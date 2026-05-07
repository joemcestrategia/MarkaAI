import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseClient(req)
    try {
      const { data, error: authError } = await supabase.auth.getUser()
      if (authError || !data?.user) {
        return new Response(
          JSON.stringify({ error: 'Usuário não autenticado' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    } catch (_) {
      return new Response(
        JSON.stringify({ error: 'Usuário não autenticado' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { professional_id, start_time, duration, shop_id } = await req.json()

    if (!professional_id || !start_time || !duration) {
      return new Response(
        JSON.stringify({ error: 'Dados incompletos para validação' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const reqStart = new Date(start_time)
    const reqEnd = new Date(reqStart.getTime() + duration * 60000)
    const now = new Date()

    // 1. Buscar Dados da Loja e Profissional
    const [{ data: shop }, { data: prof }] = await Promise.all([
      supabase.from('shops').select('config, configured_holidays, pending_holidays').eq('id', shop_id).maybeSingle(),
      supabase.from('employees').select('name, work_start, work_end, work_days').eq('id', professional_id).maybeSingle()
    ])

    if (!prof) throw new Error('Profissional não encontrado')
    const config = shop?.config || {}

    // 2. Validação: Janela de Agendamento (Dias)
    const janelaDias = config.janela_agendamento_dias || 90
    const maxDate = new Date()
    maxDate.setDate(now.getDate() + janelaDias)
    if (reqStart > maxDate) {
       return new Response(JSON.stringify({ available: false, error: 'Fora da janela de agendamento permitida' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 3. Validação: Antecedência Mínima (Horas)
    const minAdvanceHours = config.limite_minimo_agendamento_horas || 0
    const minAllowedDate = new Date(now.getTime() + minAdvanceHours * 3600000)
    if (reqStart < minAllowedDate) {
      return new Response(JSON.stringify({ available: false, error: 'Tempo de antecedência insuficiente' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 4. Validação: Dia de Trabalho
    const dayOfWeek = reqStart.getDay() // 0 = Domingo, 1 = Segunda...
    // Converter getDay() para o padrão do Marcai (1=Seg, 7=Dom?) No JS 0=Dom, 6=Sab.
    // No booking_page.dart, weekday do Dart é 1=Seg, 7=Dom.
    const dartWeekday = dayOfWeek === 0 ? 7 : dayOfWeek
    // fix: bloquear dias sem equipe ativa para qualquer estabelecimento
    // work_days NULL ou vazio → profissional sem dias configurados → rejeitar
    const workDays = Array.isArray(prof.work_days) ? prof.work_days.map(Number) : []
    if (workDays.length === 0) {
      return new Response(JSON.stringify({ available: false, error: 'Profissional sem dias de trabalho configurados' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    if (!workDays.includes(dartWeekday)) {
      return new Response(JSON.stringify({ available: false, error: 'Profissional não trabalha neste dia' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 5. Validação: Horário de Expediente
    const startStr = prof.work_start || "08:00"
    const endStr = prof.work_end || "18:00"
    const [startH, startM] = startStr.split(':').map(Number)
    const [endH, endM] = endStr.split(':').map(Number)
    
    const dayStart = new Date(reqStart)
    dayStart.setHours(startH, startM, 0, 0)
    const dayEnd = new Date(reqStart)
    dayEnd.setHours(endH, endM, 0, 0)

    if (reqStart < dayStart || reqEnd > dayEnd) {
      const profName = prof.name || 'Profissional'
      const fmt = (d: Date) => d.toISOString().slice(11, 16)
      const expedienteReasons: string[] = []
      if (reqStart < dayStart) {
        expedienteReasons.push(`O serviço inicia às ${fmt(reqStart)}, mas o expediente de ${profName} começa às ${fmt(dayStart)}.`)
      }
      if (reqEnd > dayEnd) {
        expedienteReasons.push(`O serviço termina às ${fmt(reqEnd)}, mas o expediente de ${profName} encerra às ${fmt(dayEnd)}.`)
      }
      return new Response(JSON.stringify({ available: false, error: 'Fora do horário de expediente do profissional', reasons: expedienteReasons }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 6. Validação: Feriados (Configurados ou Pendentes com Bloqueio Automático)
    const isoDate = reqStart.toISOString().split('T')[0]
    const configurados = shop?.configured_holidays || {}
    const autoBlock = config.auto_block_holidays || false
    const pendentes = shop?.pending_holidays || []

    if (configurados[isoDate] === 'fechado') {
        return new Response(JSON.stringify({ available: false, error: 'Loja fechada (feriado)' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    if (autoBlock && pendentes.includes(isoDate)) {
        return new Response(JSON.stringify({ available: false, error: 'Loja fechada (feriado pendente)' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 7. Validação: Conflitos de Horário (Agendamentos Existentes)
    const { data: appointments, error: fetchError } = await supabase
      .from('appointments')
      .select('scheduled_at, duration_min, client_name')
      .eq('professional_id', professional_id)
      .not('status', 'in', '("cancelado","rejeitado","recusado","excluido","pendente_pix")')
      .gte('scheduled_at', new Date(reqStart.getTime() - 2 * 60 * 60 * 1000).toISOString())
      .lte('scheduled_at', new Date(reqEnd.getTime() + 2 * 60 * 60 * 1000).toISOString())

    if (fetchError) throw fetchError

    const conflicting = (appointments || []).filter((appt) => {
      const apptStart = new Date(appt.scheduled_at)
      const apptDuration = appt.duration_min || 30
      const apptEnd = new Date(apptStart.getTime() + apptDuration * 60000)
      return reqStart < apptEnd && reqEnd > apptStart
    })

    const fmt = (d: Date) => d.toISOString().slice(11, 16)
    const conflictReasons: string[] = conflicting.map((appt) => {
      const apptStart = new Date(appt.scheduled_at)
      const apptEnd = new Date(apptStart.getTime() + (appt.duration_min || 30) * 60000)
      const clientName = appt.client_name || 'cliente'
      return `Conflito com agendamento de ${clientName} das ${fmt(apptStart)} às ${fmt(apptEnd)}.`
    })

    return new Response(
      JSON.stringify({
        available: conflicting.length === 0,
        conflicts: conflicting.length,
        ...(conflicting.length > 0 ? { reasons: conflictReasons } : {}),
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Erro em checkAvailability:', error)
    return new Response(
      JSON.stringify({ error: 'Erro interno ao validar disponibilidade' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
