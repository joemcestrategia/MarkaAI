import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient, createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseClient(req)
    const adminSupabase = createSupabaseAdminClient()

    // Tenta pegar o usuário apenas para log e idempotência, mas não bloqueia se falhar o JWT
    const { data: userData } = await supabase.auth.getUser()
    const userId = userData?.user?.id || 'anonymous'

    const { shop_id, amount, email, description, external_reference } = await req.json()

    if (!shop_id) {
      return new Response(JSON.stringify({ error: 'shop_id é obrigatório para gerar PIX.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const parsedAmount = parseFloat(amount)
    if (!parsedAmount || isNaN(parsedAmount) || parsedAmount <= 0) {
      return new Response(JSON.stringify({ error: 'Valor inválido para o pagamento PIX.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Fetch the access_token securely from Supabase using Admin Client (bypass RLS)
    const { data: shopDoc, error: shopError } = await adminSupabase.from('shops').select('mercadopago').eq('id', shop_id).single()
    if (shopError || !shopDoc) {
      return new Response(JSON.stringify({ error: 'Loja não encontrada.' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const accessToken = shopDoc.mercadopago?.access_token
    if (!accessToken) {
      return new Response(JSON.stringify({ error: 'Mercado Pago não configurado nesta loja. O dono precisa conectar a conta.' }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }) // 412 Precondition Failed
    }

    const idempotencyKey = `pix-${userId}-${Date.now()}`
    const paymentData: any = {
      transaction_amount: parsedAmount,
      description: description || 'Pagamento App',
      payment_method_id: 'pix',
      payer: {
        email: email || 'cliente@app.com'
      }
    }

    if (external_reference) {
      paymentData.external_reference = external_reference
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
