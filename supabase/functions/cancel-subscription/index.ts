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
    const { shop_id } = await req.json()

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
      // Sem assinatura Stripe ativa — cancelar localmente
      await supabaseAdmin.from('shops').update({
        plan_id: 'free',
        trial_active: false,
        subscription: {
          ...sub,
          status: 'canceled',
          updated_at: new Date().toISOString(),
        },
      }).eq('id', shop_id)

      return new Response(JSON.stringify({
        message: 'Assinatura cancelada localmente.',
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // Cancelar no Stripe ao fim do período atual
    const canceled = await stripe.subscriptions.update(sub.stripe_subscription_id, {
      cancel_at_period_end: true,
    })

    const accessUntil = canceled.current_period_end
      ? new Date(canceled.current_period_end * 1000).toISOString()
      : new Date().toISOString()

    // Atualizar no Supabase
    await supabaseAdmin.from('shops').update({
      subscription: {
        ...sub,
        status: 'canceled',
        cancel_at_period_end: true,
        access_until: accessUntil,
        updated_at: new Date().toISOString(),
      },
    }).eq('id', shop_id)

    return new Response(JSON.stringify({
      message: `Assinatura cancelada. Acesso mantido até ${new Date(accessUntil).toLocaleDateString('pt-BR')}.`,
      access_until: accessUntil,
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
