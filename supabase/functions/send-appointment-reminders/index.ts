import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'
import { checkWhatsAppReminderEligibility } from '../_shared/reminder-eligibility.ts'

// ──────────────────────────────────────────────────────────────
// Formatadores de data/hora
// ──────────────────────────────────────────────────────────────

function formatDate(isoDate: string): string {
  if (!isoDate || isoDate.length < 10) return ''
  const year = isoDate.substring(0, 4)
  const month = isoDate.substring(5, 7)
  const day = isoDate.substring(8, 10)
  return `${day}/${month}/${year}`
}

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

  let to = toPhone.replace(/\D/g, '')
  
  if (to.startsWith('55') && to.length === 13) {
    const ddd = parseInt(to.substring(2, 4), 10)
    if (ddd > 28) {
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
            { type: 'text', text: serviceName },
            { type: 'text', text: appointmentDate },
            { type: 'text', text: appointmentTime }
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
    return { success: false, errorCode: 'NETWORK_ERROR', rawResponse: String(err) }
  }
}

// ──────────────────────────────────────────────────────────────
// Notificação Push Lojista (Reutilizando a mesma lógica do webhook)
// ──────────────────────────────────────────────────────────────
async function notifyOwnerPush(
  supabase: any,
  ownerId: string,
  title: string,
  body: string
): Promise<void> {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    await fetch(`${supabaseUrl}/functions/v1/sendPushNotification`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ user_id: ownerId, title, message: body }),
    })
  } catch (e) {
    console.error('[send-reminders] Erro ao notificar dono por push:', e)
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
    failed: 0,
    errors: 0,
    details: [] as string[],
  }

  try {
    const realNow = new Date()
    // ATENÇÃO: As datas no banco de dados (scheduled_at e whatsapp_scheduled_send_at)
    // são salvas pela aplicação Flutter como se fossem locais, mas a string ISO
    // não carrega fuso, o que faz o Postgres interpretá-las como UTC.
    // Exemplo: 08:00 BRT vira 08:00 UTC no banco (que na verdade é 05:00 BRT).
    // Para consultar corretamente na cronjob sem estourar o limite 3 horas antes,
    // precisamos subtrair 3 horas do "now" atual para ele virar o "falso UTC" do banco.
    const fakeDbBrtNow = new Date(realNow.getTime() - 3 * 60 * 60 * 1000);
    const now = fakeDbBrtNow; // Usado daqui pra frente nas consultas e lógicas de envio

    let force = false;
    let appointmentId = '';

    try {
      const reqBody = await req.clone().json();
      if (reqBody.force === true) force = true;
      if (reqBody.appointmentId) appointmentId = reqBody.appointmentId;
    } catch (e) {
      // Body vazio ou inválido, segue normal
    }

    // Busca agendamentos base:
    let query = supabase
      .from('appointments')
      .select(`
        id,
        client_name,
        client_phone,
        service_name,
        scheduled_at,
        created_at,
        shop_id,
        whatsapp_reminder_status,
        whatsapp_scheduled_send_at,
        whatsapp_reminder_retry_count,
        shops!inner (
          id,
          name,
          owner_id,
          plan_id,
          config,
          shop_whatsapp_config (
            wa_phone_number_id,
            wa_access_token,
            wa_template_reminder_name,
            is_active
          )
        )
      `)
      .eq('shops.plan_id', 'pro')

    if (appointmentId) {
      query = query.eq('id', appointmentId)
    } else {
      // Fluxo Cron Automático
      // Inclui NULL (novos agendamentos que ainda não tiveram o campo preenchido)
      query = query
        .in('status', ['agendado', 'confirmado'])
        .eq('whatsapp_reminder_status', 'pending')
        .or(`whatsapp_scheduled_send_at.is.null,whatsapp_scheduled_send_at.lte.${now.toISOString()}`)
        .limit(100)
    }

    const { data: appointments, error: queryError } = await query

    if (queryError) {
      return new Response(
        JSON.stringify({ ok: false, error: queryError.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    if (!appointments || appointments.length === 0) {
      return new Response(
        JSON.stringify({ ok: true, ...results }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    for (const appt of appointments) {
      const shop = appt.shops as any
      
      // Robustez: caso o Supabase retorne um array ou objeto (dependendo da inferência da FK)
      const whatsappConfig = Array.isArray(shop?.shop_whatsapp_config) 
        ? shop?.shop_whatsapp_config[0] 
        : shop?.shop_whatsapp_config;

      const isConfigActive = whatsappConfig?.is_active ?? (shop?.config?.whatsapp_enabled !== false);
      
      if (!isConfigActive) {
        results.skipped++
        continue
      }

      // ──────────────────────────────────────────────────────
      // Computar scheduled_send_at on-the-fly se NULL
      // (agendamentos novos criados após a migration não têm o campo preenchido)
      // ──────────────────────────────────────────────────────
      
      let scheduledSendAt: string | null = appt.whatsapp_scheduled_send_at;
      let wasNullScheduled = false;
      if (!scheduledSendAt && !force) {
        wasNullScheduled = true;
        const shopConfig = shop?.config || {};
        const reminderValue = parseFloat(String(shopConfig?.reminder_time_value || '48'));
        const reminderUnit = String(shopConfig?.reminder_time_unit || 'hours').toLowerCase();
        const scheduledAt = new Date(appt.scheduled_at);

        let ms: number;
        if (reminderUnit === 'hours') ms = reminderValue * 60 * 60 * 1000;
        else if (reminderUnit === 'days') ms = reminderValue * 24 * 60 * 60 * 1000;
        else ms = reminderValue * 60 * 1000; // minutes

        scheduledSendAt = new Date(scheduledAt.getTime() - ms).toISOString();

        // Persistir para que futuras execuções não precisem recomputar
        await supabase.from('appointments').update({
          whatsapp_scheduled_send_at: scheduledSendAt
        }).eq('id', appt.id);
      }
      
      // ──────────────────────────────────────────────────────
      // Elegibilidade (Cron vs Force)
      // ──────────────────────────────────────────────────────
      
      if (!force) {
        const eligibility = checkWhatsAppReminderEligibility(
          scheduledSendAt,
          appt.scheduled_at,
          now
        );

        if (eligibility.action === 'skip') {
          results.skipped++;
          continue;
        }

        if (eligibility.action === 'expired') {
          // Registro neutro: sai da fila, não manda push de erro e não exibe tag de alerta.
          await supabase.from('appointments').update({
            whatsapp_reminder_status: 'expired',
            whatsapp_reminder_failure_summary: eligibility.reason
          }).eq('id', appt.id).eq('whatsapp_reminder_status', 'pending');
          
          results.skipped++;
          results.details.push(`⏭️ Appt ${appt.id}: Expired (${eligibility.reason})`);
          continue;
        }

        if (eligibility.action === 'fail') {
          const retryCount = appt.whatsapp_reminder_retry_count || 0;
          
          if (wasNullScheduled && new Date(appt.scheduled_at).getTime() > now.getTime()) {
            // Catch-up: estava NULL, envia mesmo com tolerancia estourada
            results.details.push(`🔧 Appt ${appt.id}: Tolerancia estourada mas scheduled_send_at estava NULL — enviando catch-up`);
          } else if (retryCount < 2) {
            // Tenta ate 3x (retry 0, 1, 2 = 3 tentativas no total)
            await supabase.from('appointments').update({
              whatsapp_reminder_retry_count: retryCount + 1,
            }).eq('id', appt.id);
            results.details.push(`🔄 Appt ${appt.id}: Retry ${retryCount + 1}/3 (${eligibility.reason}) — tentando envio`);
          } else {
            // 3 tentativas esgotadas — falha definitiva
            await supabase.from('appointments').update({
              whatsapp_reminder_status: 'failed',
              whatsapp_reminder_failed_at: realNow.toISOString(),
              whatsapp_reminder_failure_summary: eligibility.reason
            }).eq('id', appt.id).eq('whatsapp_reminder_status', 'pending');

            const clientName = appt.client_name || 'Cliente'
            const apptDate = formatDate(appt.scheduled_at)
            const apptTime = formatTime(appt.scheduled_at)

            await notifyOwnerPush(
              supabase,
              shop.owner_id,
              "Lembrete Não Enviado",
              `Não foi possível enviar a confirmação para ${clientName} — agendamento ${apptDate} às ${apptTime}. Entre em contato manualmente.`
            );

            results.failed++;
            results.details.push(`❌ Appt ${appt.id}: Failed definitivo apos 3 tentativas (${eligibility.reason})`);
            continue;
          }
        }
      } else {
        // FLUXO MANUAL
        if (appt.status !== 'agendado') {
          results.skipped++;
          results.details.push(`⏭️ Appt ${appt.id}: Ignorado no fluxo manual (status é '${appt.status}', não 'agendado')`);
          continue;
        }
        if (appt.whatsapp_reminder_status === 'sent' || appt.whatsapp_reminder_status === 'confirmed') {
          results.skipped++;
          results.details.push(`⏭️ Appt ${appt.id}: Ignorado no modo forçado pois status é ${appt.whatsapp_reminder_status}`);
          continue;
        }
      }

      const phoneNumberId = whatsappConfig?.wa_phone_number_id || Deno.env.get('GLOBAL_WA_PHONE_NUMBER_ID');
      const accessToken = whatsappConfig?.wa_access_token || Deno.env.get('GLOBAL_WA_ACCESS_TOKEN');

      if (!phoneNumberId || !accessToken || !appt.client_phone) {
        results.skipped++
        continue
      }

      const templateName = whatsappConfig?.wa_template_reminder_name || Deno.env.get('GLOBAL_WA_REMINDER_TEMPLATE') || 'markaai_reminder'
      const appointmentDate = formatDate(appt.scheduled_at)
      const appointmentTime = formatTime(appt.scheduled_at)
      const clientName = appt.client_name || 'Cliente'
      const businessName = shop?.name || 'Estabelecimento'
      const serviceName = appt.service_name || 'Serviço'

      // Enviar via Meta Cloud API
      const sendResult = await sendReminderTemplate({
        phoneNumberId,
        accessToken,
        templateName,
        toPhone: appt.client_phone,
        clientName,
        businessName,
        appointmentDate,
        appointmentTime,
        serviceName,
      })

      if (sendResult.success) {
        const { error: updateError } = await supabase
          .from('appointments')
          .update({
            whatsapp_reminder_status: 'sent',
            whatsapp_reminder_sent_at: realNow.toISOString(),
            wa_reminder_message_id: sendResult.messageId || null,
          })
          .eq('id', appt.id)

        // Log de sucesso
        try {
          await supabase.from('whatsapp_send_log').insert({
            shop_id: appt.shop_id,
            to_phone: appt.client_phone.replace(/\D/g, ''),
            template_name: templateName,
            status: 'success',
            response_json: sendResult.rawResponse,
            request_payload: { clientName, businessName, serviceName, appointmentDate, appointmentTime },
          })
        } catch (e: any) {}

        results.sent++
        results.details.push(`✅ Appt ${appt.id}: enviado (msg_id: ${sendResult.messageId})`)
      } else {
        // Log de erro e marca como falho no cron automático, ou se preferir não falhar de vez,
        // apenas não marca como sent. A tolerância de 30 minutos capturará e falhará depois.
        try {
          await supabase.from('whatsapp_send_errors').insert({
            appointment_id: appt.id,
            shop_id: appt.shop_id,
            error_code: sendResult.errorCode,
            raw_response: sendResult.rawResponse,
            attempt_number: 1,
          })
        } catch (e: any) {}

        results.errors++
        results.details.push(`❌ Appt ${appt.id}: erro de rede/Meta ${sendResult.errorCode}`)
      }
    }

    return new Response(
      JSON.stringify({ ok: true, ...results }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (error: any) {
    return new Response(
      JSON.stringify({ ok: false, error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
