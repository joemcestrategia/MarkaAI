/// <reference lib="deno.ns" />
import { serve } from "http/server"
import Stripe from 'stripe'
import { createClient } from 'supabase'
import { corsHeaders } from '../_shared/cors.ts'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { shop_id, new_plan_id, new_plan_name } = await req.json()

    if (!shop_id) {
      throw new Error('shop_id é obrigatório')
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') || '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    )

    // Buscar dados da loja
    const { data: shop, error: shopError } = await supabaseAdmin
      .from('shops')
      .select('subscription')
      .eq('id', shop_id)
      .maybeSingle()

    if (shopError || !shop) {
      throw new Error('Loja não encontrada')
    }

    const sub = shop.subscription
    if (!sub || !sub.stripe_subscription_id) {
      throw new Error('Nenhuma assinatura Stripe encontrada para reativar.')
    }

    // Reativar no Stripe (remover cancel_at_period_end)
    const reactivated = await stripe.subscriptions.update(sub.stripe_subscription_id, {
      cancel_at_period_end: false,
      metadata: {
        shop_id: shop_id,
        reactivated_at: new Date().toISOString(),
      },
    })

    const planId = new_plan_id || sub.plan_id || 'free'

    // Atualizar no Supabase
    await supabaseAdmin.from('shops').update({
      plan_id: planId,
      subscription: {
        ...sub,
        plan_id: planId,
        status: 'active',
        cancel_at_period_end: false,
        payment_provider: 'stripe',
        updated_at: new Date().toISOString(),
      },
    }).eq('id', shop_id)

    return new Response(JSON.stringify({
      message: `Assinatura reativada com sucesso! 🚀`,
      subscription_id: reactivated.id,
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
