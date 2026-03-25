// ============================================================
//  MarkaAI — Templates HTML de Email
//  Design responsivo, inline CSS, compatível Gmail/Outlook
// ============================================================

const PRIMARY = "#6C63FF";
const PRIMARY_DARK = "#574FD6";
const BG = "#F8F8FF";
const TEXT = "#333333";
const LIGHT_TEXT = "#666666";

function baseLayout(content: string, preheader = ""): string {
  return `
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>MarkaAI</title>
  ${preheader ? `<span style="display:none;max-height:0;overflow:hidden;">${preheader}</span>` : ""}
</head>
<body style="margin:0;padding:0;background-color:${BG};font-family:Arial,sans-serif;color:${TEXT};">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:${BG};padding:24px 0;">
    <tr>
      <td align="center">
        <table width="600" cellpadding="0" cellspacing="0" border="0"
          style="max-width:600px;width:100%;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 2px 12px rgba(0,0,0,0.08);">

          <!-- HEADER -->
          <tr>
            <td style="background:${PRIMARY};padding:28px 40px;text-align:center;">
              <h1 style="margin:0;color:#ffffff;font-size:26px;font-weight:bold;letter-spacing:1px;">
                ✂️ MarkaAI
              </h1>
              <p style="margin:6px 0 0;color:rgba(255,255,255,0.85);font-size:13px;">
                Agendamentos inteligentes para profissionais de beleza
              </p>
            </td>
          </tr>

          <!-- CONTENT -->
          <tr>
            <td style="padding:36px 40px;">
              ${content}
            </td>
          </tr>

          <!-- FOOTER -->
          <tr>
            <td style="background:#F0EFF9;padding:20px 40px;text-align:center;border-top:1px solid #E8E8E8;">
              <p style="margin:0;color:${LIGHT_TEXT};font-size:12px;line-height:1.6;">
                Enviado por <strong style="color:${PRIMARY};">MarkaAI</strong> •
                <a href="https://markaai.com.br" style="color:${PRIMARY};text-decoration:none;">markaai.com.br</a>
              </p>
              <p style="margin:8px 0 0;color:#999999;font-size:11px;">
                Este é um email automático, por favor não responda.
              </p>
            </td>
          </tr>

        </table>
      </td>
    </tr>
  </table>
</body>
</html>`.trim();
}

function infoRow(label: string, value: string): string {
  return `
  <tr>
    <td style="padding:8px 0;border-bottom:1px solid #F0EFF9;">
      <table width="100%" cellpadding="0" cellspacing="0">
        <tr>
          <td style="color:${LIGHT_TEXT};font-size:13px;width:40%;">${label}</td>
          <td style="color:${TEXT};font-size:13px;font-weight:bold;">${value}</td>
        </tr>
      </table>
    </td>
  </tr>`;
}

// ─── Template: Confirmação ────────────────────────────────────

export function confirmationEmailHtml(params: {
  clientName: string;
  salonName: string;
  serviceName: string;
  date: string;
  time: string;
  professionalName: string;
  address?: string;
}): string {
  const content = `
    <h2 style="margin:0 0 8px;color:${PRIMARY};font-size:22px;">Agendamento Confirmado! 🎉</h2>
    <p style="margin:0 0 24px;color:${LIGHT_TEXT};font-size:15px;">
      Olá, <strong>${params.clientName}</strong>! Seu agendamento foi confirmado com sucesso.
    </p>

    <div style="background:${BG};border-radius:8px;padding:20px;margin-bottom:24px;">
      <table width="100%" cellpadding="0" cellspacing="0">
        ${infoRow("📍 Salão", params.salonName)}
        ${infoRow("✂️ Serviço", params.serviceName)}
        ${infoRow("👤 Profissional", params.professionalName)}
        ${infoRow("📅 Data", params.date)}
        ${infoRow("🕐 Horário", params.time)}
        ${params.address ? infoRow("🗺️ Endereço", params.address) : ""}
      </table>
    </div>

    <div style="background:#E8F5E9;border-left:4px solid #4CAF50;border-radius:4px;padding:14px 18px;margin-bottom:24px;">
      <p style="margin:0;color:#2E7D32;font-size:14px;">
        ✅ Lembre-se de chegar com alguns minutos de antecedência.
      </p>
    </div>

    <p style="margin:0;color:${LIGHT_TEXT};font-size:13px;line-height:1.6;">
      Caso precise cancelar ou reagendar, acesse o aplicativo MarkaAI com antecedência mínima de 2 horas.
    </p>
  `;
  return baseLayout(content, `Seu agendamento no ${params.salonName} está confirmado para ${params.date} às ${params.time}.`);
}

// ─── Template: Lembrete ───────────────────────────────────────

export function reminderEmailHtml(params: {
  clientName: string;
  salonName: string;
  serviceName: string;
  date: string;
  time: string;
}): string {
  const content = `
    <h2 style="margin:0 0 8px;color:${PRIMARY};font-size:22px;">Lembrete de Agendamento ⏰</h2>
    <p style="margin:0 0 24px;color:${LIGHT_TEXT};font-size:15px;">
      Olá, <strong>${params.clientName}</strong>! Seu agendamento é <strong>amanhã</strong>.
    </p>

    <div style="background:${BG};border-radius:8px;padding:20px;margin-bottom:24px;">
      <table width="100%" cellpadding="0" cellspacing="0">
        ${infoRow("📍 Salão", params.salonName)}
        ${infoRow("✂️ Serviço", params.serviceName)}
        ${infoRow("📅 Data", params.date)}
        ${infoRow("🕐 Horário", params.time)}
      </table>
    </div>

    <div style="background:#FFF8E1;border-left:4px solid #FFC107;border-radius:4px;padding:14px 18px;margin-bottom:24px;">
      <p style="margin:0;color:#F57F17;font-size:14px;">
        ⚠️ Precisa cancelar? Faça isso com pelo menos 2 horas de antecedência pelo app.
      </p>
    </div>

    <p style="margin:0;color:${LIGHT_TEXT};font-size:13px;">
      Te esperamos amanhã! 🌟
    </p>
  `;
  return baseLayout(content, `Lembrete: seu agendamento no ${params.salonName} é amanhã às ${params.time}.`);
}

// ─── Template: Cancelamento ───────────────────────────────────

export function cancellationEmailHtml(params: {
  clientName: string;
  salonName: string;
  date: string;
  time: string;
}): string {
  const content = `
    <h2 style="margin:0 0 8px;color:#E53935;font-size:22px;">Agendamento Cancelado</h2>
    <p style="margin:0 0 24px;color:${LIGHT_TEXT};font-size:15px;">
      Olá, <strong>${params.clientName}</strong>. Seu agendamento foi cancelado.
    </p>

    <div style="background:#FFEBEE;border-radius:8px;padding:20px;margin-bottom:24px;">
      <table width="100%" cellpadding="0" cellspacing="0">
        ${infoRow("📍 Salão", params.salonName)}
        ${infoRow("📅 Data cancelada", params.date)}
        ${infoRow("🕐 Horário", params.time)}
      </table>
    </div>

    <div style="text-align:center;margin:28px 0;">
      <a href="https://markaai.com.br"
        style="display:inline-block;background:${PRIMARY};color:#ffffff;text-decoration:none;
               padding:14px 32px;border-radius:8px;font-size:15px;font-weight:bold;">
        Reagendar pelo App
      </a>
    </div>

    <p style="margin:0;color:${LIGHT_TEXT};font-size:13px;line-height:1.6;">
      Sentimos muito pelo inconveniente. Esperamos te ver em breve! 💜
    </p>
  `;
  return baseLayout(content, `Seu agendamento no ${params.salonName} do dia ${params.date} foi cancelado.`);
}

// ─── Template: Boas-vindas ────────────────────────────────────

export function welcomeEmailHtml(params: {
  clientName: string;
}): string {
  const content = `
    <h2 style="margin:0 0 8px;color:${PRIMARY};font-size:22px;">Bem-vindo ao MarkaAI! 💜</h2>
    <p style="margin:0 0 24px;color:${LIGHT_TEXT};font-size:15px;">
      Olá, <strong>${params.clientName}</strong>! Sua conta foi criada com sucesso.
    </p>

    <div style="background:${BG};border-radius:8px;padding:24px;margin-bottom:24px;text-align:center;">
      <p style="margin:0 0 8px;font-size:36px;">✂️</p>
      <p style="margin:0;color:${TEXT};font-size:15px;line-height:1.6;">
        Agora você pode agendar serviços nos melhores salões e barbearias da sua região,
        direto pelo app, a qualquer hora.
      </p>
    </div>

    <div style="text-align:center;margin:28px 0;">
      <a href="https://markaai.com.br"
        style="display:inline-block;background:${PRIMARY};color:#ffffff;text-decoration:none;
               padding:14px 32px;border-radius:8px;font-size:15px;font-weight:bold;">
        Começar a usar o MarkaAI
      </a>
    </div>

    <p style="margin:0;color:${LIGHT_TEXT};font-size:13px;line-height:1.6;">
      Qualquer dúvida, entre em contato pelo app ou pelo site.
    </p>
  `;
  return baseLayout(content, `Bem-vindo ao MarkaAI, ${params.clientName}! Sua conta está pronta.`);
}

// ─── Template: OTP por email (fallback) ──────────────────────

export function otpEmailHtml(params: {
  clientName: string;
  code: string;
}): string {
  const content = `
    <h2 style="margin:0 0 8px;color:${PRIMARY};font-size:22px;">Seu código de verificação</h2>
    <p style="margin:0 0 24px;color:${LIGHT_TEXT};font-size:15px;">
      Olá, <strong>${params.clientName}</strong>! Use o código abaixo para verificar sua conta.
    </p>

    <div style="text-align:center;margin:32px 0;">
      <div style="display:inline-block;background:${BG};border:2px dashed ${PRIMARY};
                  border-radius:12px;padding:20px 48px;">
        <span style="font-size:40px;font-weight:bold;letter-spacing:12px;color:${PRIMARY_DARK};">
          ${params.code}
        </span>
      </div>
    </div>

    <div style="background:#FFF3E0;border-left:4px solid #FF9800;border-radius:4px;padding:14px 18px;margin-bottom:24px;">
      <p style="margin:0;color:#E65100;font-size:14px;">
        ⏱️ Este código expira em <strong>10 minutos</strong>. Não compartilhe com ninguém.
      </p>
    </div>

    <p style="margin:0;color:${LIGHT_TEXT};font-size:13px;">
      Se você não solicitou este código, ignore este email.
    </p>
  `;
  return baseLayout(content, `Seu código MarkaAI: ${params.code} — Válido por 10 minutos.`);
}
