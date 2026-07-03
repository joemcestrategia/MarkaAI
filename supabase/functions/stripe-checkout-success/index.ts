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

const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL') || '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
)

serve(async (req: Request) => {
  const url = new URL(req.url)

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    let sessionId: string | null = null

    if (req.method === 'GET') {
      sessionId = url.searchParams.get('session_id')
    } else {
      const body = await req.json()
      sessionId = body.session_id
    }

    if (!sessionId) {
      throw new Error('session_id é obrigatório')
    }

    const session = await stripe.checkout.sessions.retrieve(sessionId, {
      expand: ['subscription', 'payment_intent'],
    })

    if (session.payment_status !== 'paid') {
      if (req.method === 'GET') {
        return _htmlResponse('Pagamento Pendente',
          'Seu pagamento ainda não foi confirmado. Tente novamente em alguns instantes.',
          url.searchParams.get('app_url') || '/', false)
      }
      return new Response(JSON.stringify({
        success: false,
        error: 'Pagamento não confirmado',
        status: session.payment_status,
      }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const mode = session.mode

    let resolvedShopId: string | undefined = undefined
    let resolvedPlanId: string | undefined = undefined

    if (mode === 'subscription') {
      resolvedShopId = session.metadata?.shop_id || session.subscription_data?.metadata?.shop_id
      resolvedPlanId = session.metadata?.plan_id

      if (!resolvedShopId) {
        console.error('[stripe-checkout-success] shop_id ausente no metadata da sessão')
        throw new Error('Dados da loja não encontrados na sessão de checkout.')
      }

      const subscriptionId = typeof session.subscription === 'string'
        ? session.subscription
        : (session.subscription as Stripe.Subscription)?.id

      const customerId = typeof session.customer === 'string'
        ? session.customer
        : (session.customer as any)?.id

      if (subscriptionId && !resolvedPlanId) {
        const sub = await stripe.subscriptions.retrieve(subscriptionId)
        const priceId = sub.items.data[0]?.price.id
        resolvedPlanId = getPlanIdFromPriceId(priceId) || 'free'
      }

      if (!resolvedPlanId) {
        console.error('[stripe-checkout-success] plan_id não resolvido')
        throw new Error('Não foi possível identificar o plano contratado.')
      }

      console.log(`[stripe-checkout-success] Atualizando DB: Shop ${resolvedShopId} → Plano ${resolvedPlanId}`)

      await supabaseAdmin.from('shops').update({
        plan_id: resolvedPlanId,
        trial_active: false,
        subscription: {
          plan_id: resolvedPlanId,
          status: 'active',
          payment_provider: 'stripe',
          stripe_subscription_id: subscriptionId || null,
          stripe_customer_id: customerId || null,
          updated_at: new Date().toISOString(),
        },
      }).eq('id', resolvedShopId)

    } else if (mode === 'payment') {
      resolvedShopId = session.metadata?.shop_id
      const description = session.metadata?.description || ''
      console.log(`[stripe-checkout-success] Pagamento avulso (Boost) confirmado para shop ${resolvedShopId}: ${description}`)
    }

    if (req.method === 'GET') {
      const appUrl = url.searchParams.get('app_url') || '/'
      return _htmlResponse('Pagamento Confirmado!',
        mode === 'subscription'
          ? 'Sua assinatura foi ativada com sucesso! Redirecionando...'
          : 'Pagamento confirmado com sucesso! Redirecionando...',
        appUrl, true)
    }

    return new Response(JSON.stringify({
      success: true,
      mode,
      plan_id: resolvedPlanId,
      shop_id: resolvedShopId,
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (err: any) {
    console.error('[stripe-checkout-success] Error:', err.message)

    if (req.method === 'GET') {
      return _htmlResponse('Erro', err.message || 'Erro ao verificar pagamento.', '/', false)
    }

    return new Response(JSON.stringify({ error: err.message || 'Erro interno' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

function _htmlResponse(title: string, message: string, redirectUrl: string, success: boolean): Response {
  const color = success ? '#16a34a' : '#dc2626'
  const icon = success ? '✅' : '⚠️'
  const html = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${title} - MarkaAI</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #f8f9fd;
      display: flex; align-items: center; justify-content: center;
      min-height: 100vh; padding: 24px;
    }
    .card {
      background: white; border-radius: 16px; padding: 48px 32px;
      text-align: center; max-width: 420px; width: 100%;
      box-shadow: 0 4px 24px rgba(0,0,0,0.08);
    }
    .icon { font-size: 56px; margin-bottom: 16px; }
    h1 { color: ${color}; font-size: 24px; margin-bottom: 12px; }
    p { color: #6b7280; font-size: 16px; line-height: 1.5; margin-bottom: 24px; }
    a {
      display: inline-block; padding: 14px 32px;
      background: #6B21A8; color: white; border-radius: 12px;
      text-decoration: none; font-weight: 600; font-size: 16px;
    }
    a:hover { background: #581c87; }
  </style>
  ${success ? `<meta http-equiv="refresh" content="3;url=${redirectUrl}">` : ''}
</head>
<body>
  <div class="card">
    <div class="icon">${icon}</div>
    <h1>${title}</h1>
    <p>${message}</p>
    <a href="${redirectUrl}">Voltar ao MarkaAI</a>
  </div>
</body>
</html>`

  return new Response(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  })
}
