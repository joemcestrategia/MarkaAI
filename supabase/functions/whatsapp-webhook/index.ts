import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ──────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────

/**
 * Valida a assinatura HMAC-SHA256 enviada pelo Meta no header X-Hub-Signature-256.
 * Formato: "sha256=<hex_digest>"
 */
async function verifyMetaSignature(
  rawBody: string,
  signatureHeader: string | null,
  appSecret: string,
): Promise<boolean> {
  if (!signatureHeader) return false
  const expected = signatureHeader.replace('sha256=', '')

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(appSecret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    'HMAC',
    key,
    new TextEncoder().encode(rawBody),
  )
  const computed = Array.from(new Uint8Array(signature))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')

  return computed === expected
}

/**
 * Extrai a mensagem de quick_reply do payload do Meta.
 * Retorna null se não for um evento de botão válido.
 */
function extractButtonEvent(body: any): { from: string; payload: string; phoneNumberId?: string; contextMessageId?: string } | null {
  try {
    const entry = body?.entry?.[0]
    const change = entry?.changes?.[0]
    const value = change?.value

    // Ignorar status updates (delivered, read, etc.)
    if (value?.statuses) return null

    const message = value?.messages?.[0]
    if (!message) return null

    // Aceitar somente quick_reply (type = 'button')
    if (message.type !== 'button') return null

    const from: string = message.from // número sem "+", formato E.164
    const buttonPayload: string = message.button?.payload
    const phoneNumberId: string | undefined = value?.metadata?.phone_number_id
    const contextMessageId: string | undefined = message.context?.id // wamid da mensagem original que o cliente está respondendo

    if (!from || !buttonPayload) return null
    return { from, payload: buttonPayload, phoneNumberId, contextMessageId }
  } catch {
    return null
  }
}

/** Extrai telefone do agendamento considerando campos legados (Setmore, Firebase) */
function getAppointmentPhone(appt: any): string {
  return (appt.client_phone || appt.clientPhone || appt.cliente_telefone || '').replace(/\D/g, '')
}

/**
 * Envia FCM push notification para o dono da loja via sendPushNotification function.
 */
async function notifyOwner(
  supabase: any,
  shopId: string,
  title: string,
  body: string,
): Promise<void> {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    const { data: shop } = await supabase
      .from('shops')
      .select('owner_id')
      .eq('id', shopId)
      .single()

    const ownerId = shop?.owner_id ?? shopId // fallback: shop_id === owner_id neste sistema

    await fetch(`${supabaseUrl}/functions/v1/sendPushNotification`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({ user_id: ownerId, title, message: body }),
    })
  } catch (e) {
    console.error('[whatsapp-webhook] Erro ao notificar dono:', e)
  }
}

/**
 * Envia uma mensagem de texto livre de volta para o cliente.
 * Só funciona porque o cliente acabou de interagir (janela de 24h aberta).
 */
async function sendWhatsAppText(
  phoneNumberId: string,
  accessToken: string,
  to: string,
  text: string,
): Promise<void> {
  try {
    const payload = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to: to.replace(/\D/g, ''),
      type: 'text',
      text: { body: text }
    }
    await fetch(`https://graph.facebook.com/v18.0/${phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    })
  } catch (e) {
    console.error('[whatsapp-webhook] Erro ao enviar text reply:', e)
  }
}

// ──────────────────────────────────────────────────────────────
// Handler principal
// ──────────────────────────────────────────────────────────────

serve(async (req) => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  // ──────────────────────────────────────────────────────────
  // GET — Verificação do webhook pelo Meta for Devs
  // ──────────────────────────────────────────────────────────
  if (req.method === 'GET') {
    const url = new URL(req.url)
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge')

    if (mode !== 'subscribe' || !token || !challenge) {
      return new Response('Bad Request', { status: 400 })
    }

    // Aceitar qualquer token cadastrado em shop_whatsapp_config para multi-loja,
    // ou o token global de env var.
    const globalToken = Deno.env.get('WHATSAPP_VERIFY_TOKEN')
    if (token === globalToken) {
      console.log('[whatsapp-webhook] Verificação GET: token global aceito')
      return new Response(challenge, { status: 200 })
    }

    // Fallback: busca em qualquer loja ativa
    const { data } = await supabase
      .from('shop_whatsapp_config')
      .select('id')
      .eq('wa_webhook_verify_token', token)
      .eq('is_active', true)
      .maybeSingle()

    if (data) {
      console.log('[whatsapp-webhook] Verificação GET: token de loja aceito')
      return new Response(challenge, { status: 200 })
    }

    console.warn('[whatsapp-webhook] Verificação GET: token inválido:', token)
    return new Response('Forbidden', { status: 403 })
  }

  // ──────────────────────────────────────────────────────────
  // POST — Recepção de mensagens do cliente
  // REGRA META: SEMPRE retornar HTTP 200, mesmo em erro interno.
  // ──────────────────────────────────────────────────────────
  if (req.method === 'POST') {
    let rawBody = ''
    try {
      rawBody = await req.text()
    } catch {
      console.error('[whatsapp-webhook] Falha ao ler body')
      return new Response('OK', { status: 200 })
    }

    // Validar assinatura HMAC-SHA256
    const appSecret = Deno.env.get('WHATSAPP_APP_SECRET') ?? ''
    if (appSecret) {
      const signatureHeader = req.headers.get('x-hub-signature-256')
      const valid = await verifyMetaSignature(rawBody, signatureHeader, appSecret)
      if (!valid) {
        console.warn('[whatsapp-webhook] Assinatura HMAC inválida — requisição rejeitada')
        // Retornar 200 mesmo assim para não revelar o motivo ao atacante
        return new Response('OK', { status: 200 })
      }
    } else {
      console.warn('[whatsapp-webhook] WHATSAPP_APP_SECRET não configurado — pulando validação HMAC')
    }

    let body: any
    try {
      body = JSON.parse(rawBody)
    } catch {
      console.error('[whatsapp-webhook] Payload inválido (não é JSON)')
      return new Response('OK', { status: 200 })
    }

    console.log('[whatsapp-webhook] POST recebido:', JSON.stringify(body))

    // Extrair evento de botão
    const event = extractButtonEvent(body)
    if (!event) {
      // Pode ser status update (delivered/read) — ignorar silenciosamente
      return new Response(JSON.stringify({ ok: true, ignored: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { from, payload: buttonPayload, phoneNumberId: webhookPhoneId, contextMessageId } = event
    // Número do remetente vem sem "+" — adicionar para bater com o formato E.164 do banco
    const clientPhone = `+${from}`
    const fromClean = from.replace(/\D/g, '')
    const fromSuffix = fromClean.slice(-8)
    console.log(`[whatsapp-webhook] Botão pressionado: ${buttonPayload} | de: ${clientPhone} | sufixo: ${fromSuffix} | phone_id: ${webhookPhoneId || '(não informado)'} | context_msg_id: ${contextMessageId || '(não informado)'}`)

    try {
      let appointment: any = null

      // ── ESTRATÉGIA 1 (preferencial): lookup exato pelo wamid ──
      // O Meta envia context.id = wamid da mensagem original que o cliente está respondendo.
      // Isso identifica EXATAMENTE qual agendamento gerou o lembrete, mesmo que o cliente
      // tenha múltiplos agendamentos em lojas diferentes.
      if (contextMessageId) {
        console.log(`[whatsapp-webhook] Tentando lookup direto por contextMessageId: ${contextMessageId}`)
        const { data: exactMatch, error: exactError } = await supabase
          .from('appointments')
          .select(`
            id, shop_id, client_name, client_phone, service_name, scheduled_at, status,
            shops (
              plan,
              shop_whatsapp_config (
                wa_phone_number_id,
                wa_access_token
              )
            )
          `)
          .eq('wa_reminder_message_id', contextMessageId)
          .maybeSingle()

        if (!exactError && exactMatch) {
          // Verificação extra de segurança: o telefone de quem clicou bate com o do agendamento?
          const phone = getAppointmentPhone(exactMatch)
          if (phone.slice(-8) === fromSuffix) {
            console.log(`[whatsapp-webhook] Match exato por wamid: ${exactMatch.id}`)
            appointment = exactMatch
          } else {
            console.warn(`[whatsapp-webhook] wamid bateu (${exactMatch.id}) mas telefone NÃO confere — ignorando match exato`)
          }
        } else {
          console.log(`[whatsapp-webhook] Nenhum match por wamid — caindo para busca por telefone`)
        }
      }

      // ── ESTRATÉGIA 2 (fallback): match por telefone ──
      if (!appointment) {
        const findAppointment = async (requireReminderSent: boolean) => {
          let q = supabase
            .from('appointments')
            .select(`
              id, shop_id, client_name, client_phone, clientPhone, cliente_telefone, service_name, scheduled_at, status,
              shops (
                plan,
                shop_whatsapp_config (
                  wa_phone_number_id,
                  wa_access_token
                )
              )
            `)
            .not('status', 'in', '("cancelado","cancelled","confirmed_by_client")')
            .gt('scheduled_at', new Date().toISOString())
            .order('scheduled_at', { ascending: false })

          if (requireReminderSent) {
            q = q.eq('reminder_sent', true)
          }

          // Se temos o phone_number_id do webhook, restringe à loja correspondente
          if (webhookPhoneId) {
            q = q.eq('shops.shop_whatsapp_config.wa_phone_number_id', webhookPhoneId)
          }

          const { data, error } = await q
          if (error || !data?.length) return null

          // Filtra em memória suportando campos legados (client_phone, clientPhone, cliente_telefone)
          const matches = data.filter((appt: any) => {
            const phone = getAppointmentPhone(appt)
            return phone.slice(-8) === fromSuffix
          })

          if (matches.length === 0) return null

          // Se múltiplos, retorna o mais recente (já ordenado por scheduled_at DESC)
          if (matches.length > 1) {
            console.log(`[whatsapp-webhook] ${matches.length} agendamentos batem com o telefone — usando o mais recente: ${matches[0].id}`)
          }
          return matches[0]
        }

        // 1ª tentativa: apenas agendamentos que já receberam lembrete (fluxo normal)
        appointment = await findAppointment(true)

        // 2ª tentativa (fallback): sem filtro de reminder_sent
        if (!appointment) {
          console.log(`[whatsapp-webhook] Nenhum match com reminder_sent=true, tentando fallback sem reminder_sent...`)
          appointment = await findAppointment(false)
        }
      }

      if (!appointment) {
        console.warn(`[whatsapp-webhook] Nenhum agendamento encontrado para o sufixo ${fromSuffix}`)
        return new Response('OK', { status: 200 })
      }

      console.log(`[whatsapp-webhook] Agendamento encontrado: ${appointment.id} | status: ${appointment.status} | scheduled: ${appointment.scheduled_at}`)

      // Obter credenciais para resposta
      const shop = (appointment.shops as any) || {}
      const shopPlan = (shop.plan || '').toLowerCase()

      // Apenas lojas nos planos plus e pro podem usar WhatsApp
      if (shopPlan !== 'plus' && shopPlan !== 'pro') {
        console.warn(`[whatsapp-webhook] Loja ${appointment.shop_id} no plano "${shopPlan}" — WhatsApp não disponível`)
        return new Response('OK', { status: 200 })
      }

      const whatsappConfig = shop.shop_whatsapp_config || {}
      const phoneNumberId = whatsappConfig.wa_phone_number_id || Deno.env.get('GLOBAL_WA_PHONE_NUMBER_ID') || ''
      const accessToken = whatsappConfig.wa_access_token || Deno.env.get('GLOBAL_WA_ACCESS_TOKEN') || ''

      // ── CONFIRMAR ─────────────────────────────────────────
      if (buttonPayload === 'CONFIRM_APPOINTMENT' || buttonPayload.toUpperCase() === 'CONFIRMAR') {
        const { error: updateError } = await supabase
          .from('appointments')
          .update({ status: 'confirmed_by_client' })
          .eq('id', appointment.id)

        if (updateError) {
          console.error('[whatsapp-webhook] Erro ao confirmar:', updateError.message)
        } else {
          console.log(`[whatsapp-webhook] ✅ Agendamento ${appointment.id} confirmado pelo cliente`)
          if (phoneNumberId && accessToken) {
            await sendWhatsAppText(phoneNumberId, accessToken, clientPhone, '✅ Excelente! Seu agendamento foi confirmado com sucesso. Te esperamos!')
          }

          // Notificar dono fire-and-forget
          const d = new Date(appointment.scheduled_at)
          const dateStr = `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}`
          const timeStr = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`

          notifyOwner(
            supabase,
            appointment.shop_id,
            '✅ Confirmação via WhatsApp',
            `${appointment.client_name} confirmou presença — ${appointment.service_name} de ${dateStr} às ${timeStr}`,
          ).catch((e) => console.error('[whatsapp-webhook] notifyOwner error:', e))
        }
      }

      // ── CANCELAR ──────────────────────────────────────────
      else if (buttonPayload === 'CANCEL_APPOINTMENT' || buttonPayload.toUpperCase() === 'CANCELAR') {
        const { error: cancelError } = await supabase
          .from('appointments')
          .update({ status: 'cancelado' })
          .eq('id', appointment.id)

        if (cancelError) {
          console.error('[whatsapp-webhook] Erro ao cancelar:', cancelError.message)
        } else {
          console.log(`[whatsapp-webhook] ❌ Agendamento ${appointment.id} cancelado pelo cliente`)

          if (phoneNumberId && accessToken) {
            await sendWhatsAppText(phoneNumberId, accessToken, clientPhone, '❌ Entendido. Seu agendamento foi cancelado com sucesso. Caso queira agendar novamente no futuro, estamos à disposição!')
          }

          // Nota: Não enviamos notifyOwner aqui explicitamente porque o gatilho 
          // de banco de dados 'appointment_notifications' (Edge Function appointmentTriggers)
          // já escuta por status = 'cancelado' e dispara notificação Push e E-mail 
          // automaticamente para o dono.
        }
      }

      // ── PAYLOAD DESCONHECIDO ───────────────────────────────
      else {
        console.warn(`[whatsapp-webhook] Payload de botão desconhecido: ${buttonPayload}`)
      }
    } catch (e) {
      console.error('[whatsapp-webhook] Erro interno:', e)
      // Nunca retornar 5xx para o Meta
    }

    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  return new Response('Method Not Allowed', { status: 405 })
})
