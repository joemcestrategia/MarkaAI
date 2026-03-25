// ============================================================
//  MarkaAI — Email Service (Resend)
//  Domínio central MarkaAI envia para todos os clientes
// ============================================================

import * as functions from "firebase-functions";
import { Resend } from "resend";
import {
  confirmationEmailHtml,
  reminderEmailHtml,
  cancellationEmailHtml,
  welcomeEmailHtml,
  otpEmailHtml,
} from "../templates/emailTemplates";

// ─── Função base ──────────────────────────────────────────────

async function sendEmail(params: {
  to: string;
  subject: string;
  html: string;
}): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.EMAIL_FROM || "noreply@markaai.com.br";

  if (!apiKey) {
    throw new Error("Resend credentials not configured. Set RESEND_API_KEY secret.");
  }

  const resend = new Resend(apiKey);

  const { error } = await resend.emails.send({
    from: `MarkaAI <${from}>`,
    to: params.to,
    subject: params.subject,
    html: params.html,
  });

  if (error) {
    functions.logger.error("Resend error", { to: params.to, subject: params.subject, error });
    throw new Error(`Resend error: ${JSON.stringify(error)}`);
  }

  functions.logger.info("Email sent", { to: params.to, subject: params.subject });
}

// ─── Notificações específicas ─────────────────────────────────

export async function sendAppointmentConfirmationEmail(params: {
  to: string;
  clientName: string;
  salonName: string;
  serviceName: string;
  date: string;
  time: string;
  professionalName: string;
  address?: string;
}): Promise<void> {
  try {
    await sendEmail({
      to: params.to,
      subject: `✅ Agendamento confirmado — ${params.salonName} · ${params.date}`,
      html: confirmationEmailHtml(params),
    });
  } catch (err) {
    functions.logger.error("sendAppointmentConfirmationEmail failed", { params, err });
  }
}

export async function sendAppointmentReminderEmail(params: {
  to: string;
  clientName: string;
  salonName: string;
  serviceName: string;
  date: string;
  time: string;
}): Promise<void> {
  try {
    await sendEmail({
      to: params.to,
      subject: `⏰ Lembrete: seu agendamento é amanhã — ${params.salonName}`,
      html: reminderEmailHtml(params),
    });
  } catch (err) {
    functions.logger.error("sendAppointmentReminderEmail failed", { params, err });
  }
}

export async function sendAppointmentCancellationEmail(params: {
  to: string;
  clientName: string;
  salonName: string;
  date: string;
  time: string;
}): Promise<void> {
  try {
    await sendEmail({
      to: params.to,
      subject: `❌ Agendamento cancelado — ${params.salonName} · ${params.date}`,
      html: cancellationEmailHtml(params),
    });
  } catch (err) {
    functions.logger.error("sendAppointmentCancellationEmail failed", { params, err });
  }
}

export async function sendWelcomeEmail(params: {
  to: string;
  clientName: string;
}): Promise<void> {
  try {
    await sendEmail({
      to: params.to,
      subject: "💜 Bem-vindo ao MarkaAI!",
      html: welcomeEmailHtml(params),
    });
  } catch (err) {
    functions.logger.error("sendWelcomeEmail failed", { params, err });
  }
}

export async function sendOTPEmail(params: {
  to: string;
  clientName: string;
  code: string;
}): Promise<void> {
  // OTP: propaga erro pois é crítico para autenticação
  await sendEmail({
    to: params.to,
    subject: `🔐 Seu código de verificação MarkaAI: ${params.code}`,
    html: otpEmailHtml(params),
  });
}
