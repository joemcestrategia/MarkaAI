import { serve } from "http/server"
import { createSupabaseClient, createSupabaseAdminClient } from '../_shared/supabase.ts'
import Stripe from 'stripe'
import { corsHeaders } from '../_shared/cors.ts'
import { genCouponCode, getAffiliateConfig } from '../_shared/affiliates.ts'

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY') || '', {
  apiVersion: '2023-10-16',
  httpClient: Stripe.createFetchHttpClient(),
})

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createSupabaseClient(req)

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser()
    if (authError || !user) {
      console.error('Auth Error:', authError)
      throw new Error(`Unauthorized: ${authError?.message || 'No user found'}`)
    }

    const url = new URL(req.url)
    const path = url.pathname.split('/').pop() || ''
    console.log(`Method: ${req.method}, Path: ${path}, FullPath: ${url.pathname}`)

    // --- GET /me ---
    if (req.method === 'GET' && (path === 'me' || path === '')) {
      const { data: affiliate, error } = await supabaseClient
        .from('affiliates')
        .select(`
          *,
          referrals:affiliate_referrals(count),
          commissions:affiliate_commissions(*)
        `)
        .eq('user_id', user.id)
        .maybeSingle()

      if (error) throw error
      return new Response(JSON.stringify(affiliate), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // --- POST /register ---
    if (req.method === 'POST' && path === 'register') {
      const { commission_type } = await req.json()
      
      // Check if already affiliate
      const { data: existing } = await supabaseClient
        .from('affiliates')
        .select('id')
        .eq('user_id', user.id)
        .maybeSingle()
      
      if (existing) {
        return new Response(JSON.stringify({ error: 'Você já possui um cadastro de afiliado.' }), {
          status: 409,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      // Generate unique coupon
      let couponCode = genCouponCode(user.user_metadata?.full_name || user.email || 'AFF')
      
      // Insert with service role to ensure uniqueness check and bypass some RLS if needed
      const supabaseAdmin = createSupabaseAdminClient()

      const { data: affiliate, error: insertError } = await supabaseAdmin
        .from('affiliates')
        .insert({
          user_id: user.id,
          coupon_code: couponCode,
          commission_type: commission_type || 'recurring',
          status: 'pending',
        })
        .select()
        .single()

      if (insertError) throw insertError

      return new Response(JSON.stringify(affiliate), {
        status: 201,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // --- POST /stripe-connect ---
    if (req.method === 'POST' && path === 'stripe-connect') {
      const { data: affiliate } = await supabaseClient
        .from('affiliates')
        .select('id, stripe_account_id')
        .eq('user_id', user.id)
        .single()

      if (!affiliate) throw new Error('Affiliate not found')

      let accountId = affiliate.stripe_account_id
      if (!accountId) {
        const account = await stripe.accounts.create({
          type: 'express',
          email: user.email,
          metadata: { affiliate_id: affiliate.id },
        })
        accountId = account.id
        
        const supabaseAdmin = createSupabaseAdminClient()
        await supabaseAdmin
          .from('affiliates')
          .update({ stripe_account_id: accountId })
          .eq('id', affiliate.id)
      }

      const accountLink = await stripe.accountLinks.create({
        account: accountId,
        refresh_url: `${url.origin}/affiliates/painel`, // URL do dashboard Next.js
        return_url: `${url.origin}/affiliates/painel`,
        type: 'account_onboarding',
      })

      return new Response(JSON.stringify({ url: accountLink.url }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // --- GET /stripe-status ---
    if (req.method === 'GET' && path === 'stripe-status') {
      const { data: affiliate } = await supabaseClient
        .from('affiliates')
        .select('id, stripe_account_id')
        .eq('user_id', user.id)
        .single()

      if (!affiliate || !affiliate.stripe_account_id) throw new Error('Invalid state')

      const account = await stripe.accounts.retrieve(affiliate.stripe_account_id)
      
      if (account.charges_enabled) {
        const supabaseAdmin = createSupabaseAdminClient()
        await supabaseAdmin
          .from('affiliates')
          .update({ stripe_onboarding_completed: true, status: 'active' })
          .eq('id', affiliate.id)
      }

      return new Response(JSON.stringify({ onboarding_completed: account.charges_enabled }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    return new Response('Not Found', { status: 404, headers: corsHeaders })

  } catch (err: any) {
    return new Response(JSON.stringify({ error: err.message || 'Erro interno no servidor' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
