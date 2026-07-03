import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

// ──────────────────────────────────────────────────────────────
// Formatadores de data/hora
// ──────────────────────────────────────────────────────────────

/** Formata data no padrão dd/MM/yyyy pegando direto da string ISO (sem shift de fuso) */
function formatDate(isoDate: string): string {
  // isoDate ex: "2026-06-23T18:00:00Z" ou "2026-06-23T18:00:00+00:00"
  if (!isoDate || isoDate.length < 10) return ''
  const year = isoDate.substring(0, 4)
  const month = isoDate.substring(5, 7)
  const day = isoDate.substring(8, 10)
  return `${day}/${month}/${year}`
}

/** Formata hora no padrão HH:mm pegando direto da string ISO */
function formatTime(isoDate: string): string {
  if (!isoDate || isoDate.length < 16) return ''
  return isoDate.substring(11, 16)
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
      name: templateName,
      language: { code: 'pt_BR' },
      components: [
        {
          type: 'body',
          parameters: [
            { type: 'text', text: clientName },
            { type: 'text', text: businessName },
            { type: 'text', text: serviceName },     // O template da Meta espera o SERVIÇO na variável 3
            { type: 'text', text: appointmentDate }, // O template da Meta espera a DATA na variável 4
            { type: 'text', text: appointmentTime }  // O template da Meta espera a HORA na variável 5
          ]
        }
      ]
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

    // Permite forçar a execução via POST body { "force": true, "testPhone": "996759238" }
    let force = false;
    let testPhone = '';
    try {
      const reqBody = await req.clone().json();
      if (reqBody.force === true) force = true;
      if (reqBody.testPhone) testPhone = reqBody.testPhone;
    } catch (e) {
      // Body vazio ou inválido, segue normal
    }

    // ────────────────────────────────────────────────────────
    // Regra: Lembretes apenas no período da manhã (08:00 às 10:59 BRT)
    // ────────────────────────────────────────────────────────
    const brtNow = new Date(now.getTime() - 3 * 60 * 60 * 1000)
    if (!force && (brtNow.getUTCHours() < 8 || brtNow.getUTCHours() > 10)) {
      console.log(`[send-reminders] Ignorando: Agora são ${brtNow.getUTCHours()}h. Configurado para rodar apenas de manhã (08h-10h).`)
      return new Response(
        JSON.stringify({ ok: true, skipped: true, reason: 'Outside 08:00-10:59 BRT window' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ────────────────────────────────────────────────────────
    // Busca agendamentos elegíveis para lembrete:
    // - reminder_sent = false
    // - status não cancelado nem já confirmado pelo cliente
    // - Agendamento deve estar entre 48h e 72h no futuro
    // ────────────────────────────────────────────────────────
    const minTimeMs = now.getTime() + 48 * 60 * 60 * 1000;
    const maxTimeMs = now.getTime() + 72 * 60 * 60 * 1000;
    const minDateISO = new Date(minTimeMs).toISOString();
    const maxDateISO = new Date(maxTimeMs).toISOString();

    let query = supabase
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
          plan,
          config,
          shop_whatsapp_config (
            wa_phone_number_id,
            wa_access_token,
            wa_template_reminder_name,
            is_active
          )
        )
      `)
      .eq('shops.plan', 'pro')
      .eq('reminder_sent', false)
      .not('status', 'in', '("cancelado","cancelled","confirmed_by_client")')
      .limit(15) // Pega apenas 15 por vez para evitar bloqueio de SPAM na Meta

    if (force) {
      // Se forçado, ignora a janela de 48h-72h e pega qualquer agendamento no futuro não lembrado ainda
      query = query.gt('scheduled_at', now.toISOString())
      if (testPhone) {
        query = query.like('client_phone', `%${testPhone}%`)
      }
    } else {
      query = query.gt('scheduled_at', minDateISO).lte('scheduled_at', maxDateISO)
    }

    const { data: appointments, error: queryError } = await query

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
        // Armazena o wamid para que o webhook de confirmação/cancelamento
        // encontre o agendamento exato via context.id
        const { error: updateError } = await supabase
          .from('appointments')
          .update({
            reminder_sent: true,
            wa_reminder_message_id: sendResult.messageId || null,
          })
          .eq('id', appt.id)
          .eq('reminder_sent', false) // Garante que não houve envio concorrente

        if (updateError) {
          console.warn(`[send-reminders] Erro ao marcar reminder_sent para ${appt.id}:`, updateError.message)
        }

        // Log de sucesso
        try {
          const requestPayload = {
            clientName,
            businessName,
            serviceName,
            appointmentDate,
            appointmentTime
          }

          await supabase.from('whatsapp_send_log').insert({
            shop_id: appt.shop_id,
            to_phone: appt.client_phone.replace(/\D/g, ''),
            template_name: templateName,
            status: 'success',
            response_json: sendResult.rawResponse,
            request_payload: requestPayload,
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
