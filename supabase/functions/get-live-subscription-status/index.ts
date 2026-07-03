/// <reference lib="deno.ns" />
import { serve } from "http/server"
import Stripe from 'stripe'
import { createClient } from 'supabase'
import { corsHeaders } from '../_shared/cors.ts'
import { getPlanIdFromPriceId } from '../_shared/plan-mapping.ts'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { shopId } = await req.json()

    if (!shopId) {
      throw new Error('shopId é obrigatório')
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL') || '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
    )

    // 1. Busca o shop no banco
    const { data: shop, error: shopError } = await supabaseAdmin
      .from('shops')
      .select('subscription, has_used_trial, plan_id, cancel_at_period_end, current_period_end, subscription_started_at')
      .eq('id', shopId)
      .maybeSingle()

    if (shopError || !shop) {
      throw new Error('Loja não encontrada')
    }

    const sub = shop.subscription
    const stripeSubId = sub?.stripe_subscription_id

    // 2. Se não houver stripe_subscription_id
    if (!stripeSubId) {
      return new Response(JSON.stringify({
        status: sub?.status || (shop.plan_id !== 'free' ? 'active' : 'free'),
        planId: shop.plan_id || 'free',
        subscriptionStartedAt: shop.subscription_started_at || null,
        currentPeriodEnd: shop.current_period_end || null,
        cancelAtPeriodEnd: shop.cancel_at_period_end || false,
        hasUsedTrial: shop.has_used_trial || false,
        isManual: true,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 3. Chama a API da Stripe diretamente
    try {
      const stripeSub = await stripe.subscriptions.retrieve(stripeSubId)
      
      // 4. Extrai os dados
      const status = stripeSub.status
      const subscriptionStartedAt = new Date(stripeSub.start_date * 1000).toISOString()
      const currentPeriodEnd = new Date(stripeSub.current_period_end * 1000).toISOString()
      const cancelAtPeriodEnd = stripeSub.cancel_at_period_end
      
      const priceId = stripeSub.items.data[0]?.price.id
      const planId = getPlanIdFromPriceId(priceId) || stripeSub.metadata?.plan_id || 'free'
      
      const realPlanId = (status === 'canceled' || status === 'unpaid') ? 'free' : planId

      // Logging divergência
      if (shop.plan_id !== realPlanId) {
        console.log(`⚠️ Divergência de plan_id: Banco (${shop.plan_id}) vs Stripe (${realPlanId}) para shop ${shopId}`)
      }

      // 5. Upsert no cache local
      await supabaseAdmin.from('shops').update({
        plan_id: realPlanId,
        trial_active: status === 'trialing',
        subscription_started_at: subscriptionStartedAt,
        current_period_end: currentPeriodEnd,
        cancel_at_period_end: cancelAtPeriodEnd,
        subscription: {
          ...sub,
          plan_id: realPlanId,
          status: status,
          payment_provider: 'stripe',
          cancel_at_period_end: cancelAtPeriodEnd,
          updated_at: new Date().toISOString(),
        }
      }).eq('id', shopId)

      // 6. Retorna ao cliente
      return new Response(JSON.stringify({
        status: status,
        planId: realPlanId,
        subscriptionStartedAt,
        currentPeriodEnd,
        cancelAtPeriodEnd,
        hasUsedTrial: shop.has_used_trial || false,
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })

    } catch (stripeErr: any) {
      // 7. Erro resource_missing da Stripe
      if (stripeErr.code === 'resource_missing' || stripeErr.statusCode === 404) {
        console.log(`🗑 Assinatura não encontrada na Stripe. Rebaixando cache do shop ${shopId}.`)
        
        await supabaseAdmin.from('shops').update({
          plan_id: 'free',
          cancel_at_period_end: false,
          current_period_end: null,
          subscription: {
            ...sub,
            status: 'canceled',
            plan_id: 'free',
            cancel_at_period_end: false,
            updated_at: new Date().toISOString(),
          }
        }).eq('id', shopId)

        return new Response(JSON.stringify({
          status: 'free',
          planId: 'free',
          subscriptionStartedAt: null,
          currentPeriodEnd: null,
          cancelAtPeriodEnd: false,
          hasUsedTrial: shop.has_used_trial || false,
        }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      throw stripeErr // Passa outros erros para o try/catch genérico
    }

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Erro interno no servidor' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
