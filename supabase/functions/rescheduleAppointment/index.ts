import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient, createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseClient(req)
    const supabaseAdmin = createSupabaseAdminClient()
    let user: any
    try {
      const { data, error: authError } = await supabase.auth.getUser()
      if (authError || !data?.user) {
        return new Response(
          JSON.stringify({ error: 'Usuário não autenticado' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      user = data.user
    } catch (_) {
      return new Response(
        JSON.stringify({ error: 'Usuário não autenticado' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { 
      appointmentId, 
      newDateISO, 
      newServiceId, 
      newProfessionalId,
      newServiceName,
      newPrice 
    } = await req.json()

    if (!appointmentId || !newDateISO) {
      return new Response(
        JSON.stringify({ error: 'Dados incompletos para reagendamento' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 1. Buscar agendamento atual
    const { data: currentAppt, error: fetchError } = await supabaseAdmin
      .from('appointments')
      .select('*')
      .eq('id', appointmentId)
      .single()

    if (fetchError || !currentAppt) {
      return new Response(
        JSON.stringify({ error: 'Agendamento não encontrado' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Verificar se o usuário tem permissão (é o dono ou admin da loja)
    // Para simplificar, assumimos que se o cliente_id bate, ele pode reagendar.
    if (currentAppt.client_id !== user.id) {
       // Check if user is professional/admin of the shop
       const { data: isStaff } = await supabaseAdmin
         .from('employees')
         .select('id')
         .eq('user_id', user.id)
         .eq('shop_id', currentAppt.shop_id)
         .maybeSingle()
       
       if (!isStaff) {
         return new Response(
           JSON.stringify({ error: 'Sem permissão para reagendar este compromisso' }),
           { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
         )
       }
    }

    const shopId = currentAppt.shop_id
    const professionalId = newProfessionalId || currentAppt.professional_id
    const serviceId = newServiceId || currentAppt.service_id

    // 2. Buscar duração do novo serviço
    let duration = currentAppt.duration_min || 30
    if (newServiceId && newServiceId !== currentAppt.service_id) {
      const { data: service } = await supabaseAdmin
        .from('services')
        .select('duration_min')
        .eq('id', newServiceId)
        .single()
      if (service) duration = service.duration_min
    }

    const reqStart = new Date(newDateISO)
    const reqEnd = new Date(reqStart.getTime() + duration * 60000)

    // 3. Validação de Disponibilidade (Reaproveitando lógica de checkAvailability)
    const [{ data: shop }, { data: prof }] = await Promise.all([
      supabaseAdmin.from('shops').select('config, configured_holidays, pending_holidays').eq('id', shopId).maybeSingle(),
      supabaseAdmin.from('employees').select('work_start, work_end, work_days').eq('id', professionalId).maybeSingle()
    ])

    if (!prof) throw new Error('Profissional não encontrado')
    const config = shop?.config || {}

    // Validação de horário de expediente, feriados, etc.
    const dayOfWeek = reqStart.getDay()
    const dartWeekday = dayOfWeek === 0 ? 7 : dayOfWeek
    const workDays = Array.isArray(prof.work_days) ? prof.work_days.map(Number) : [1,2,3,4,5,6]
    if (!workDays.includes(dartWeekday)) {
      return new Response(JSON.stringify({ error: 'Profissional não trabalha neste dia' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const startStr = prof.work_start || "08:00"
    const endStr = prof.work_end || "18:00"
    const [startH, startM] = startStr.split(':').map(Number)
    const [endH, endM] = endStr.split(':').map(Number)
    
    const dayStart = new Date(reqStart)
    dayStart.setHours(startH, startM, 0, 0)
    const dayEnd = new Date(reqStart)
    dayEnd.setHours(endH, endM, 0, 0)

    if (reqStart < dayStart || reqEnd > dayEnd) {
      return new Response(JSON.stringify({ error: 'Fora do horário de expediente do profissional' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 4. Verificar conflitos EXCLUINDO o agendamento atual
    const { data: appointments, error: conflictError } = await supabaseAdmin
      .from('appointments')
      .select('id, scheduled_at, duration_min')
      .eq('professional_id', professionalId)
      .neq('id', appointmentId) // EXCLUIR O ATUAL
      .not('status', 'in', '("cancelado","rejeitado","excluido")')
      .gte('scheduled_at', new Date(reqStart.getTime() - 2 * 60 * 60 * 1000).toISOString())
      .lte('scheduled_at', new Date(reqEnd.getTime() + 2 * 60 * 60 * 1000).toISOString())

    if (conflictError) throw conflictError

    const isConflicting = (appointments || []).some((appt) => {
      const apptStart = new Date(appt.scheduled_at)
      const apptDuration = appt.duration_min || 30
      const apptEnd = new Date(apptStart.getTime() + apptDuration * 60000)
      return reqStart < apptEnd && reqEnd > apptStart
    })

    if (isConflicting) {
      return new Response(JSON.stringify({ error: 'Este horário já está ocupado' }), { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // 5. Executar o UPDATE
    const updateData: any = {
      scheduled_at: reqStart.toISOString(),
      end_at: reqEnd.toISOString(),
      duration_min: duration,
      professional_id: professionalId,
      updated_at: new Date().toISOString(),
    }

    if (newServiceId) updateData.service_id = newServiceId
    if (newServiceName) updateData.service_name = newServiceName
    if (newPrice !== undefined) updateData.total_price = newPrice
    // Se mudou o profissional, talvez queiramos o nome dele também
    if (newProfessionalId) {
       const { data: pDoc } = await supabaseAdmin.from('employees').select('name').eq('id', newProfessionalId).single()
       if (pDoc) updateData.professional_name = pDoc.name
    }

    const { error: finalUpdateError } = await supabaseAdmin
      .from('appointments')
      .update(updateData)
      .eq('id', appointmentId)

    if (finalUpdateError) throw finalUpdateError

    return new Response(
      JSON.stringify({ message: 'Agendamento reagendado com sucesso', id: appointmentId }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Erro em rescheduleAppointment:', error)
    return new Response(
      JSON.stringify({ error: error.message || 'Erro interno ao reagendar' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
