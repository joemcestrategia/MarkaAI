import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseAdminClient()
    const { shop_id } = await req.json()

    if (!shop_id) {
      return new Response(
        JSON.stringify({ error: 'shop_id é obrigatório.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Busca o access_token do Mercado Pago da loja
    const { data: shopDoc, error: shopErr } = await supabase
      .from('shops')
      .select('mercadopago')
      .eq('id', shop_id)
      .single()

    if (shopErr || !shopDoc) {
      return new Response(
        JSON.stringify({ error: 'Loja não encontrada.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const accessToken = shopDoc.mercadopago?.access_token
    if (!accessToken) {
      return new Response(
        JSON.stringify({ error: 'Mercado Pago não conectado nesta loja.' }),
        { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const baseUrl = 'https://api.mercadopago.com'

    const res = await fetch(`${baseUrl}/v1/balance`, {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    })

    const data = await res.json()

    if (!res.ok) {
      return new Response(
        JSON.stringify({ error: 'Erro ao consultar saldo', details: data }),
        { status: res.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify(data),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error getMpBalance:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
