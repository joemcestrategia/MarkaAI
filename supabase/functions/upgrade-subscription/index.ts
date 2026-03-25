/// <reference lib="deno.ns" />
import { serve } from "http/server"
import Stripe from 'stripe'
import { createClient } from 'supabase'
import { corsHeaders } from '../_shared/cors.ts'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const PRICE_IDS: Record<string, string> = {
  'starter': 'price_1T98YSFzh8r5AMGzkMdAH2eq',
  'start': 'price_1T98YSFzh8r5AMGzkMdAH2eq',
  'plus': 'price_1T98ZPFzh8r5AMGzUHfVZRfC',
  'pro': 'price_1T98aHFzh8r5AMGzlgvM6eSZ',
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { shop_id, new_plan_id, new_plan_name, new_plan_price } = await req.json()

    if (!shop_id || !new_plan_id) {
      throw new Error('shop_id e new_plan_id são obrigatórios')
    }

    const newPriceId = PRICE_IDS[new_plan_id]
    if (!newPriceId) {
      throw new Error(`Plano inválido: ${new_plan_id}`)
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
      throw new Error('Nenhuma assinatura Stripe ativa encontrada para upgrade.')
    }

    // Buscar a assinatura no Stripe
    const subscription = await stripe.subscriptions.retrieve(sub.stripe_subscription_id)
    if (!subscription || !subscription.items.data.length) {
      throw new Error('Assinatura não encontrada no Stripe.')
    }

    const currentItemId = subscription.items.data[0].id

    // Atualizar item da assinatura (pro-rata automático pelo Stripe)
    const updated = await stripe.subscriptions.update(sub.stripe_subscription_id, {
      items: [{
        id: currentItemId,
        price: newPriceId,
      }],
      proration_behavior: 'create_prorations',
      cancel_at_period_end: false,
      metadata: {
        shop_id: shop_id,
        plan_id: new_plan_id,
      },
    })

    // Atualizar no Supabase
    await supabaseAdmin.from('shops').update({
      plan_id: new_plan_id,
      trial_active: false,
      subscription: {
        ...sub,
        plan_id: new_plan_id,
        status: 'active',
        cancel_at_period_end: false,
        payment_provider: 'stripe',
        updated_at: new Date().toISOString(),
      },
    }).eq('id', shop_id)

    return new Response(JSON.stringify({
      message: `Plano atualizado para ${new_plan_name || new_plan_id} com sucesso!`,
      subscription_id: updated.id,
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
