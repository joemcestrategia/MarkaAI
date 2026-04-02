import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    const token = authHeader?.replace('Bearer ', '')
    if (!token) {
      return new Response(JSON.stringify({ error: 'Token ausente.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const supabaseAdmin = createSupabaseAdminClient()
    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(token)
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Autenticação necessária.' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { shop_id, card_token, user_email, payment_method_id, last_four } = await req.json()
    if (!shop_id || !card_token) {
      return new Response(JSON.stringify({ error: 'shop_id e card_token são obrigatórios.' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Get shop's MP access token via admin (bypasses RLS)
    const { data: shopDoc, error: shopError } = await supabaseAdmin.from('shops').select('mercadopago').eq('id', shop_id).single()
    if (shopError || !shopDoc?.mercadopago?.access_token) {
      return new Response(JSON.stringify({ error: 'Mercado Pago não configurado nesta loja.' }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const accessToken = shopDoc.mercadopago.access_token
    const baseUrl = accessToken.startsWith('TEST-')
      ? 'https://api.sandbox.mercadopago.com'
      : 'https://api.mercadopago.com'

    const email = user_email || user.email || 'cliente@app.com'

    // Step 1: Find or create MP customer for this user+shop
    let customerId: string
    const searchRes = await fetch(`${baseUrl}/v1/customers/search?email=${encodeURIComponent(email)}&limit=1`, {
      headers: { 'Authorization': `Bearer ${accessToken}` }
    })
    const searchData = await searchRes.json()

    if (searchData.results && searchData.results.length > 0) {
      customerId = searchData.results[0].id
    } else {
      const createRes = await fetch(`${baseUrl}/v1/customers`, {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ email })
      })
      const createData = await createRes.json()
      if (!createData.id) {
        console.error('Create customer error:', createData)
        return new Response(JSON.stringify({ error: createData.message || 'Erro ao criar cliente.' }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
      customerId = createData.id
    }

    // Step 2: Save card token to MP customer
    const cardRes = await fetch(`${baseUrl}/v1/customers/${customerId}/cards`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: card_token })
    })
    const cardData = await cardRes.json()

    if (!cardData.id) {
      console.error('Save card to customer error:', cardData)
      // 400 from MP usually means card already saved or token reused — treat gracefully
      const errMsg = cardData.message || cardData.cause?.[0]?.description || 'Erro ao salvar cartão.'
      return new Response(JSON.stringify({ error: errMsg }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const mpCardId: string = cardData.id
    const brand: string = cardData.payment_method?.id || payment_method_id || 'unknown'
    const last4: string = cardData.last_four_digits || last_four || '****'
    const paymentMethodId: string = cardData.payment_method?.id || payment_method_id || ''

    // Step 3: Upsert in Supabase saved_cards (avoid duplicates by MP card ID)
    const { data: existing } = await supabaseAdmin
      .from('saved_cards')
      .select('id')
      .eq('user_id', user.id)
      .eq('shop_id', shop_id)
      .eq('cardId', mpCardId)
      .maybeSingle()

    if (!existing) {
      await supabaseAdmin.from('saved_cards').insert({
        user_id: user.id,
        shop_id,
        cardId: mpCardId,
        customerId,
        brand,
        last_4: last4,
        paymentMethodId,
      })
    }

    return new Response(JSON.stringify({
      success: true,
      cardId: mpCardId,
      customerId,
      brand,
      last4,
    }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    console.error('Error save-card:', error)
    return new Response(JSON.stringify({ success: false, error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
