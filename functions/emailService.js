const nodemailer = require('nodemailer');
const { defineSecret } = require('firebase-functions/params');

// Define the secret config to be set in Firebase via:
// firebase secrets:set SMTP_PASSWORD
const SMTP_PASSWORD = defineSecret('SMTP_PASSWORD');

/**
 * Retorna uma instância limpa ou reusa o transporter do SMTP
 */
function getTransporter() {
    const pwd = SMTP_PASSWORD.value();

    return nodemailer.createTransport({
        service: 'gmail', // ou 'smtp.hostgator.com.br', dependendo do email
        auth: {
            user: 'suporte@markaai.com.br', // Email do cliente no Firebase
            pass: pwd
        }
    });
}

/**
 * Template Base de HTML (Core do App)
 * @param {string} title 
 * @param {string} contentHtml 
 */
function baseHtmlTemplate(title, contentHtml) {
    return `
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
      <meta charset="utf-8">
      <style>
        body { font-family: 'Helvetica Neue', Arial, sans-serif; background-color: #f7f9fc; margin: 0; padding: 0; color: #333; }
        .container { max-width: 600px; margin: 40px auto; background: #ffffff; border-radius: 12px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
        .header { background-color: #5B2DB6; padding: 30px; text-align: center; color: white; }
        .header h1 { margin: 0; font-size: 24px; font-weight: 600; }
        .content { padding: 40px 30px; line-height: 1.6; }
        .footer { background-color: #f1f5f9; padding: 20px; text-align: center; font-size: 13px; color: #64748b; }
        .btn { display: inline-block; padding: 12px 24px; background-color: #5B2DB6; color: white !important; text-decoration: none; border-radius: 8px; font-weight: bold; margin-top: 20px; }
        .info-box { background: #f8fafc; border: 1px solid #e2e8f0; padding: 20px; border-radius: 8px; margin: 20px 0; }
        .info-row { margin-bottom: 10px; display: flex; }
        .info-label { font-weight: 600; width: 120px; color: #475569; }
        .info-value { color: #0f172a; font-weight: 500;}
      </style>
    </head>
    <body>
      <div class="container">
        <div class="header">
          <h1>${title}</h1>
        </div>
        <div class="content">
          ${contentHtml}
        </div>
        <div class="footer">
          &copy; ${new Date().getFullYear()} MarkaAI. Todos os direitos reservados.<br>
          <a href="https://markaai.com.br" style="color: #5B2DB6; text-decoration: none;">www.markaai.com.br</a>
        </div>
      </div>
    </body>
    </html>
  `;
}

/**
 * Envia um E-mail de Transação Baseado em Status (Novo, Cancelado)
 */
async function sendAppointmentEmail({ toEmail, patientName, shopName, serviceName, dateStr, price, isCancellation = false }) {
    try {
        const transporter = getTransporter();

        let title = isCancellation ? 'Agendamento Cancelado' : 'Agendamento Confirmado!';
        let intro = isCancellation
            ? `Olá, <b>${patientName}</b>. Seu agendamento com <b>${shopName}</b> foi cancelado.`
            : `Olá, <b>${patientName}</b>! Seu agendamento com <b>${shopName}</b> foi confirmado com sucesso.`;

        const content = `
      <p>${intro}</p>
      
      <div class="info-box">
        <div class="info-row">
          <span class="info-label">Serviço:</span>
          <span class="info-value">${serviceName}</span>
        </div>
        <div class="info-row">
          <span class="info-label">Data e Hora:</span>
          <span class="info-value">${dateStr}</span>
        </div>
        ${price ? `
        <div class="info-row">
          <span class="info-label">Valor:</span>
          <span class="info-value">R$ ${parseFloat(price).toFixed(2).replace('.', ',')}</span>
        </div>` : ''}
      </div>

      ${!isCancellation ? `
        <p>Agradecemos a preferência! Se precisar reagendar ou cancelar, acesse o aplicativo.</p>
      ` : `
        <p>Se você não solicitou este cancelamento, por favor entre em contato com o profissional.</p>
      `}
    `;

        const html = baseHtmlTemplate(title, content);

        const info = await transporter.sendMail({
            from: '"MarkaAI Reservas" <suporte@markaai.com.br>',
            to: toEmail,
            subject: `[MarkaAI] ${title} - ${shopName}`,
            html: html,
        });

        console.log(`✅ Email Transacional Enviado para ${toEmail} | MessageID: ${info.messageId}`);
        return true;
    } catch (error) {
        console.error(`❌ Erro ao enviar email SMTP para ${toEmail}:`, error);
        return false;
    }
}

module.exports = {
    sendAppointmentEmail
};
