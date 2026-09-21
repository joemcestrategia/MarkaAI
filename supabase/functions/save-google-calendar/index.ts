import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

const GOOGLE_CLIENT_ID = '170942564821-s8doqh3tcqe4rs7muauefgkdqehcf1l9.apps.googleusercontent.com'
const GOOGLE_TOKEN_URL = 'https://oauth2.googleapis.com/token'

async function exchangeAuthCode(serverAuthCode: string, isWeb: boolean): Promise<{ success: true; data: Record<string, unknown> } | { success: false; error: string }> {
  const clientSecret = Deno.env.get('GOOGLE_OAUTH_CLIENT_SECRET')
  if (!clientSecret) {
    console.error('[save-google-calendar] GOOGLE_OAUTH_CLIENT_SECRET não configurado')
    return { success: false, error: 'GOOGLE_OAUTH_CLIENT_SECRET não configurado no servidor' }
  }

  console.log('[save-google-calendar] Trocando auth code por tokens... isWeb=', isWeb)
  
  const bodyParams = new URLSearchParams({
    code: serverAuthCode,
    client_id: GOOGLE_CLIENT_ID,
    client_secret: clientSecret,
    grant_type: 'authorization_code',
  })
  
  if (isWeb) {
    bodyParams.append('redirect_uri', 'postmessage')
  }

  const tokenRes = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: bodyParams,
  })

  const tokenData = await tokenRes.json()
  if (!tokenRes.ok) {
    const googleError = tokenData.error_description || tokenData.error || JSON.stringify(tokenData)
    console.error('[save-google-calendar] Erro na troca do auth code:', tokenData)
    return { success: false, error: `Google OAuth error: ${googleError}` }
  }

  console.log('[save-google-calendar] Tokens obtidos: refresh_token=', tokenData.refresh_token ? 'SIM' : 'NÃO')
  return { success: true, data: tokenData }
}

async function refreshAccessToken(refreshToken: string): Promise<{ accessToken: string; expiresIn: number } | null> {
  const clientSecret = Deno.env.get('GOOGLE_OAUTH_CLIENT_SECRET')
  if (!clientSecret) {
    console.error('[save-google-calendar] GOOGLE_OAUTH_CLIENT_SECRET não configurado para refresh')
    return null
  }

  console.log('[save-google-calendar] Atualizando access token...')
  const tokenRes = await fetch(GOOGLE_TOKEN_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      refresh_token: refreshToken,
      client_id: GOOGLE_CLIENT_ID,
      client_secret: clientSecret,
      grant_type: 'refresh_token',
    }),
  })

  const tokenData = await tokenRes.json()
  if (!tokenRes.ok) {
    console.error('[save-google-calendar] Erro ao atualizar token:', tokenData)
    return null
  }

  return { accessToken: tokenData.access_token as string, expiresIn: tokenData.expires_in as number }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseAdmin = createSupabaseAdminClient()

    const body = await req.json().catch(() => ({}))
    const userId = body?.userId as string | null
    const employeeId = body?.employeeId as string | null
    const calendarData = body?.calendarData as Record<string, unknown> | null
    const serverAuthCode = body?.serverAuthCode as string | null
    const action = body?.action as string | null
    const platform = body?.platform as string | null

    if (!userId && !employeeId) {
      return new Response(
        JSON.stringify({ error: 'userId ou employeeId obrigatório' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Ação: refresh — atualiza o access token do refresh token armazenado e retorna
    if (action === 'refresh') {
      const tableToRead = employeeId ? 'employees' : 'users'
      const idValue = employeeId || userId

      const { data: doc, error: readError } = await supabaseAdmin
        .from(tableToRead)
        .select('google_calendar')
        .eq('id', idValue!)
        .maybeSingle()

      if (readError || !doc) {
        return new Response(
          JSON.stringify({ error: 'Falha ao ler dados de conexão' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const gcal = doc.google_calendar as Record<string, unknown> | null
      if (!gcal?.connected || !gcal?.refreshToken) {
        return new Response(
          JSON.stringify({ error: 'Profissional não tem refresh token armazenado' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const tokenData = await refreshAccessToken(gcal.refreshToken as string)
      if (!tokenData) {
        return new Response(
          JSON.stringify({ error: 'Falha ao renovar token' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const tokenExpiry = new Date(Date.now() + tokenData.expiresIn * 1000).toISOString()
      await supabaseAdmin
        .from(tableToRead)
        .update({
          google_calendar: {
            ...gcal,
            accessToken: tokenData.accessToken,
            tokenExpiry,
          },
        })
        .eq('id', idValue!)

      console.log(`[save-google-calendar] Token renovado para ${tableToRead} ID: ${idValue}`)
      return new Response(
        JSON.stringify({ success: true, accessToken: tokenData.accessToken }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const isDisconnect = calendarData === null || calendarData === undefined
    const tableToUpdate = employeeId ? 'employees' : 'users'
    const idColumn = 'id'
    const idValue = employeeId || userId

    // Se for conectar com serverAuthCode, troca por refresh token
    if (!isDisconnect && serverAuthCode) {
      console.log(`[save-google-calendar] Processando auth code para ${tableToUpdate} ID: ${idValue}`)
      const exchangeResult = await exchangeAuthCode(serverAuthCode, platform === 'web')

      if (exchangeResult.success) {
        const tokenData = exchangeResult.data
        
        if (!tokenData.refresh_token) {
          console.error(`[save-google-calendar] Nenhum refresh token no payload retornado. O consentimento foi ignorado.`)
          return new Response(
            JSON.stringify({ error: 'Falha crítica: Refresh Token ausente. Você precisa desconectar a conta e refazer o login aceitando as permissões.' }),
            { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        // Atualiza calendarData com refreshToken e accessToken do servidor
        const mergedData = {
          ...calendarData,
          accessToken: tokenData.access_token || calendarData?.accessToken,
          refreshToken: tokenData.refresh_token || null,
          tokenExpiry: tokenData.expires_in
            ? new Date(Date.now() + Number(tokenData.expires_in) * 1000).toISOString()
            : calendarData?.expiry,
        }

        const { error } = await supabaseAdmin
          .from(tableToUpdate)
          .update({ google_calendar: mergedData })
          .eq(idColumn, idValue)

        if (error) {
          console.error(`[save-google-calendar] Erro ao salvar com tokens: ${error.message}`)
          return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
          )
        }

        console.log(`[save-google-calendar] Conexão completa com refresh token para ${idValue}`)
        return new Response(
          JSON.stringify({ success: true, email: calendarData?.email, hasRefreshToken: !!mergedData.refreshToken }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      // Se tinha serverAuthCode mas a troca falhou, retorna erro detalhado do Google
      return new Response(
        JSON.stringify({ error: exchangeResult.error }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Guarda: se a ação era 'refresh' mas chegou aqui, não deve sobrescrever dados
    if (action === 'refresh') {
      console.error(`[save-google-calendar] action=refresh caiu fora do bloco de refresh — possível corpo mal formado`)
      return new Response(
        JSON.stringify({ error: 'Requisição de refresh inválida' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Salvar/desconectar sem troca de tokens
    console.log(`[save-google-calendar] ${isDisconnect ? 'Desconectando' : 'Salvando'} Google Calendar para ${tableToUpdate} ID: ${idValue}`)

    const { error } = await supabaseAdmin
      .from(tableToUpdate)
      .update({ google_calendar: isDisconnect ? null : calendarData })
      .eq(idColumn, idValue)

    if (error) {
      console.error(`[save-google-calendar] Erro ao salvar: ${error.message}`)
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!isDisconnect) {
      const { data: verifyDoc, error: verifyError } = await supabaseAdmin
        .from(tableToUpdate)
        .select('google_calendar')
        .eq(idColumn, idValue)
        .maybeSingle()

      if (verifyError) {
        return new Response(
          JSON.stringify({ error: verifyError.message }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      const saved = verifyDoc?.google_calendar as Record<string, unknown> | null
      if (!saved || !saved.connected) {
        return new Response(
          JSON.stringify({ error: 'Falha na verificação: dados não persistidos.' }),
          { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      return new Response(
        JSON.stringify({ success: true, email: saved.email }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    } else {
      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }
  } catch (err) {
    console.error(`[save-google-calendar] Erro inesperado:`, err)
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : 'Erro desconhecido' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
