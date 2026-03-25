import { serve } from "http/server"
import { createClient } from 'supabase'
import { corsHeaders } from '../_shared/cors.ts'
import { getAffiliateConfig } from '../_shared/affiliates.ts'

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { coupon_code, store_id } = await req.json()
    if (!coupon_code || !store_id) throw new Error('Dados incompletos')

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // 1. Seek affiliate
    const { data: affiliate, error: affError } = await supabaseAdmin
      .from('affiliates')
      .select('id, store_id, status, commission_type')
      .eq('coupon_code', coupon_code.toUpperCase())
      .single()

    if (affError || !affiliate) {
      return new Response(JSON.stringify({ valid: false, message: 'Cupom inválido ou inexistente.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (affiliate.status !== 'active') {
      return new Response(JSON.stringify({ valid: false, message: 'Este cupom não está ativo no momento.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 2. Anti-self-referral
    if (affiliate.store_id === store_id) {
      return new Response(JSON.stringify({ valid: false, message: 'Uma loja não pode usar o próprio cupom de afiliado.' }), {
        status: 403,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 3. One referral per store
    const { data: existingReferral } = await supabaseAdmin
      .from('affiliate_referrals')
      .select('id')
      .eq('referred_store_id', store_id)
      .maybeSingle()

    if (existingReferral) {
      return new Response(JSON.stringify({ valid: false, message: 'Esta loja já utilizou um cupom de indicação anteriormente.' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 4. Get program config
    const config = await getAffiliateConfig(supabaseAdmin)

    return new Response(JSON.stringify({
      valid: true,
      discount_percent: config.discount_percent,
      affiliate_id: affiliate.id,
      commission_type: affiliate.commission_type,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Erro interno no servidor' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
