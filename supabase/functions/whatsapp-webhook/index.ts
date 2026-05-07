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
function extractButtonEvent(body: any): { from: string; payload: string } | null {
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

    if (!from || !buttonPayload) return null
    return { from, payload: buttonPayload }
  } catch {
    return null
  }
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

    const { from, payload: buttonPayload } = event
    // Número do remetente vem sem "+" — adicionar para bater com o formato E.164 do banco
    const clientPhone = `+${from}`
    console.log(`[whatsapp-webhook] Botão pressionado: ${buttonPayload} | de: ${clientPhone}`)

    try {
      // Buscar o agendamento mais recente deste número que recebeu lembrete e ainda está pendente
      const { data: appointment, error: apptError } = await supabase
        .from('appointments')
        .select('id, shop_id, client_name, service_name, scheduled_at, status')
        .eq('client_phone', clientPhone)
        .eq('reminder_sent', true)
        .not('status', 'in', '("cancelado","cancelled","confirmed_by_client")')
        .gt('scheduled_at', new Date().toISOString())
        .order('scheduled_at', { ascending: true })
        .limit(1)
        .maybeSingle()

      if (apptError) {
        console.error('[whatsapp-webhook] Erro ao buscar agendamento:', apptError.message)
        return new Response('OK', { status: 200 })
      }

      if (!appointment) {
        console.warn(`[whatsapp-webhook] Nenhum agendamento pendente encontrado para ${clientPhone}`)
        return new Response('OK', { status: 200 })
      }

      console.log(`[whatsapp-webhook] Agendamento encontrado: ${appointment.id} | status: ${appointment.status}`)

      // ── CONFIRMAR ─────────────────────────────────────────
      if (buttonPayload === 'CONFIRM_APPOINTMENT') {
        const { error: updateError } = await supabase
          .from('appointments')
          .update({ status: 'confirmed_by_client' })
          .eq('id', appointment.id)

        if (updateError) {
          console.error('[whatsapp-webhook] Erro ao confirmar:', updateError.message)
        } else {
          console.log(`[whatsapp-webhook] ✅ Agendamento ${appointment.id} confirmado pelo cliente`)
        }
      }

      // ── CANCELAR ──────────────────────────────────────────
      else if (buttonPayload === 'CANCEL_APPOINTMENT') {
        const { error: cancelError } = await supabase
          .from('appointments')
          .update({ status: 'cancelado' })
          .eq('id', appointment.id)

        if (cancelError) {
          console.error('[whatsapp-webhook] Erro ao cancelar:', cancelError.message)
        } else {
          console.log(`[whatsapp-webhook] ❌ Agendamento ${appointment.id} cancelado pelo cliente`)

          // Notificar dono fire-and-forget
          const d = new Date(appointment.scheduled_at)
          const dateStr = `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}`
          const timeStr = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`

          notifyOwner(
            supabase,
            appointment.shop_id,
            '❌ Cancelamento via WhatsApp',
            `${appointment.client_name} cancelou — ${appointment.service_name} de ${dateStr} às ${timeStr}`,
          ).catch((e) => console.error('[whatsapp-webhook] notifyOwner error:', e))
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
