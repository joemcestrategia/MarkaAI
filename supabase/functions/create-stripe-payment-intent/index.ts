/// <reference lib="deno.ns" />
import { serve } from "http/server"
import Stripe from 'stripe'
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
    const { amount, currency, description, shop_id } = await req.json()

    if (!amount || !currency) {
      throw new Error('amount e currency são obrigatórios')
    }

    // Criar PaymentIntent avulso (one-time, ex: boost)
    const paymentIntent = await stripe.paymentIntents.create({
      amount: amount, // já vem em centavos do Flutter
      currency: currency,
      description: description || 'Pagamento MarkaAI',
      metadata: {
        shop_id: shop_id || '',
        type: 'one_time',
      },
      automatic_payment_methods: { enabled: true },
    })

    return new Response(JSON.stringify({
      clientSecret: paymentIntent.client_secret,
      paymentIntentId: paymentIntent.id,
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
