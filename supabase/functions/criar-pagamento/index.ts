import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Extract and validate JWT via admin.auth.getUser(token) — most reliable pattern for Edge Functions
    const authHeader = req.headers.get('Authorization')
    const token = authHeader?.replace('Bearer ', '')
    if (!token) {
      return new Response(JSON.stringify({ error: 'Token de autenticação ausente.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const supabaseAdmin = createSupabaseAdminClient()
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) {
      console.error('Auth error:', authError?.message)
      return new Response(JSON.stringify({ error: 'Autenticação necessária.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
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

    const accessToken = shopDoc.mercadopago?.access_token
    if (!accessToken) {
      return new Response(JSON.stringify({ error: 'Mercado Pago não configurado nesta loja.' }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const idempotencyKey = `card-${user.id}-${Date.now()}`
    const paymentData: any = {
      transaction_amount: parsedAmount, // already rounded to 2dp
      token: card_token,
      description: description || 'Pagamento App',
      installments: parseInt(installments) || 1,
      payment_method_id: payment_method_id,
      issuer_id: issuer_id,
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

    const res = await fetch(`${baseUrl}/v1/payments`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'X-Idempotency-Key': idempotencyKey,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(paymentData)
    })

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
