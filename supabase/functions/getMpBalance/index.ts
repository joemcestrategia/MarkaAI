import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

/**
 * Renova o access_token OAuth do Mercado Pago usando o refresh_token.
 */
async function refreshMpToken(
  refreshToken: string,
  shopId: string,
  currentMp: Record<string, any>,
  supabase: any
): Promise<string | null> {
  const clientId = Deno.env.get('MP_CLIENT_ID')
  const clientSecret = Deno.env.get('MP_CLIENT_SECRET')

  if (!clientId || !clientSecret || !refreshToken) {
    console.error('refreshMpToken: credenciais ausentes ou refresh_token vazio')
    return null
  }

  try {
    const tokenRes = await fetch('https://api.mercadopago.com/oauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json' },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: clientSecret,
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
      }),
    })

    const tokens = await tokenRes.json()

    if (!tokenRes.ok) {
      console.error('refreshMpToken: erro:', JSON.stringify(tokens))
      return null
    }

    const updatedMp = {
      ...currentMp,
      access_token: tokens.access_token,
      refresh_token: tokens.refresh_token,
      user_id: tokens.user_id || currentMp.user_id,
      public_key: tokens.public_key || currentMp.public_key,
      connected: true,
      updated_at: new Date().toISOString(),
    }

    await supabase
      .from('shops')
      .update({ mercadopago: updatedMp })
      .eq('id', shopId)

    console.log('refreshMpToken: token renovado para shop', shopId)
    return tokens.access_token
  } catch (err) {
    console.error('refreshMpToken: exceção:', err)
    return null
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseAdminClient()
    const { shop_id } = await req.json()

    if (!shop_id) {
      return new Response(
        JSON.stringify({ error: 'shop_id é obrigatório.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { data: shopDoc, error: shopErr } = await supabase
      .from('shops')
      .select('mercadopago')
      .eq('id', shop_id)
      .single()

    if (shopErr || !shopDoc) {
      return new Response(
        JSON.stringify({ error: 'Loja não encontrada.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    let accessToken = shopDoc.mercadopago?.access_token
    const refreshToken = shopDoc.mercadopago?.refresh_token

    if (!accessToken) {
      return new Response(
        JSON.stringify({ error: 'Mercado Pago não conectado nesta loja.' }),
        { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const baseUrl = 'https://api.mercadopago.com'

    // 1. Obter user_id (já salvo no OAuth callback)
    let mpUserId = shopDoc.mercadopago?.user_id

    if (!mpUserId) {
      const meRes = await fetch(`${baseUrl}/users/me`, {
        headers: { 'Authorization': `Bearer ${accessToken}` },
      })

      if (!meRes.ok && (meRes.status === 401 || meRes.status === 403) && refreshToken) {
        const newToken = await refreshMpToken(refreshToken, shop_id, shopDoc.mercadopago, supabase)
        if (newToken) {
          accessToken = newToken
          const meRes2 = await fetch(`${baseUrl}/users/me`, {
            headers: { 'Authorization': `Bearer ${accessToken}` },
          })
          if (meRes2.ok) {
            const meData2 = await meRes2.json()
            mpUserId = meData2.id
          }
        }
      } else if (meRes.ok) {
        const meData = await meRes.json()
        mpUserId = meData.id
      }

      if (mpUserId) {
        const currentMp = shopDoc.mercadopago || {}
        await supabase
          .from('shops')
          .update({ mercadopago: { ...currentMp, user_id: mpUserId } })
          .eq('id', shop_id)
      }
    }

    if (!mpUserId) {
      return new Response(
        JSON.stringify({ error: 'Não foi possível obter o user_id do Mercado Pago.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Buscar saldo REAL — endpoint oficial do Mercado Pago
    let res = await fetch(
      `${baseUrl}/users/${mpUserId}/mercadopago_account/balance`,
      { headers: { 'Authorization': `Bearer ${accessToken}` } }
    )

    // 3. Se token expirado, renova e tenta novamente
    if ((res.status === 401 || res.status === 403) && refreshToken) {
      console.log('getMpBalance: tentando renovar token...')
      const newToken = await refreshMpToken(refreshToken, shop_id, shopDoc.mercadopago, supabase)
      if (newToken) {
        res = await fetch(
          `${baseUrl}/users/${newToken ? mpUserId : mpUserId}/mercadopago_account/balance`,
          { headers: { 'Authorization': `Bearer ${newToken}` } }
        )
      }
    }

    const data = await res.json()

    if (!res.ok) {
      // Se 403 mesmo após refresh, é problema de scope — orienta reconectar
      const needsReconnect = res.status === 403
      return new Response(
        JSON.stringify({
          error: needsReconnect
            ? 'Permissão insuficiente. Desconecte e reconecte o Mercado Pago em Configurações > Pagamentos para atualizar as permissões.'
            : 'Erro ao consultar saldo',
          details: data,
          needs_reconnect: needsReconnect,
        }),
        { status: res.status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify(data),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    console.error('Error getMpBalance:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
