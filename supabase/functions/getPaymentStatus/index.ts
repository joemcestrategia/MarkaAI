import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseClient(req)
    const { access_token, shop_id, payment_id } = await req.json()

    let tokenToUse = access_token

    if (!tokenToUse && shop_id) {
      const { data: shopDoc } = await supabase.from('shops').select('mercadopago').eq('id', shop_id).single()
      if (shopDoc) {
        tokenToUse = shopDoc.mercadopago?.access_token
      }
    }

    if (!tokenToUse) {
      return new Response(JSON.stringify({ error: 'Token de acesso não encontrado para esta loja.' }), { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const baseUrl = (tokenToUse.startsWith('TEST-'))
      ? 'https://api.sandbox.mercadopago.com'
      : 'https://api.mercadopago.com'

    const res = await fetch(`${baseUrl}/v1/payments/${payment_id}`, {
      headers: { 'Authorization': `Bearer ${tokenToUse}` }
    })
    
    const data = await res.json()

    if (!res.ok) {
      return new Response(JSON.stringify({ error: 'Erro ao consultar status', details: data }), { status: res.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify(data), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    console.error('Error getPaymentStatus:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
