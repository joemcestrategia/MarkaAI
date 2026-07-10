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

    // Aceitar type = 'button' (Template) ou type = 'interactive' (Mensagem Interativa)
    if (message.type !== 'button' && message.type !== 'interactive') return null

    let buttonPayload: string | undefined
    if (message.type === 'button') {
      buttonPayload = message.button?.payload
    } else if (message.type === 'interactive' && message.interactive?.type === 'button_reply') {
      buttonPayload = message.interactive.button_reply?.id
    }

    if (!buttonPayload) return null

    const from: string = message.from // número sem "+", formato E.164
    const phoneNumberId: string | undefined = value?.metadata?.phone_number_id
    const contextMessageId: string | undefined = message.context?.id // wamid da mensagem original que o cliente está respondendo

    if (!from) return null
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

/**
 * Envia uma mensagem interativa (botões ou cta_url).
 */
async function sendWhatsAppInteractive(
  phoneNumberId: string,
  accessToken: string,
  to: string,
  interactiveType: 'button' | 'cta_url',
  text: string,
  buttonsOrUrl: any
): Promise<any> {
  try {
    const interactive: any = {
      type: interactiveType,
      body: { text },
      action: {}
    }

    if (interactiveType === 'button') {
      interactive.action.buttons = buttonsOrUrl
    }

    const payload = {
      messaging_product: 'whatsapp',
      recipient_type: 'individual',
      to: to.replace(/\D/g, ''),
      type: 'interactive',
      interactive
    }

    const res = await fetch(`https://graph.facebook.com/v18.0/${phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    })
    
    if (!res.ok) {
      const errTxt = await res.text()
      console.error('[whatsapp-webhook] Erro retornado pela Meta ao enviar interactive:', errTxt)
      return null
    }
    return await res.json()
  } catch (e) {
    console.error('[whatsapp-webhook] Exceção ao enviar interactive reply:', e)
    return null
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
      if (body?.entry?.[0]?.changes?.[0]?.value?.messages?.[0]?.type === 'interactive') {
         const phId = body?.entry?.[0]?.changes?.[0]?.value?.metadata?.phone_number_id || Deno.env.get('GLOBAL_WA_PHONE_NUMBER_ID') || ''
         const tk = Deno.env.get('GLOBAL_WA_ACCESS_TOKEN') || ''
         const f = body?.entry?.[0]?.changes?.[0]?.value?.messages?.[0]?.from || ''
         if (phId && tk && f) {
           await sendWhatsAppText(phId, tk, f, `[Debug] Erro ao extrair payload do botão interativo. Tipo recebido: ${body?.entry?.[0]?.changes?.[0]?.value?.messages?.[0]?.interactive?.type}`)
         }
      }
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
        
        const baseQuery = `
            id, shop_id, client_name, client_phone, clientPhone, cliente_telefone, service_name, scheduled_at, status, confirmation_state,
            shops (
              plan_id,
              phone,
              whatsapp,
              shop_whatsapp_config (
                wa_phone_number_id,
                wa_access_token
              )
            )
          `
        
        // 3a. Busca por clique no template original
        const { data: exactMatch, error: exactError } = await supabase
          .from('appointments')
          .select(baseQuery)
          .eq('wa_reminder_message_id', contextMessageId)
          .maybeSingle()

        if (!exactError && exactMatch) {
          appointment = exactMatch
        } else {
          // 3b. Busca por clique na mensagem interativa
          const { data: interactiveMatch, error: interactiveError } = await supabase
            .from('appointments')
            .select(`${baseQuery}, wa_interactive_messages!inner(wamid)`)
            .eq('wa_interactive_messages.wamid', contextMessageId)
            .maybeSingle()
            
          if (!interactiveError && interactiveMatch) {
            appointment = interactiveMatch
          }
        }
      }

      // ── ESTRATÉGIA 2 (fallback): match por telefone ──
      if (!appointment) {
        const findAppointment = async (requireReminderSent: boolean) => {
          // Pega data de ontem para aceitar confirmações atrasadas
          const yesterday = new Date()
          yesterday.setDate(yesterday.getDate() - 1)
          
          let q = supabase
            .from('appointments')
            .select(`
              id, shop_id, client_name, client_phone, clientPhone, cliente_telefone, service_name, scheduled_at, status, confirmation_state,
              shops (
                plan_id,
                phone,
                whatsapp,
                shop_whatsapp_config (
                  wa_phone_number_id,
                  wa_access_token
                )
              )
            `)
            .not('status', 'in', '("cancelado","cancelled","confirmed_by_client")')
            .gte('scheduled_at', yesterday.toISOString())
            .order('scheduled_at', { ascending: false })

          if (requireReminderSent) {
            q = q.eq('reminder_sent', true)
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

        if (!appointment) {
          console.warn(`[whatsapp-webhook] Nenhum agendamento encontrado para o sufixo ${fromSuffix}`)
          // Removed debug message sending because credentials are not resolved yet and it causes ReferenceError.
          return new Response(JSON.stringify({ error: 'Nenhum agendamento', fromSuffix }), { status: 200, headers: { 'Content-Type': 'application/json' } })
        } else {
          console.error(`[whatsapp-webhook] fallback_by_phone_triggered - wamid original não encontrado, mas telefone bateu. appointment_id: ${appointment.id}`)
        }
      }

      console.log(`[whatsapp-webhook] Agendamento encontrado: ${appointment.id} | status: ${appointment.status} | scheduled: ${appointment.scheduled_at}`)

      // Obter credenciais para resposta
      const shop = (appointment.shops as any) || {}
      const shopPlan = (shop.plan_id || '').toLowerCase()

      // Apenas lojas nos planos plus e pro podem usar WhatsApp
      if (shopPlan !== 'plus' && shopPlan !== 'pro') {
        console.warn(`[whatsapp-webhook] Loja ${appointment.shop_id} no plano "${shopPlan}" — WhatsApp não disponível`)
        return new Response('OK', { status: 200 })
      }

      const whatsappConfig = shop.shop_whatsapp_config || {}
      const phoneNumberId = whatsappConfig.wa_phone_number_id || Deno.env.get('GLOBAL_WA_PHONE_NUMBER_ID') || ''
      const accessToken = whatsappConfig.wa_access_token || Deno.env.get('GLOBAL_WA_ACCESS_TOKEN') || ''

      // ── CONFIRMAR (Etapa 1: Pergunta) ─────────────────────────────────────────
      if (buttonPayload === 'CONFIRM_APPOINTMENT' || buttonPayload.toUpperCase() === 'CONFIRMAR') {
        if (appointment.confirmation_state === 'awaiting_confirmation') {
          console.log(`[whatsapp-webhook] Pergunta de confirmação já enviada para ${appointment.id}, ignorando reenvio duplicado.`)
        } else if (phoneNumberId && accessToken) {
          const metaResponse = await sendWhatsAppInteractive(phoneNumberId, accessToken, clientPhone, 'button', 'Você tem certeza que deseja confirmar?', [
            { type: 'reply', reply: { id: 'CONFIRM_SURE', title: 'Sim' } },
            { type: 'reply', reply: { id: 'CANCEL_SURE', title: 'Não' } }
          ])
          
          const newWamid = metaResponse?.messages?.[0]?.id
          if (newWamid) {
            await supabase.from('wa_interactive_messages').insert({
              appointment_id: appointment.id,
              wamid: newWamid,
              message_kind: 'confirmation_check'
            })
            await supabase.from('appointments').update({ confirmation_state: 'awaiting_confirmation', last_wa_message_sent_at: new Date().toISOString() }).eq('id', appointment.id)
          }
        }
      }
      
      // ── CANCELAR (Etapa 1: Pergunta) ──────────────────────────────────────────
      else if (buttonPayload === 'CANCEL_APPOINTMENT' || buttonPayload.toUpperCase() === 'CANCELAR') {
        if (appointment.confirmation_state === 'awaiting_confirmation') {
          console.log(`[whatsapp-webhook] Pergunta de confirmação já enviada para ${appointment.id}, ignorando reenvio duplicado.`)
        } else if (phoneNumberId && accessToken) {
          const metaResponse = await sendWhatsAppInteractive(phoneNumberId, accessToken, clientPhone, 'button', 'Você tem certeza que deseja cancelar?', [
            { type: 'reply', reply: { id: 'CANCEL_SURE', title: 'Sim' } },
            { type: 'reply', reply: { id: 'CONFIRM_SURE', title: 'Não' } }
          ])
          
          const newWamid = metaResponse?.messages?.[0]?.id
          if (newWamid) {
            await supabase.from('wa_interactive_messages').insert({
              appointment_id: appointment.id,
              wamid: newWamid,
              message_kind: 'confirmation_check'
            })
            await supabase.from('appointments').update({ confirmation_state: 'awaiting_confirmation', last_wa_message_sent_at: new Date().toISOString() }).eq('id', appointment.id)
          }
        }
      }

      // ── LOGICA COMPARTILHADA DA ETAPA 2 ──────────────────────────────────────
      else if (buttonPayload === 'CONFIRM_SURE' || buttonPayload === 'CANCEL_SURE') {
        let shopPhoneClean = (shop.whatsapp || shop.phone || '').replace(/\D/g, '') || ''
        if (shopPhoneClean && shopPhoneClean.length <= 11) {
          shopPhoneClean = `55${shopPhoneClean}`
        }
        const shopWaLink = shopPhoneClean ? `https://wa.me/${shopPhoneClean}` : 'https://marka.ai'

        // ── ATUALIZAÇÃO ATÔMICA DA ETAPA 2 ───────────────────────────────
        const newState = buttonPayload === 'CONFIRM_SURE' ? 'confirmed' : 'cancelled'
        const newStatus = buttonPayload === 'CONFIRM_SURE' ? 'confirmed_by_client' : 'cancelado'

        const { data: updated, error: updateError } = await supabase
          .from('appointments')
          .update({ status: newStatus, confirmation_state: newState })
          .eq('id', appointment.id)
          .eq('confirmation_state', 'awaiting_confirmation')
          .select('id')

        if (updateError) {
          console.error('[whatsapp-webhook] Erro ao processar:', updateError.message)
          if (phoneNumberId && accessToken) {
            await sendWhatsAppText(phoneNumberId, accessToken, clientPhone, `[Debug] Erro ao atualizar o banco: ${updateError.message}`)
          }
          return new Response(JSON.stringify({ error: updateError.message }), { status: 200 })
        }

        if (!updated || updated.length === 0) {
          console.warn(`[whatsapp-webhook] Evento duplicado ou já processado ignorado. Agendamento ${appointment.id}.`)
          return new Response('OK', { status: 200 })
        }

        if (buttonPayload === 'CONFIRM_SURE') {
          console.log(`[whatsapp-webhook] ✅ Agendamento ${appointment.id} confirmado pelo cliente`)
          if (phoneNumberId && accessToken) {
            await sendWhatsAppText(phoneNumberId, accessToken, clientPhone, `✅ Ação executada com sucesso! Seu agendamento foi confirmado.\n\nPara falar com o salão, clique no link abaixo:\n${shopWaLink}`)
          }

          const d = new Date(appointment.scheduled_at)
          const dateStr = `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}`
          const timeStr = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`

          notifyOwner(
            supabase,
            appointment.shop_id,
            '✅ Confirmação via WhatsApp',
            `${appointment.client_name} confirmou presença — ${appointment.service_name} de ${dateStr} às ${timeStr}`,
          ).catch((e) => console.error('[whatsapp-webhook] notifyOwner error:', e))
          
          return new Response(JSON.stringify({ success: true, action: 'CONFIRM_SURE', appointment }), { status: 200 })
        } else if (buttonPayload === 'CANCEL_SURE') {
          console.log(`[whatsapp-webhook] ❌ Agendamento ${appointment.id} cancelado pelo cliente`)
          if (phoneNumberId && accessToken) {
            await sendWhatsAppText(phoneNumberId, accessToken, clientPhone, `❌ Ação executada com sucesso! Seu agendamento foi cancelado.\n\nPara falar com o salão, clique no link abaixo:\n${shopWaLink}`)
          }
          // Não envia notifyOwner explícito pois o banco já possui trigger pra status='cancelado'
          return new Response(JSON.stringify({ success: true, action: 'CANCEL_SURE', appointment }), { status: 200 })
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
