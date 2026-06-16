import { createSupabaseAdminClient } from '../_shared/supabase.ts'

// ESTRATÉGIA: Nunca retornar HTML (problema com Supabase/Cloudflare sobrescrevendo content-type).
// Em SUCESSO: redirect 302 direto para deep link markaai://mercadopago?connected=true
// Em ERRO: redirect 302 para markaai://mercadopago?error=MENSAGEM

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      }
    })
  }

  const url = new URL(req.url)
  const code = url.searchParams.get('code')
  const state = url.searchParams.get('state')
  const error = url.searchParams.get('error')
  const errorDescription = url.searchParams.get('error_description') || 'Erro desconhecido'

  const appSuccess = 'markaai://mercadopago?connected=true'
  const appError = (msg: string) => `markaai://mercadopago?error=${encodeURIComponent(msg)}`

  if (error) {
    return Response.redirect(appError(errorDescription), 302)
  }

  if (!code) {
    // Acesso direto sem parâmetros: apenas informativo
    return Response.redirect(appError('Inicie o processo pelo aplicativo MarkaAI.'), 302)
  }

  const clientId = Deno.env.get('MP_CLIENT_ID')
  const clientSecret = Deno.env.get('MP_CLIENT_SECRET')
  if (!clientId || !clientSecret) {
    return Response.redirect(appError('Configuração do Mercado Pago ausente.'), 302)
  }
  const redirectUri = `${Deno.env.get('SUPABASE_URL')}/functions/v1/mercadopagoCallback`

  try {
    const tokenRes = await fetch('https://api.mercadopago.com/oauth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'application/json' },
      body: new URLSearchParams({
        client_id: clientId || '',
        client_secret: clientSecret || '',
        code: code,
        grant_type: 'authorization_code',
        redirect_uri: redirectUri
      })
    })

    const tokens = await tokenRes.json()

    if (!tokenRes.ok) {
      console.error('MP Token Error:', tokens)
      return Response.redirect(appError(tokens.message || 'Falha ao obter tokens.'), 302)
    }

    // Extrair shopId do state: formato "shop-UUID-TIMESTAMP"
    let shopId = 'anon'
    if (state && state.startsWith('shop-')) {
      shopId = state.substring(state.indexOf('-') + 1, state.lastIndexOf('-')) || 'anon'
    }

    const supabase = createSupabaseAdminClient()
    const { error: updateError } = await supabase.from('shops').update({
      mercadopago: {
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        user_id: tokens.user_id,
        public_key: tokens.public_key,
        connected: true,
        updated_at: new Date().toISOString()
      },
      payment_provider: 'mercadopago'
    }).eq('id', shopId)

    if (updateError) {
      console.error('Supabase update error:', updateError)
      return Response.redirect(appError('Tokens obtidos mas erro ao salvar.'), 302)
    }

    // SUCESSO: redireciona direto para o app — o Android abre via intent
    return Response.redirect(appSuccess, 302)

  } catch (err: any) {
    console.error('Error:', err)
    return Response.redirect(appError('Erro interno inesperado.'), 302)
  }
})
