import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// ──────────────────────────────────────────────────────────────
// Formatadores de data/hora
// ──────────────────────────────────────────────────────────────

/** Formata data no padrão dd/MM/yyyy (fuso local do servidor — UTC) */
function formatDate(isoDate: string): string {
  const d = new Date(isoDate)
  // Ajuste para timezone Brasil (UTC-3)
  const brt = new Date(d.getTime() - 3 * 60 * 60 * 1000)
  const day = brt.getUTCDate().toString().padStart(2, '0')
  const month = (brt.getUTCMonth() + 1).toString().padStart(2, '0')
  const year = brt.getUTCFullYear()
  return `${day}/${month}/${year}`
}

/** Formata hora no padrão HH:mm (fuso local do servidor — UTC-3) */
function formatTime(isoDate: string): string {
  const d = new Date(isoDate)
  const brt = new Date(d.getTime() - 3 * 60 * 60 * 1000)
  const h = brt.getUTCHours().toString().padStart(2, '0')
  const m = brt.getUTCMinutes().toString().padStart(2, '0')
  return `${h}:${m}`
}

// ──────────────────────────────────────────────────────────────
// Envio do template de lembrete via Meta Cloud API
// ──────────────────────────────────────────────────────────────

interface SendReminderResult {
  success: boolean
  messageId?: string
  errorCode?: string
  rawResponse?: unknown
}

async function sendReminderTemplate(params: {
  phoneNumberId: string
  accessToken: string
  templateName: string
  toPhone: string
  clientName: string
  businessName: string
  appointmentDate: string
  appointmentTime: string
  serviceName: string
}): Promise<SendReminderResult> {
  const {
    phoneNumberId,
    accessToken,
    templateName,
    toPhone,
    clientName,
    businessName,
    appointmentDate,
    appointmentTime,
    serviceName,
  } = params

  // Garantir formato E.164 sem "+" para a Meta API
  let to = toPhone.replace(/\D/g, '')
  
  // Regra especial para Brasil (55)
  // Meta recomenda remover o 9 para DDDs fora de 11-28 para garantir entrega
  if (to.startsWith('55') && to.length === 13) {
    const ddd = parseInt(to.substring(2, 4), 10)
    if (ddd > 28) {
      console.log(`[send-reminders] Aplicando normalização de 9º dígito para DDD ${ddd}`)
      to = to.substring(0, 4) + to.substring(5)
    }
  }

  const metaPayload = {
    messaging_product: 'whatsapp',
    to,
    type: 'template',
    template: {
      name: 'hello_world',
      language: { code: 'en_US' },
    },
  }

  try {
    const res = await fetch(
      `https://graph.facebook.com/v18.0/${phoneNumberId}/messages`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(metaPayload),
      },
    )

    const data = await res.json()

    if (res.ok && data?.messages?.[0]?.id) {
      return { success: true, messageId: data.messages[0].id, rawResponse: data }
    }

    const errorCode = data?.error?.code?.toString() ?? `HTTP_${res.status}`
    return { success: false, errorCode, rawResponse: data }
  } catch (err) {
    console.error('[send-reminders] fetch error:', err)
    return { success: false, errorCode: 'NETWORK_ERROR', rawResponse: String(err) }
  }
}

// ──────────────────────────────────────────────────────────────
// Handler principal
// ──────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  const results = {
    sent: 0,
    skipped: 0,
    errors: 0,
    details: [] as string[],
  }

  try {
    const now = new Date()

    // ────────────────────────────────────────────────────────
    // Busca agendamentos elegíveis para lembrete:
    // - reminder_sent = false
    // - status não cancelado nem já confirmado pelo cliente
    // - agendamento ainda não passou
    // - (scheduled_at - now) <= reminder_hours_before da loja (padrão 48h)
    // - integração WhatsApp ativa e configurada na loja
    // ────────────────────────────────────────────────────────
    const { data: appointments, error: queryError } = await supabase
      .from('appointments')
      .select(`
        id,
        client_name,
        client_phone,
        service_name,
        scheduled_at,
        shop_id,
        shops!inner (
          id,
          name,
          config,
          shop_whatsapp_config (
            wa_phone_number_id,
            wa_access_token,
            wa_template_reminder_name,
            is_active
          )
        )
      `)
      .eq('reminder_sent', false)
      .not('status', 'in', '("cancelado","cancelled","confirmed_by_client")')
      .gt('scheduled_at', now.toISOString())
      .limit(50)

    if (queryError) {
      console.error('[send-reminders] Erro na query principal:', queryError.message)
      return new Response(
        JSON.stringify({ ok: false, error: queryError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (!appointments || appointments.length === 0) {
      console.log('[send-reminders] Nenhum agendamento elegível encontrado.')
      return new Response(
        JSON.stringify({ ok: true, ...results }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    console.log(`[send-reminders] ${appointments.length} agendamentos candidatos para verificação`)

    for (const appt of appointments) {
      const shop = appt.shops as any
      const whatsappConfig = shop?.shop_whatsapp_config

      // Lógica de Ativação:
      // 1. Se existir config específica, respeitamos o is_active dela.
      // 2. Se NÃO existir config, usamos o fallback global se a loja permitir (config.whatsapp_enabled)
      
      const isConfigActive = whatsappConfig?.is_active ?? (shop?.config?.whatsapp_enabled !== false);
      
      if (!isConfigActive) {
        results.skipped++
        continue
      }

      const phoneNumberId = whatsappConfig?.wa_phone_number_id || Deno.env.get('GLOBAL_WA_PHONE_NUMBER_ID');
      const accessToken = whatsappConfig?.wa_access_token || Deno.env.get('GLOBAL_WA_ACCESS_TOKEN');

      if (!phoneNumberId || !accessToken) {
        results.skipped++
        results.details.push(`Appt ${appt.id}: credenciais Meta não encontradas (loja ou global)`)
        continue
      }
      if (!appt.client_phone) {
        results.skipped++
        results.details.push(`Appt ${appt.id}: sem telefone do cliente`)
        continue
      }

      // Calcular janela de lembrete (padrão 48h)
      const reminderHours = parseInt(shop?.config?.reminder_hours_before ?? '48', 10) || 48
      const reminderWindowMs = reminderHours * 60 * 60 * 1000
      const scheduledAt = new Date(appt.scheduled_at)
      const diffMs = scheduledAt.getTime() - now.getTime()

      // Ainda fora da janela de lembrete — pular
      if (diffMs > reminderWindowMs) {
        results.skipped++
        continue
      }

      const templateName = whatsappConfig?.wa_template_reminder_name || Deno.env.get('GLOBAL_WA_REMINDER_TEMPLATE') || 'markaai_reminder'
      const appointmentDate = formatDate(appt.scheduled_at)
      const appointmentTime = formatTime(appt.scheduled_at)
      const clientName = appt.client_name || 'Cliente'
      const businessName = shop?.name || 'Estabelecimento'
      const serviceName = appt.service_name || 'Serviço'

      console.log(`[send-reminders] Enviando lembrete para appt ${appt.id} | ${clientName} | ${appointmentDate} ${appointmentTime}`)

      // Enviar via Meta Cloud API
      const sendResult = await sendReminderTemplate({
        phoneNumberId: phoneNumberId,
        accessToken: accessToken,
        templateName,
        toPhone: appt.client_phone,
        clientName,
        businessName,
        appointmentDate,
        appointmentTime,
        serviceName,
      })

      if (sendResult.success) {
        // Marcar como enviado (idempotência — lock otimista)
        const { error: updateError } = await supabase
          .from('appointments')
          .update({ reminder_sent: true })
          .eq('id', appt.id)
          .eq('reminder_sent', false) // Garante que não houve envio concorrente

        if (updateError) {
          console.warn(`[send-reminders] Erro ao marcar reminder_sent para ${appt.id}:`, updateError.message)
        }

        // Log de sucesso
        try {
          await supabase.from('whatsapp_send_log').insert({
            shop_id: appt.shop_id,
            to_phone: appt.client_phone.replace(/\D/g, ''),
            template_name: templateName,
            status: 'success',
            response_json: sendResult.rawResponse,
          })
        } catch (e: any) {
          console.warn('[send-reminders] Erro ao salvar log de sucesso:', e.message)
        }

        results.sent++
        results.details.push(`✅ Appt ${appt.id}: enviado (msg_id: ${sendResult.messageId})`)
      } else {
        // Log de erro
        try {
          await supabase.from('whatsapp_send_errors').insert({
            appointment_id: appt.id,
            shop_id: appt.shop_id,
            error_code: sendResult.errorCode,
            raw_response: sendResult.rawResponse,
            attempt_number: 1,
          })
        } catch (e: any) {
          console.error('[send-reminders] Erro ao salvar log de erro:', e.message)
        }

        results.errors++
        results.details.push(`❌ Appt ${appt.id}: erro ${sendResult.errorCode}`)
        console.error(`[send-reminders] Falha no envio para appt ${appt.id}:`, sendResult.errorCode)
      }
    }

    console.log('[send-reminders] Resultado final:', results)
    return new Response(
      JSON.stringify({ ok: true, ...results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error: any) {
    console.error('[send-appointment-reminders] Erro inesperado:', error)
    return new Response(
      JSON.stringify({ ok: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
