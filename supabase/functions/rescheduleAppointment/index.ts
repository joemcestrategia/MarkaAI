import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient, createSupabaseAdminClient } from '../_shared/supabase.ts'
import { parseWorkSchedule, jsDowToDartWeekday, hhmmToMin } from '../_shared/workSchedule.ts'

// ── Push helpers ──────────────────────────────────────────────────────────────

async function getGoogleAccessTokenForFCM(serviceAccount: any): Promise<string> {
  const { default: jwt } = await import('npm:jsonwebtoken@9')
  const now = Math.floor(Date.now() / 1000)
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  }
  const token = jwt.sign(payload, serviceAccount.private_key, { algorithm: 'RS256' })
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${token}`,
  })
  const data = await res.json()
  return data.access_token
}

async function sendReschedulePush(
  supabaseAdmin: any,
  shopId: string,
  ownerId: string,
  title: string,
  body: string,
  extraData: Record<string, string>,
): Promise<void> {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey  = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) return

  // VAPID web push (PWA/web)
  try {
    await fetch(`${supabaseUrl}/functions/v1/sendPushNotification`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ user_id: ownerId, title, message: body, data: extraData }),
    })
    console.log('[PUSH] VAPID enviado para owner:', ownerId)
  } catch (e) {
    console.error('[PUSH] Erro VAPID:', e)
  }

  // FCM push (Android/iOS)
  try {
    const projectId = Deno.env.get('FCM_PROJECT_ID')
    const serviceAccountKey = Deno.env.get('FCM_SERVICE_ACCOUNT_KEY')
    if (!projectId || !serviceAccountKey) return

    const { data: tokenData } = await supabaseAdmin
      .from('fcm_tokens')
      .select('token')
      .eq('user_id', ownerId)
      .maybeSingle()

    if (!tokenData?.token) return

    const accessToken = await getGoogleAccessTokenForFCM(JSON.parse(serviceAccountKey))
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: tokenData.token,
            notification: { title, body },
            data: extraData,
            android: { priority: 'high' },
            apns: { payload: { aps: { sound: 'default', badge: 1 } } },
          },
        }),
      },
    )
    if (!res.ok) {
      console.error('[FCM] Erro ao enviar:', await res.text())
    } else {
      console.log('[FCM] Reagendamento enviado para:', ownerId)
    }
  } catch (e) {
    console.error('[FCM] Erro:', e)
  }
}

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
      supabaseAdmin.from('employees').select('work_start, work_end, start_time, end_time, work_days, work_schedule').eq('id', professionalId).maybeSingle()
    ])

    if (!prof) throw new Error('Profissional não encontrado')
    const config = shop?.config || {}

    // Validação de horário de expediente (per-day schedule + pausa).
    const dartWeekday = jsDowToDartWeekday(reqStart.getDay())
    const schedule = parseWorkSchedule(prof as Record<string, unknown>)
    if (schedule.size === 0) {
      return new Response(JSON.stringify({ error: 'Profissional sem dias de trabalho configurados' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    const dayCfg = schedule.get(dartWeekday)
    if (!dayCfg) {
      return new Response(JSON.stringify({ error: 'Profissional não trabalha neste dia' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const startStr = dayCfg.start
    const endStr = dayCfg.end
    const [startH, startM] = startStr.split(':').map(Number)
    const [endH, endM] = endStr.split(':').map(Number)

    const dayStart = new Date(reqStart)
    dayStart.setHours(startH, startM, 0, 0)
    const dayEnd = new Date(reqStart)
    dayEnd.setHours(endH, endM, 0, 0)

    if (reqStart < dayStart || reqEnd > dayEnd) {
      return new Response(JSON.stringify({ error: 'Fora do horário de expediente do profissional' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (dayCfg.break) {
      const reqStartMin = reqStart.getHours() * 60 + reqStart.getMinutes()
      const reqEndMin = reqStartMin + duration
      const brStart = hhmmToMin(dayCfg.break.start)
      const brEnd = hhmmToMin(dayCfg.break.end)
      if (reqStartMin < brEnd && reqEndMin > brStart) {
        return new Response(JSON.stringify({
          error: `Conflito com a pausa do profissional (${dayCfg.break.start}–${dayCfg.break.end})`
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
    }

    // 4. Verificar conflitos EXCLUINDO o agendamento atual
    const { data: appointments, error: conflictError } = await supabaseAdmin
      .from('appointments')
      .select('id, scheduled_at, duration_min')
      .eq('professional_id', professionalId)
      .neq('id', appointmentId) // EXCLUIR O ATUAL
      .not('status', 'in', '("cancelado","rejeitado","recusado","excluido")')
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
      whatsapp_scheduled_send_at: null,
      whatsapp_reminder_status: 'pending',
      whatsapp_reminder_retry_count: 0,
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

    // ── Pós-update: push + activity log ─────────────────────────────────────
    try {
      // Busca owner da loja
      const { data: shopData } = await supabaseAdmin
        .from('shops')
        .select('owner_id, name')
        .eq('id', shopId)
        .maybeSingle()

      const ownerId: string = shopData?.owner_id || shopId
      const clientName: string = currentAppt.client_name || 'Cliente'
      const serviceName: string = updateData.service_name || currentAppt.service_name || 'Serviço'
      const profName: string = updateData.professional_name || currentAppt.professional_name || ''

      const dt = new Date(newDateISO)
      const dateStr = `${dt.getDate().toString().padStart(2, '0')}/${(dt.getMonth()+1).toString().padStart(2,'0')}/${dt.getFullYear()}`
      const timeStr = `${dt.getHours().toString().padStart(2,'0')}:${dt.getMinutes().toString().padStart(2,'0')}`
      const pushMsg = `${clientName} reagendou — ${serviceName} para ${dateStr} às ${timeStr}`

      // Push direto ao dono (fix: não depende do webhook)
      await sendReschedulePush(
        supabaseAdmin,
        shopId,
        ownerId,
        '🔄 Reagendamento',
        pushMsg,
        { appointment_id: appointmentId, scheduled_at: newDateISO },
      )

      // Activity log
      await supabaseAdmin.from('shop_activity_log').insert({
        shop_id: shopId,
        appointment_id: appointmentId,
        event_type: 'reagendamento',
        actor_type: 'cliente',
        actor_name: clientName,
        description: pushMsg,
        metadata: {
          old_scheduled_at: currentAppt.scheduled_at,
          new_scheduled_at: newDateISO,
          service_name: serviceName,
          professional_name: profName,
        },
      })
    } catch (postErr) {
      console.error('[POST_UPDATE] Erro em push/log (não crítico):', postErr)
    }
    // ────────────────────────────────────────────────────────────────────────

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
