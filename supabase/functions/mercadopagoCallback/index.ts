import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

const buildResultPage = (title: string, message: string, isError = false) => `
<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title}</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; background:#f6f7fb; margin:0; }
    .wrap { max-width:640px; margin:10vh auto; padding:0 16px; }
    .card { background:#fff; padding:24px; border-radius:16px; box-shadow:0 10px 30px rgba(0,0,0,.08); border:1px solid ${isError ? '#ffcdd2' : '#c8e6c9'}; }
    h1 { font-size:22px; margin:0 0 10px; color:${isError ? '#c62828' : '#2e7d32'}; }
    p { color:#444; line-height:1.6; margin:8px 0; }
    .badge { display:inline-block; font-size:12px; padding:4px 8px; border-radius:999px; background:${isError ? '#ffebee' : '#e8f5e9'}; color:${isError ? '#c62828' : '#2e7d32'}; }
    .steps { margin-top:12px; padding:12px; background:#f9fafc; border-radius:12px; border:1px dashed #dce2f0; }
    .steps li { margin:6px 0; }
    .footer { margin-top:14px; font-size:12px; color:#666; }
    .btn { display: inline-block; padding: 10px 20px; background: #5B2DB6; color: white; text-decoration: none; border-radius: 8px; font-weight: bold; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <span class="badge">${isError ? 'Falha' : 'Sucesso'}</span>
      <h1>${title}</h1>
      <p>${message}</p>
      <div class="steps">
        <strong>Próximos passos</strong>
        <ul>
          <li>Volte para o app MarkaAI.</li>
          <li>Se a tela não atualizar, feche e abra o app.</li>
        </ul>
      </div>
      <div style="margin-top:12px;">
        <a class="btn" href="markaai://mercadopago">Voltar para o app</a>
      </div>
      <div class="footer">Você pode fechar esta página com segurança.</div>
    </div>
  </div>
</body>
</html>
`

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)
  const code = url.searchParams.get('code')
  const state = url.searchParams.get('state')
  const error = url.searchParams.get('error')
  const errorDescription = url.searchParams.get('error_description') || 'Erro desconhecido'

  if (error) {
    return new Response(buildResultPage('Conexão não concluída', `Não foi possível conectar com o Mercado Pago. Detalhe: ${errorDescription}`, true), { headers: { 'Content-Type': 'text/html; charset=utf-8' }})
  }

  if (!code) {
    return new Response(buildResultPage('Conexão não concluída', 'Código de autorização ausente.', true), { headers: { 'Content-Type': 'text/html; charset=utf-8' }})
  }

  const clientId = Deno.env.get('MP_CLIENT_ID') || '8404269586602737'
  const clientSecret = Deno.env.get('MP_CLIENT_SECRET') || 'D1NjvPjNYSyUjWMfngTDsO0PDy0DaghB'
  // We determine the function's own URL from the request to pass as redirect_uri for MP.
  // In production, this should match exactly what is registered in MP Application.
  // Generally it is better to hardcode if the env changes. For now we use the Supabase Project URL.
  const redirectUri = `${Deno.env.get('SUPABASE_URL')}/functions/v1/mercadopagoCallback`

  try {
    const tokenRes = await fetch("https://api.mercadopago.com/oauth/token", {
      method: 'POST',
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
      },
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
      return new Response(buildResultPage('Conexão não concluída', tokens.message || 'Falha ao obter tokens.', true), { headers: { 'Content-Type': 'text/html; charset=utf-8' }})
    }

    let shopId = 'anon'
    if (state && state.startsWith('shop-')) {
      shopId = state.split('-')[1] || 'anon'
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
      return new Response(buildResultPage('Erro de Banco de Dados', 'Tokens obtidos, mas erro ao salvar na loja.', true), { headers: { 'Content-Type': 'text/html; charset=utf-8' }})
    }

    return new Response(buildResultPage('Conectado com sucesso', 'Sua conta Mercado Pago foi conectada. Agora você já pode voltar para o app.', false), { headers: { 'Content-Type': 'text/html; charset=utf-8' }})

  } catch (err) {
    console.error('Error Callback:', err)
    return new Response(buildResultPage('Erro Interno', err.message, true), { headers: { 'Content-Type': 'text/html; charset=utf-8' }})
  }
})
