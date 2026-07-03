/// <reference lib="deno.ns" />
import { serve } from "http/server"
import Stripe from 'stripe'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.3'
import { corsHeaders } from '../_shared/cors.ts'
import { getPriceIdFromPlanId } from '../_shared/plan-mapping.ts'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

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

    const body = await req.json()
    const {
      mode,        // 'subscription' | 'payment'
      plan_id,
      email,
      shop_id,
      amount,       // in centavos (only for mode=payment)
      currency,     // e.g. 'brl' (only for mode=payment)
      description,  // only for mode=payment
      boost_days,  // only for mode=payment (boost)
      success_url,
      cancel_url,
    } = body

    if (!success_url || !cancel_url) {
      throw new Error('success_url e cancel_url são obrigatórios')
    }

    // Find or create Stripe customer
    let customerId: string | undefined
    if (email) {
      const customers = await stripe.customers.list({ email, limit: 1 })
      if (customers.data.length > 0) {
        customerId = customers.data[0].id
      } else {
        const customer = await stripe.customers.create({
          email,
          metadata: { shop_id: shop_id || '' },
        })
        customerId = customer.id
      }
    }

    if (mode === 'subscription') {
      // ── Subscription Checkout ──────────────────────────────────
      if (!plan_id || !email || !shop_id) {
        throw new Error('plan_id, email e shop_id são obrigatórios para assinatura')
      }

      const priceId = getPriceIdFromPlanId(plan_id)
      if (!priceId) {
        throw new Error(`Plano inválido ou ID de preço não configurado: ${plan_id}`)
      }

      const sessionParams: Record<string, any> = {
        mode: 'subscription',
        line_items: [{ price: priceId, quantity: 1 }],
        success_url: `${success_url}?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url,
        metadata: {
          shop_id,
          plan_id,
        },
        subscription_data: {
          metadata: {
            shop_id,
            plan_id,
          },
        },
      }

      if (customerId) {
        sessionParams.customer = customerId
      } else {
        sessionParams.customer_email = email
      }

      // Lógica de cupons de afiliados removida

      const session = await stripe.checkout.sessions.create(sessionParams)

      return new Response(JSON.stringify({ url: session.url, sessionId: session.id }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })

    } else {
      // ── One-time Payment Checkout (boost) ──────────────────────
      if (!amount || !currency) {
        throw new Error('amount e currency são obrigatórios para pagamento avulso')
      }

      const sessionParams: Record<string, any> = {
        mode: 'payment',
        line_items: [{
          price_data: {
            currency,
            product_data: { name: description || 'Pagamento MarkaAI' },
            unit_amount: amount,
          },
          quantity: 1,
        }],
        success_url: `${success_url}?session_id={CHECKOUT_SESSION_ID}`,
        cancel_url,
        metadata: {
          shop_id: shop_id || '',
          type: 'one_time',
          description: description || '',
          ...(boost_days != null ? { boost_days: String(boost_days) } : {}),
        },
      }

      if (customerId) {
        sessionParams.customer = customerId
      } else if (email) {
        sessionParams.customer_email = email
      }

      const session = await stripe.checkout.sessions.create(sessionParams)

      return new Response(JSON.stringify({ url: session.url, sessionId: session.id }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

  } catch (err: any) {
    console.error('[create-stripe-checkout-session] Error:', err.message || err)
    return new Response(JSON.stringify({ error: err.message || 'Erro interno no servidor' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
