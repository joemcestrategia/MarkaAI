import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

async function refreshMpToken(
  refreshToken: string,
  shopId: string,
  currentMp: Record<string, any>,
  supabase: any
): Promise<string | null> {
  const clientId = Deno.env.get('MP_CLIENT_ID')
  const clientSecret = Deno.env.get('MP_CLIENT_SECRET')

  if (!clientId || !clientSecret || !refreshToken) {
    console.error('refreshMpToken: credenciais ausentes ou refresh_token vazio')
    return null
  }

  try {
    const tokenRes = await fetch('https://api.mercadopago.com/oauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json' },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
      }),
    })

    const tokens = await tokenRes.json()
    if (!tokenRes.ok) {
      console.error('refreshMpToken: erro:', JSON.stringify(tokens))
      return null
    }

    const updatedMp = {
      ...currentMp,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      user_id: tokens.user_id || currentMp.user_id,
      public_key: tokens.public_key || currentMp.public_key,
      connected: true,
      updated_at: new Date().toISOString(),
    }

    await supabase.from('shops').update({ mercadopago: updatedMp }).eq('id', shopId)
    console.log('refreshMpToken: token renovado para shop', shopId)
    return tokens.access_token
  } catch (err) {
    console.error('refreshMpToken: exceção:', err)
    return null
  }
}

// Helper to decode base64 URL
function base64UrlDecode(str: string): string {
  const base64 = str.replace(/-/g, '+').replace(/_/g, '/')
  const padding = '='.repeat((4 - base64.length % 4) % 4)
  return atob(base64 + padding)
}

// Extract user_id from JWT payload without validation (for ES256 fallback)
function extractUserIdFromToken(token: string): string | null {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    const payload = JSON.parse(base64UrlDecode(parts[1]))
    return payload.sub || null
  } catch {
    return null
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseAdmin = createSupabaseAdminClient()

    // Extract token from header
    const authHeader = req.headers.get('Authorization')
    const token = authHeader?.replace('Bearer ', '')

    console.log('🔑 Token recebido:', token ? `${token.substring(0, 20)}...` : 'AUSENTE')
    console.log('🔑 Auth header:', authHeader ? 'presente' : 'ausente')

    if (!token) {
      return new Response(JSON.stringify({ error: 'Token de autenticação ausente.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Try to get user - handles both HS256 and ES256 tokens
    let user: any = null
    let userId: string | null = null
    try {
      const { data, error: authError } = await supabaseAdmin.auth.getUser(token)
      if (authError) {
        console.error('❌ getUser error:', authError.message)
      } else if (data?.user) {
        user = data.user
        userId = user.id
        console.log('✅ Usuário autenticado via getUser:', userId)
      }
    } catch (authEx: any) {
      console.error('❌ Auth exception:', authEx?.message)
    }

    // Fallback: extract user_id from JWT payload directly (for ES256 tokens)
    if (!userId) {
      userId = extractUserIdFromToken(token)
      console.log('🔑 User ID extraído do token:', userId)
    }

    if (!userId) {
      return new Response(JSON.stringify({ error: 'Autenticação necessária. Faça login novamente.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { shop_id, amount, description, email, payer_email, cpf, payer_cpf, card_token, installments, payment_method_id, issuer_id } = await req.json()

    const finalEmail = email || payer_email || 'cliente@app.com'
    const finalCpf = cpf || payer_cpf

    if (!shop_id || !card_token || !amount) {
      return new Response(JSON.stringify({ error: 'Parâmetros obrigatórios ausentes.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const rawAmount = parseFloat(amount)
    if (!rawAmount || isNaN(rawAmount) || rawAmount <= 0) {
      return new Response(JSON.stringify({ error: 'Valor inválido.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }
    // MP rejects transaction_amount with more than 2 decimal places
    const parsedAmount = Math.round(rawAmount * 100) / 100

    // Admin client already created above — reuse for shop data query (bypasses RLS)
    const { data: shopDoc, error: shopError } = await supabaseAdmin.from('shops').select('mercadopago').eq('id', shop_id).single()
    if (shopError || !shopDoc) {
      console.error('Shop query error:', shopError?.message)
      return new Response(JSON.stringify({ error: 'Loja não encontrada.' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    let accessToken = shopDoc.mercadopago?.access_token
    const mpRefreshToken = shopDoc.mercadopago?.refresh_token
    if (!accessToken) {
      return new Response(JSON.stringify({ error: 'Mercado Pago não configurado nesta loja.' }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const idempotencyKey = `card-${userId}-${Date.now()}`
    const paymentData: any = {
      transaction_amount: parsedAmount, // already rounded to 2dp
      token: card_token,
      description: description || 'Pagamento App',
      installments: parseInt(installments) || 1,
      payment_method_id: payment_method_id,
      issuer_id: issuer_id,
      notification_url: 'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/mpPaymentWebhook',
      payer: {
        email: finalEmail,
        identification: finalCpf ? {
          type: 'CPF',
          number: finalCpf.replace(/\D/g, '')
        } : undefined
      }
    }

    const baseUrl = (accessToken.startsWith('TEST-'))
      ? 'https://api.sandbox.mercadopago.com'
      : 'https://api.mercadopago.com'

    let res = await fetch(`${baseUrl}/v1/payments`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'X-Idempotency-Key': idempotencyKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(paymentData)
    })

    // Auto-refresh: se token expirado (401/403), renova e retenta UMA vez
    if ((res.status === 401 || res.status === 403) && mpRefreshToken) {
      console.log('criar-pagamento: token expirado, tentando renovar...')
      const newToken = await refreshMpToken(mpRefreshToken, shop_id, shopDoc.mercadopago, supabaseAdmin)
      if (newToken) {
        accessToken = newToken
        res = await fetch(`${baseUrl}/v1/payments`, {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'X-Idempotency-Key': idempotencyKey,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify(paymentData)
        })
      }
    }

    const data = await res.json()

    if (!res.ok) {
      console.error("Erro MP:", data)
      return new Response(JSON.stringify({ success: false, error: data.message || 'Erro Desconhecido', status_detail: data.cause?.[0]?.code || data.status_detail, details: data }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (data.status === 'approved' || data.status === 'in_process') {
      return new Response(JSON.stringify({ success: true, paymentId: data.id, status: data.status, message: data.status_detail }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    } else {
      return new Response(JSON.stringify({ success: false, error: data.status_detail || 'Pagamento recusado', status_detail: data.status_detail }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

  } catch (error) {
    console.error('Error criar-pagamento:', error)
    return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
