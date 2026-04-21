import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'

/**
 * Edge Function: contact-landing
 *
 * Recebe o POST do formulário de contato anônimo da landing page
 * e envia um e-mail de notificação via Resend para a equipe MarkaAI.
 *
 * Body: { nome: string, email: string, assunto: string, mensagem: string }
 * NÃO grava nada no banco (sem autenticação exigida).
 */

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

serve(async (req) => {
  // Preflight CORS
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response(
      JSON.stringify({ error: 'Método não permitido.' }),
      { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }

  try {
    const body = await req.json()
    const { nome, email, telefone, assunto, mensagem } = body

    // ─── Validação dos campos obrigatórios ───────────────────────────────────
    if (!nome || typeof nome !== 'string' || nome.trim().length < 2) {
      return new Response(
        JSON.stringify({ error: 'Campo "nome" é obrigatório e deve ter ao menos 2 caracteres.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!email || !email.includes('@')) {
      return new Response(
        JSON.stringify({ error: 'Campo "email" inválido.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (telefone && (typeof telefone !== 'string' || telefone.trim().length < 8)) {
      return new Response(
        JSON.stringify({ error: 'Campo "telefone" inválido.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!assunto || typeof assunto !== 'string' || assunto.trim().length === 0) {
      return new Response(
        JSON.stringify({ error: 'Campo "assunto" é obrigatório.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (!mensagem || typeof mensagem !== 'string' || mensagem.trim().length < 10) {
      return new Response(
        JSON.stringify({ error: 'Campo "mensagem" é obrigatório e deve ter ao menos 10 caracteres.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    if (mensagem.trim().length > 1000) {
      return new Response(
        JSON.stringify({ error: 'Mensagem excede o limite de 1000 caracteres.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // ─── Envio via Resend ────────────────────────────────────────────────────
    const resendApiKey = Deno.env.get('RESEND_API_KEY') || 're_Qy2C15mJ_9uFX99gZB3HfYfbC15mUfw1R'
    if (!resendApiKey) {
      console.error('[contact-landing] RESEND_API_KEY não configurada.')
      return new Response(
        JSON.stringify({ error: 'Configuração de e-mail ausente.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // FALLBACK DE REMETENTE: Resend exige domínio verificado. 
    // Se o domínio markaai.com.br não estiver verificado no Resend, o envio falhará.
    // Você pode usar 'onboarding@resend.dev' para testes se necessário.
    const from = Deno.env.get('EMAIL_FROM') || 'MarkaAI <no-reply@markaai.com.br>'
    
    // FIX: Forçando o e-mail correto solicitado pelo usuário
    const toEmail = 'contato.markaai@gmail.com'

    const emailHtml = `
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Novo contato via Landing Page - MarkaAI</title>
</head>
<body style="margin:0;padding:0;background:#F5F7FA;font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F5F7FA;padding:32px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" style="background:#FFFFFF;border-radius:12px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">
          <!-- Header -->
          <tr>
            <td style="background:linear-gradient(135deg,#2D264B 0%,#6A1B9A 100%);padding:28px 40px;text-align:center;">
              <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="140" style="display:block;margin:0 auto;max-height:42px;object-fit:contain;"/>
              <p style="color:#FFD700;font-size:13px;margin:12px 0 0;letter-spacing:0.5px;">NOVO CONTATO — LANDING PAGE</p>
            </td>
          </tr>
          <!-- Body -->
          <tr>
            <td style="padding:40px;">
              <h2 style="margin:0 0 24px;color:#2D264B;font-size:22px;">[Contato Landing] ${assunto} — ${nome}</h2>
              <table width="100%" cellpadding="0" cellspacing="0">
                <tr>
                  <td style="padding:12px 16px;background:#F5F7FA;border-radius:8px;margin-bottom:8px;">
                    <p style="margin:0;font-size:12px;color:#666;text-transform:uppercase;letter-spacing:0.5px;">Nome</p>
                    <p style="margin:4px 0 0;font-size:16px;color:#2D264B;font-weight:600;">${nome.trim()}</p>
                  </td>
                </tr>
                <tr><td style="height:8px;"></td></tr>
                <tr>
                  <td style="padding:12px 16px;background:#F5F7FA;border-radius:8px;">
                    <p style="margin:0;font-size:12px;color:#666;text-transform:uppercase;letter-spacing:0.5px;">E-mail</p>
                    <p style="margin:4px 0 0;font-size:16px;color:#6A1B9A;font-weight:600;">
                      <a href="mailto:${email.trim()}" style="color:#6A1B9A;text-decoration:none;">${email.trim()}</a>
                    </p>
                  </td>
                </tr>
                <tr><td style="height:8px;"></td></tr>
                <tr>
                  <td style="padding:12px 16px;background:#F5F7FA;border-radius:8px;">
                    <p style="margin:0;font-size:12px;color:#666;text-transform:uppercase;letter-spacing:0.5px;">WhatsApp / Telefone</p>
                    <p style="margin:4px 0 0;font-size:16px;color:#2D264B;font-weight:600;">${telefone ? telefone.trim() : 'Não informado'}</p>
                  </td>
                </tr>
                <tr><td style="height:8px;"></td></tr>
                <tr>
                  <td style="padding:12px 16px;background:#F5F7FA;border-radius:8px;">
                    <p style="margin:0;font-size:12px;color:#666;text-transform:uppercase;letter-spacing:0.5px;">Assunto</p>
                    <p style="margin:4px 0 0;font-size:16px;color:#2D264B;font-weight:600;">${assunto.trim()}</p>
                  </td>
                </tr>
                <tr><td style="height:16px;"></td></tr>
                <tr>
                  <td style="padding:20px;background:#2D264B;border-radius:8px;">
                    <p style="margin:0 0 8px;font-size:12px;color:#FFD700;text-transform:uppercase;letter-spacing:0.5px;">Mensagem</p>
                    <p style="margin:0;font-size:15px;color:#FFFFFF;line-height:1.7;white-space:pre-wrap;">${mensagem.trim()}</p>
                  </td>
                </tr>
              </table>
              <div style="margin-top:32px;padding:16px;border-top:1px solid #E0E0E0;text-align:center;">
                <a href="mailto:${email.trim()}?subject=Re:%20${encodeURIComponent(assunto.trim())}" style="display:inline-block;padding:12px 28px;background:#6A1B9A;color:#FFFFFF;border-radius:8px;text-decoration:none;font-weight:600;font-size:14px;">
                  Responder para ${nome.trim()}
                </a>
              </div>
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px;background:#F5F7FA;text-align:center;border-top:1px solid #E0E0E0;">
              <p style="margin:0;font-size:12px;color:#999;">MarkaAI — Sistema de gestão para salões e estética</p>
              <p style="margin:4px 0 0;font-size:12px;color:#bbb;">Este e-mail foi gerado automaticamente pela landing page.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
`

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: [toEmail],
        reply_to: email.trim(),
        subject: `[Contato Landing] ${assunto.trim()} - ${nome.trim()}`,
        html: emailHtml,
      }),
    })

    const resendData = await resendRes.json()

    if (!resendRes.ok) {
      console.error('[contact-landing] Resend error:', JSON.stringify(resendData, null, 2))
      return new Response(
        JSON.stringify({ error: 'Falha ao enviar e-mail.' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    console.log('[contact-landing] E-mail enviado com sucesso. ID:', resendData?.id)

    return new Response(
      JSON.stringify({ success: true }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (err) {
    console.error('[contact-landing] Erro inesperado:', err)
    return new Response(
      JSON.stringify({ error: err.message || 'Erro interno.' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
