/// <reference lib="deno.ns" />
import { serve } from "http/server"
import Stripe from 'stripe'
import { createClient } from '../_shared/supabase.ts'
import { getPlanIdFromPriceId } from '../_shared/plan-mapping.ts'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

const endpointSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET') || ''

// Supabase admin client (service role) to bypass RLS
const supabaseAdmin = createClient(
  Deno.env.get('SUPABASE_URL') || '',
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || ''
)

serve(async (req: Request) => {
  // Only accept POST requests
  if (req.method !== 'POST') {
    return new Response('Metodo nao permitido', { status: 405 })
  }

  const signature = req.headers.get('Stripe-Signature')
  if (!signature) {
    return new Response('Sem assinatura', { status: 400 })
  }

  const body = await req.text()
  let event: Stripe.Event

  try {
    event = stripe.webhooks.constructEvent(body, signature, endpointSecret)
  } catch (err: any) {
    console.error(`⚠️  Falha na assinatura do Webhook: ${err.message}`)
    return new Response(`Webhook Error: ${err.message}`, { status: 400 })
  }

  console.log(`🔔 Recebido evento ${event.type} (${event.id})`)

  try {
    // ── Idempotency Check ────────────────────────────
    const { data: processedEvent } = await supabaseAdmin
      .from('processed_webhook_events')
      .select('id')
      .eq('id', event.id)
      .maybeSingle()
      
    if (processedEvent) {
      console.log(`Evento ${event.id} já processado, ignorando.`)
      return new Response(JSON.stringify({ received: true }), { status: 200 })
    }

    await supabaseAdmin
      .from('processed_webhook_events')
      .insert({ id: event.id })
    // ──────────────────────────────────────────────────

    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session
        
        if (session.mode === 'subscription') {
          const shopId = session.metadata?.shop_id || session.subscription_data?.metadata?.shop_id
          let planId = session.metadata?.plan_id
          
          if (!shopId) throw new Error('Missing shop_id in session metadata')

          const subscriptionId = typeof session.subscription === 'string' 
            ? session.subscription 
            : (session.subscription as Stripe.Subscription)?.id

          const customerId = typeof session.customer === 'string'
            ? session.customer
            : (session.customer as any)?.id

          if (subscriptionId && !planId) {
            const sub = await stripe.subscriptions.retrieve(subscriptionId)
            const priceId = sub.items.data[0]?.price.id
            planId = PRICE_IDS_REV[priceId] || 'free'
          }

          if (!planId) throw new Error('Missing plan_id resolving')

          console.log(`✔ Checkout Sucesso: Shop ${shopId} | Plano: ${planId}`)

          await supabaseAdmin.from('shops').update({
            plan_id: planId,
            trial_active: false,
            subscription: {
              plan_id: planId,
              status: 'active',
              payment_provider: 'stripe',
              stripe_subscription_id: subscriptionId || null,
              stripe_customer_id: customerId || null,
              updated_at: new Date().toISOString(),
            },
          }).eq('id', shopId)
        } else if (session.mode === 'payment') {
          const shopId = session.metadata?.shop_id
          const description = session.metadata?.description || ''
          const boostDays = parseInt(session.metadata?.boost_days || '0', 10)
          
          if (shopId && boostDays > 0) {
            const now = new Date()
            const expiresAt = new Date(now.getTime() + boostDays * 86400000)
            
            console.log(`🚀 Boost ativado: Shop ${shopId} por ${boostDays} dias, expira em ${expiresAt.toISOString()}`)
            
            const { data: existing } = await supabaseAdmin.from('shops').select('boost').eq('id', shopId).maybeSingle()
            let currentExpires: Date | null = null
            if (existing?.boost?.expires_at) {
              const cur = new Date(existing.boost.expires_at)
              if (cur > now) currentExpires = cur
            }
            const start = currentExpires || now
            const newExpiration = new Date(start.getTime() + boostDays * 86400000)
            
            await supabaseAdmin.from('shops').update({
              is_boosted: true,
              boost_expires_at: newExpiration.toISOString(),
              boost: {
                is_active: true,
                expires_at: newExpiration.toISOString(),
                updated_at: now.toISOString(),
              },
            }).eq('id', shopId)
          } else {
            console.log(`💳 One-time payment concluído para shop ${shopId}`)
          }
        }
        break
      }

      case 'invoice.paid': {
        const invoice = event.data.object as Stripe.Invoice
        const subscriptionId = typeof invoice.subscription === 'string' ? invoice.subscription : invoice.subscription?.id
        
        if (subscriptionId) {
          const subscription = await stripe.subscriptions.retrieve(subscriptionId)
          const shopId = subscription.metadata?.shop_id || subscription.metadata?.store_id
          
          if (shopId) {
            console.log(`💰 Fatura Paga: Renovação para ${shopId}`)
            const priceId = subscription.items.data[0]?.price.id
            const planId = getPlanIdFromPriceId(priceId) || subscription.metadata?.plan_id || 'free'

            await supabaseAdmin.from('shops').update({
              plan_id: planId,
              trial_active: false,
              subscription: {
                plan_id: planId,
                status: 'active',
                payment_provider: 'stripe',
                stripe_subscription_id: subscriptionId,
                stripe_customer_id: typeof invoice.customer === 'string' ? invoice.customer : '',
                updated_at: new Date().toISOString(),
              },
            }).eq('id', shopId)
          }
        }
        break
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const subscriptionId = typeof invoice.subscription === 'string' ? invoice.subscription : invoice.subscription?.id

        if (subscriptionId) {
          const subscription = await stripe.subscriptions.retrieve(subscriptionId)
          const shopId = subscription.metadata?.shop_id
          
          if (shopId) {
            console.error(`❌ Falha de Pagamento na Assinatura (Past Due): Shop ${shopId}`)
            // Update the DB to lock out the user due to payment failure
            const { data } = await supabaseAdmin.from('shops').select('subscription').eq('id', shopId).maybeSingle()
            if (data?.subscription) {
              await supabaseAdmin.from('shops').update({
                subscription: {
                  ...data.subscription,
                  status: 'past_due',
                  updated_at: new Date().toISOString(),
                }
              }).eq('id', shopId)
            }
          }
        }
        break
      }

      case 'customer.subscription.created': {
        const subscription = event.data.object as Stripe.Subscription
        const shopId = subscription.metadata?.shop_id || subscription.metadata?.store_id
        
        if (shopId) {
          console.log(`✨ Assinatura Criada: Shop ${shopId}`)
          
          const { data } = await supabaseAdmin.from('shops').select('subscription_started_at').eq('id', shopId).maybeSingle()
          
          const updates: any = {
            has_used_trial: true,
          }
          if (!data?.subscription_started_at) {
            updates.subscription_started_at = new Date(subscription.start_date * 1000).toISOString()
          }
          
          await supabaseAdmin.from('shops').update(updates).eq('id', shopId)
        }
        break
      }

      case 'customer.subscription.updated': {
        const subscription = event.data.object as Stripe.Subscription
        const shopId = subscription.metadata?.shop_id || subscription.metadata?.store_id
        
        if (shopId) {
          const priceId = subscription.items.data[0]?.price.id
          const planId = getPlanIdFromPriceId(priceId) || subscription.metadata?.plan_id || 'free'
          const status = subscription.status // "active", "past_due", "canceled", "unpaid"
          const cancelAtPeriodEnd = subscription.cancel_at_period_end
          const currentPeriodEnd = new Date(subscription.current_period_end * 1000).toISOString()

          console.log(`🔄 Assinatura Atualizada: Shop ${shopId} | Novo Status: ${status} | Plano: ${planId}`)

          const { data } = await supabaseAdmin.from('shops').select('subscription').eq('id', shopId).maybeSingle()
          
          await supabaseAdmin.from('shops').update({
            // Only update root plan_id to free if the status is actually canceled outright, 
            // OR keep it the new plan_id so downgrades take effect correctly on the cycle virada.
            plan_id: (status === 'canceled' || status === 'unpaid') ? 'free' : planId,
            trial_active: false,
            current_period_end: currentPeriodEnd,
            cancel_at_period_end: cancelAtPeriodEnd,
            subscription: {
              ...(data?.subscription || {}),
              plan_id: planId,
              status: status,
              payment_provider: 'stripe',
              cancel_at_period_end: cancelAtPeriodEnd,
              updated_at: new Date().toISOString(),
            }
          }).eq('id', shopId)
        }
        break
      }

      case 'customer.subscription.deleted': {
        const subscription = event.data.object as Stripe.Subscription
        const shopId = subscription.metadata?.shop_id || subscription.metadata?.store_id
        
        if (shopId) {
          console.log(`🗑 Assinatura Cancelada/Deletada Definitivamente: Shop ${shopId}`)
          
          // Wipe plan clean
          const { data } = await supabaseAdmin.from('shops').select('subscription').eq('id', shopId).maybeSingle()
          
          await supabaseAdmin.from('shops').update({
            plan_id: 'free',
            cancel_at_period_end: false,
            current_period_end: null,
            subscription: {
              ...(data?.subscription || {}),
              status: 'canceled',
              plan_id: 'free',
              cancel_at_period_end: false,
              updated_at: new Date().toISOString(),
            }
          }).eq('id', shopId)
        }
        break
      }

      default:
        console.log(`Evento ignorado: ${event.type}`)
    }

    return new Response(JSON.stringify({ received: true }), { status: 200 })
  } catch (err: any) {
    console.error(`Erro ao processar evento ${event.type}`, err)
    return new Response(`Erro Interno: ${err.message}`, { status: 500 })
  }
})
