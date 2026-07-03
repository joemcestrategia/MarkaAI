import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient } from '../_shared/supabase.ts'
import { parseWorkSchedule, jsDowToDartWeekday, hhmmToMin } from '../_shared/workSchedule.ts'

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

    const { professional_id, start_time, duration, shop_id, is_vip, exclude_appointment_id } = await req.json()

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
      supabase.from('employees').select('name, work_start, work_end, start_time, end_time, work_days, work_schedule, breaks').eq('id', professional_id).maybeSingle()
    ])

    if (!prof) throw new Error('Profissional não encontrado')
    const config = shop?.config || {}

    // 2. Validação: Janela de Agendamento (Dias)
    if (!is_vip) {
      const janelaDias = config.janela_agendamento_dias || 90
      const maxDate = new Date()
      maxDate.setDate(now.getDate() + janelaDias)
      if (reqStart > maxDate) {
         return new Response(JSON.stringify({ available: false, error: 'Fora da janela de agendamento permitida' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
    }

    // 3. Validação: Antecedência Mínima (Horas)
    if (!is_vip) {
      const minAdvanceHours = config.limite_minimo_agendamento_horas || 0
      const minAllowedDate = new Date(now.getTime() + minAdvanceHours * 3600000)
      if (reqStart < minAllowedDate) {
        return new Response(JSON.stringify({ available: false, error: 'Tempo de antecedência insuficiente' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
    }

    // 4. Validação: Dia de Trabalho (per-day schedule)
    const dartWeekday = jsDowToDartWeekday(reqStart.getDay())
    const schedule = parseWorkSchedule(prof as Record<string, unknown>)
    if (schedule.size === 0) {
      return new Response(JSON.stringify({ available: false, error: 'Profissional sem dias de trabalho configurados' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    const dayCfg = schedule.get(dartWeekday)
    if (!dayCfg) {
      return new Response(JSON.stringify({ available: false, error: 'Profissional não trabalha neste dia' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 5. Validação: Horário de Expediente (do dia da semana)
    const startStr = dayCfg.start
    const endStr = dayCfg.end
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

    // 5b. Validação: Pausa diária (almoço, etc.)
    if (dayCfg.break) {
      const localReqStart = new Date(reqStart.getTime() - 3 * 3600000)
      const reqStartMin = localReqStart.getUTCHours() * 60 + localReqStart.getUTCMinutes()
      const reqEndMin = reqStartMin + duration
      const brStart = hhmmToMin(dayCfg.break.start)
      const brEnd = hhmmToMin(dayCfg.break.end)
      if (reqStartMin < brEnd && reqEndMin > brStart) {
        return new Response(JSON.stringify({
          available: false,
          error: 'Conflito com a pausa do profissional',
          reasons: [`O profissional está em pausa das ${dayCfg.break.start} às ${dayCfg.break.end}.`]
        }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
    }

    // 6. Validação: Feriados (Configurados ou Pendentes com Bloqueio Automático)
    const isoDate = reqStart.toISOString().split('T')[0]
    const configurados = shop?.configured_holidays || {}
    const autoBlock = config.auto_block_holidays || false
    const pendentes = shop?.pending_holidays || []

    if (configurados[isoDate] === 'fechado') {
        return new Response(JSON.stringify({ available: false, error: 'Loja fechada (feriado)' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    if (configurados[isoDate] && typeof configurados[isoDate] === 'object') {
      const config = configurados[isoDate] as Record<string, unknown>
      if (Array.isArray(config['escala'])) {
        const escala = config['escala'] as string[]
        if (escala.length > 0 && !escala.includes(professional_id)) {
          return new Response(
            JSON.stringify({ available: false, error: 'Profissional não está na escala deste dia' }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }
      }
    }
    if (autoBlock && pendentes.includes(isoDate)) {
        return new Response(JSON.stringify({ available: false, error: 'Loja fechada (feriado pendente)' }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    if (autoBlock) {
      try {
        const year = reqStart.getFullYear()
        const holidaysRes = await fetch(`https://brasilapi.com.br/api/feriados/v1/${year}`)
        if (holidaysRes.ok) {
          const nationalHolidays = await holidaysRes.json() as Array<{ date: string }>
          const isNationalHoliday = nationalHolidays.some((h) => h.date === isoDate)
          if (isNationalHoliday) {
            return new Response(
              JSON.stringify({ available: false, error: 'Feriado nacional' }),
              { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
          }
        }
      } catch (_) {
        // BrasilAPI indisponível → fail-open intencional, não bloqueia o agendamento
      }
    }

    // 6b. Validação: Folgas do Profissional (breaks)
    const profBreaks = (prof as Record<string, unknown>).breaks as Array<Record<string, unknown>> | null
    if (profBreaks && Array.isArray(profBreaks)) {
      const localReqStart = new Date(reqStart.getTime() - 3 * 3600000)
      const reqStartMin = localReqStart.getUTCHours() * 60 + localReqStart.getUTCMinutes()
      const reqEndMin = reqStartMin + duration

      for (const folga of profBreaks) {
        const fStart = folga.start ? new Date(String(folga.start)) : null
        let fEnd = folga.end ? new Date(String(folga.end)) : null
        if (!fStart || !fEnd) continue

        // Ajuste: se a folga salva no app terminou a meia noite (00:00) significa dia inteiro selecionado no range picker
        if (fEnd.getUTCHours() === 0 && fEnd.getUTCMinutes() === 0) {
           fEnd = new Date(fEnd.getTime() + 86400000 - 1)
        }

        // Verifica se a folga cobre a data solicitada
        const dayStart = new Date(reqStart)
        dayStart.setHours(0, 0, 0, 0)
        const dayEnd = new Date(dayStart.getTime() + 86400000)
        if (fStart >= dayEnd || fEnd <= dayStart) continue

        const fType = String(folga.type || 'full_day').toLowerCase()

        if (fType === 'partial') {
          // Folga parcial: verifica colisão com start_time/end_time
          const stStr = String(folga.start_time || '')
          const etStr = String(folga.end_time || '')
          if (stStr && etStr) {
            const fStartMin = hhmmToMin(stStr)
            const fEndMin = hhmmToMin(etStr)
            if (reqStartMin < fEndMin && reqEndMin > fStartMin) {
              return new Response(JSON.stringify({
                available: false,
                error: 'Profissional em folga neste período',
                reasons: [`${prof.name || 'Profissional'} está de folga das ${stStr} às ${etStr} (${folga.notes || 'folga parcial'}).`]
              }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
            }
          }
        } else {
          // Folga de dia inteiro
          return new Response(JSON.stringify({
            available: false,
            error: 'Profissional em folga neste dia',
            reasons: [`${prof.name || 'Profissional'} está de folga o dia inteiro (${folga.notes || 'folga'}).`]
          }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
        }
      }
    }

    // 7. Validação: Conflitos de Horário (Agendamentos Existentes)
    // IMPORTANTE: pendente_pix recente (< 20 min) também conta como ocupado
    // para evitar double-booking enquanto o cliente está pagando.
    // pre_reserva (lock de checkout) também é considerada ocupada.
    const PENDING_PIX_TTL_MIN = 20
    const pendingPixCutoff = new Date(Date.now() - PENDING_PIX_TTL_MIN * 60000).toISOString()

    const { data: appointments, error: fetchError } = await supabase
      .from('appointments')
      .select('id, scheduled_at, duration_min, client_name, status, created_at')
      .eq('professional_id', professional_id)
      .not('status', 'in', '("cancelado","rejeitado","recusado","excluido")')
      .gte('scheduled_at', new Date(reqStart.getTime() - 2 * 60 * 60 * 1000).toISOString())
      .lte('scheduled_at', new Date(reqEnd.getTime() + 2 * 60 * 60 * 1000).toISOString())

    if (fetchError) throw fetchError

    const conflicting = (appointments || []).filter((appt) => {
      // Ignorar o próprio agendamento (reagendamento / pre_reserva do mesmo cliente)
      if (exclude_appointment_id && appt.id === exclude_appointment_id) return false
      const status = (appt.status || '').toString().toLowerCase()
      // Ignorar pendente_pix antigos (provavelmente abandonados)
      if (status === 'pendente_pix') {
        const createdAt = appt.created_at ? new Date(appt.created_at).toISOString() : ''
        if (!createdAt || createdAt < pendingPixCutoff) return false
      }
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
