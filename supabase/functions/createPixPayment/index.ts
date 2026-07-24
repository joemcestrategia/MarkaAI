import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient, createSupabaseAdminClient } from '../_shared/supabase.ts'

async function refreshMpToken(adminSupabase: any, shopId: string, refreshToken: string) {
  const response = await fetch('https://api.mercadopago.com/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      client_id: Deno.env.get('MP_CLIENT_ID'),
      client_secret: Deno.env.get('MP_CLIENT_SECRET'),
    }),
  })

  if (!response.ok) return null

  const tokens = await response.json()
  await adminSupabase.from('shops').update({
    mercadopago: {
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      token_type: tokens.token_type,
      expires_in: tokens.expires_in,
      scope: tokens.scope,
      user_id: tokens.user_id,
      public_key: tokens.public_key,
      live_mode: tokens.live_mode,
    }
  }).eq('id', shopId)

  return tokens.access_token
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization header' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const supabase = createSupabaseClient(req)
    const adminSupabase = createSupabaseAdminClient()

    let userId = 'anonymous'
    try {
      const { data: userData } = await supabase.auth.getUser()
      userId = userData?.user?.id || 'anonymous'
    } catch (_) {}

    const { shop_id, amount, email, description, external_reference } = await req.json()

    if (!shop_id) {
      return new Response(JSON.stringify({ error: 'shop_id é obrigatório para gerar PIX.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const parsedAmount = parseFloat(amount)
    if (!parsedAmount || isNaN(parsedAmount) || parsedAmount <= 0) {
      return new Response(JSON.stringify({ error: 'Valor inválido para o pagamento PIX.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { data: shopDoc, error: shopError } = await adminSupabase.from('shops').select('mercadopago').eq('id', shop_id).single()
    if (shopError || !shopDoc) {
      return new Response(JSON.stringify({ error: 'Loja não encontrada.' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    let accessToken = shopDoc.mercadopago?.access_token
    if (!accessToken) {
      return new Response(JSON.stringify({ error: 'Mercado Pago não configurado nesta loja.' }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const idempotencyKey = `pix-${userId}-${Date.now()}`
    const paymentData: any = {
      transaction_amount: parsedAmount,
      description: description || 'Pagamento App',
      payment_method_id: 'pix',
      payer: { email: email || 'cliente@app.com' }
    }

    if (external_reference) paymentData.external_reference = external_reference
    paymentData.notification_url = 'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/mpPaymentWebhook'

    const baseUrl = (accessToken.startsWith('TEST-')) ? 'https://api.sandbox.mercadopago.com' : 'https://api.mercadopago.com'

    let res = await fetch(`${baseUrl}/v1/payments`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'X-Idempotency-Key': idempotencyKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(paymentData)
    })

    if ((res.status === 401 || res.status === 403) && shopDoc.mercadopago?.refresh_token) {
      const newAccessToken = await refreshMpToken(adminSupabase, shop_id, shopDoc.mercadopago.refresh_token)
      if (newAccessToken) {
        accessToken = newAccessToken
        res = await fetch(`${baseUrl}/v1/payments`, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${accessToken}`, 'X-Idempotency-Key': idempotencyKey, 'Content-Type': 'application/json' },
          body: JSON.stringify(paymentData)
        })
      }
    }

    const data = await res.json()

    if (!res.ok) {
      console.error("Erro MP:", data)
      const causeStr = JSON.stringify(data.cause || {}).toLowerCase()
      if (causeStr.includes('collector user') && causeStr.includes('qr')) {
        return new Response(JSON.stringify({ error: 'collector_not_enabled_for_qr', details: data }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      if (causeStr.includes('pix_keys') || causeStr.includes('no pix') || causeStr.includes('collector without pix')) {
        return new Response(JSON.stringify({ error: 'collector_no_pix_keys', details: data }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      return new Response(JSON.stringify({ error: `MP Recusou: ${data.message || 'Erro Desconhecido'}`, details: data }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify(data), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error: any) {
    console.error('Error createPixPayment:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
