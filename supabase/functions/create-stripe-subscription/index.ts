/// <reference lib="deno.ns" />
import { serve } from "http/server"
import Stripe from 'stripe'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
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
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { status: 401, headers: corsHeaders })
    }

    const jwt = authHeader.replace('Bearer ', '')

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') || '',
      Deno.env.get('SUPABASE_ANON_KEY') || ''
    )

    let user: any
    try {
      const { data, error: userError } = await supabaseClient.auth.getUser(jwt)
      if (userError || !data?.user) {
        return new Response(JSON.stringify({ error: 'Unauthorized', details: userError }), { status: 401, headers: corsHeaders })
      }
      user = data.user
    } catch (_) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: corsHeaders })
    }

    const { plan_id, email, shop_id } = await req.json()

    if (!plan_id || !email || !shop_id) {
      throw new Error('Dados incompletos')
    }

    const priceId = PRICE_IDS[plan_id]
    if (!priceId) {
      throw new Error(`Plano inválido ou ID de preço não configurado: ${plan_id}`)
    }

    // 1. Buscar ou Criar Cliente
    let customer
    const customers = await stripe.customers.list({ email: email, limit: 1 })
    if (customers.data.length > 0) {
      customer = customers.data[0]
    } else {
      customer = await stripe.customers.create({
        email: email,
        metadata: { shop_id: shop_id }
      })
    }

    // 2. Criar Chave Efêmera
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customer.id },
      { apiVersion: '2023-10-16' }
    )

    // 3. Criar a Assinatura (Status: incomplete para processar via PaymentSheet)
    const subscriptionData: Stripe.SubscriptionCreateParams = {
      customer: customer.id,
      items: [{ price: priceId }],
      payment_behavior: 'default_incomplete',
      payment_settings: { save_default_payment_method: 'on_subscription' },
      expand: ['latest_invoice.payment_intent'],
      metadata: { 
        store_id: shop_id,
      },
    }

    const subscription = await stripe.subscriptions.create(subscriptionData)

    const invoice = subscription.latest_invoice as any
    const paymentIntent = invoice.payment_intent

    return new Response(JSON.stringify({
      subscriptionId: subscription.id,
      paymentIntentClientSecret: paymentIntent.client_secret,
      customer: customer.id,
      ephemeralKey: ephemeralKey.secret,
      publishableKey: Deno.env.get('STRIPE_PUBLISHABLE_KEY') // Recomendado passar pelo env
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
