import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'
import { corsHeaders } from '../_shared/cors.ts'

/**
 * Edge Function: sendPasswordReset
 *
 * Gera um link de recuperação de senha via Supabase Admin API e envia por email
 * usando o Resend — o mesmo provedor já utilizado para notificações de agendamento.
 *
 * Body: { email: string }
 */
serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email } = await req.json()

    if (!email || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'E-mail inválido.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const supabase = createSupabaseAdminClient()

    // ─── 0. Verificar se o usuário existe no banco de dados ──────────────────
    console.log('[sendPasswordReset] Validando e-mail:', email)
    
    const { data: userData, error: userError } = await supabase
      .from('users')
      .select('id')
      .ilike('email', email.trim())
      .maybeSingle()

    if (userError) {
      console.error('[sendPasswordReset] Erro na consulta ao banco:', userError)
      return new Response(
        JSON.stringify({ error: 'Erro interno ao validar e-mail no banco.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!userData) {
      console.warn('[sendPasswordReset] Usuário não encontrado (resposta genérica enviada):', email)
      return new Response(
        JSON.stringify({ success: true }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('[sendPasswordReset] Usuário validado OK:', userData.id)

    // ─── 1. Gerar link de recuperação via Admin API ───────────────────────────
    const redirectTo = Deno.env.get('APP_URL')
      ? `${Deno.env.get('APP_URL')}/reset-password`
      : 'https://markaai.com.br/reset-password'

    const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
      type: 'recovery',
      email: email.trim(),
      options: { redirectTo },
    })

    if (linkError || !linkData?.properties?.action_link) {
      console.error('[sendPasswordReset] Erro ao gerar link:', linkError)
      return new Response(
        JSON.stringify({ error: linkError?.message ?? 'Não foi possível gerar o link.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const recoveryLink = linkData.properties.action_link
    console.log('[sendPasswordReset] Link gerado para:', email)

    // ─── 2. Enviar email via Resend ───────────────────────────────────────────
    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    const from = Deno.env.get('EMAIL_FROM') || 'MarkaAI <no-reply@markaai.com.br>'

    if (!resendApiKey) {
      console.error('[sendPasswordReset] RESEND_API_KEY não configurado.')
      return new Response(
        JSON.stringify({ error: 'Configuração de e-mail ausente.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const emailHtml = `
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Redefinir Senha – MarkaAI</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">

  <span style="display:none;max-height:0;overflow:hidden;mso-hide:all;">
    Recebemos uma solicitação para redefinir a senha da sua conta MarkaAI.
  </span>

  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f0fb;">
    <tr>
      <td align="center" style="padding:48px 20px;">

        <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">

          <!-- ══ HEADER: MARCA ══ -->
          <tr>
            <td align="center" style="
              background:linear-gradient(160deg, #3b0f8c 0%, #5c1fc4 60%, #7c3aed 100%);
              border-radius:16px 16px 0 0;
              padding:36px 48px 32px;
            ">
              <img
                src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png"
                alt="MarkaAI"
                width="148"
                style="display:block;margin:0 auto;max-height:44px;object-fit:contain;"
              />
            </td>
          </tr>

          <!-- Linha separadora colorida fina -->
          <tr>
            <td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td>
          </tr>

          <!-- ══ CORPO ══ -->
          <tr>
            <td style="background:#ffffff;padding:44px 48px 36px;">

              <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">
                Olá! Recebemos um pedido para redefinir sua senha 👋
              </p>

              <p style="margin:0 0 16px;color:#4b5563;font-size:15px;line-height:1.75;">
                Identificamos uma solicitação de redefinição de senha para a sua conta no <strong style="color:#5c1fc4;">MarkaAI</strong>. Clique no botão abaixo para criar uma nova senha com segurança.
              </p>

              <p style="margin:0 0 36px;color:#4b5563;font-size:15px;line-height:1.75;">
                O link é válido por <strong style="color:#5c1fc4;">1 hora</strong>.
              </p>

              <!-- Botão -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="padding-bottom:36px;">
                    <a href="${recoveryLink}"
                       style="
                         display:inline-block;
                         background:linear-gradient(135deg,#5c1fc4,#7c3aed);
                         color:#ffffff;
                         text-decoration:none;
                         font-size:15px;
                         font-weight:600;
                         padding:16px 44px;
                         border-radius:10px;
                         letter-spacing:0.2px;
                         box-shadow:0 6px 20px rgba(92,31,196,0.35);
                       ">
                      Redefinir minha senha
                    </a>
                  </td>
                </tr>
              </table>

              <!-- Alerta -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom:28px;">
                <tr>
                  <td style="
                    background:#faf5ff;
                    border-left:3px solid #7c3aed;
                    border-radius:0 8px 8px 0;
                    padding:14px 18px;
                  ">
                    <p style="margin:0;color:#5b21b6;font-size:13px;line-height:1.6;">
                      <strong>Não foi você?</strong> Ignore este email com segurança — sua senha não será alterada.
                    </p>
                  </td>
                </tr>
              </table>

              <!-- Link alternativo -->
              <p style="margin:0 0 4px;color:#9ca3af;font-size:12px;">Se o botão não funcionar, use este link:</p>
              <p style="margin:0;color:#7c3aed;font-size:12px;word-break:break-all;line-height:1.6;">${recoveryLink}</p>

            </td>
          </tr>

          <!-- ══ FOOTER ══ -->
          <tr>
            <td style="
              background:#faf8ff;
              border-top:1px solid #ede9fe;
              border-radius:0 0 16px 16px;
              padding:24px 48px;
              text-align:center;
            ">
              <p style="margin:0 0 10px;">
                <a href="https://markaai.com.br" style="color:#7c3aed;text-decoration:none;font-size:12px;font-weight:600;">markaai.com.br</a>
                &nbsp;·&nbsp;
                <a href="https://markaai.com.br/suporte" style="color:#9ca3af;text-decoration:none;font-size:12px;">Suporte</a>
                &nbsp;·&nbsp;
                <a href="https://markaai.com.br/privacidade" style="color:#9ca3af;text-decoration:none;font-size:12px;">Privacidade</a>
              </p>
              <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">
                © 2026 MarkaAI · Email automático, não responda.
              </p>
            </td>
          </tr>

        </table>

      </td>
    </tr>
  </table>

</body>
</html>`

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: email.trim(),
        subject: '🔐 Recuperação de Senha — MarkaAI',
        html: emailHtml,
      }),
    })

    const resendData = await resendRes.json()

    if (!resendRes.ok) {
      console.error('[sendPasswordReset] Resend error:', JSON.stringify(resendData, null, 2))
      return new Response(
        JSON.stringify({ error: 'Falha ao enviar e-mail.', detail: resendData }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('[sendPasswordReset] E-mail enviado com sucesso:', resendData?.id)

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    console.error('[sendPasswordReset] Erro inesperado:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
