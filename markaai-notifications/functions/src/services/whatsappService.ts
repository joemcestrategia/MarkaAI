// ============================================================
//  MarkaAI — WhatsApp Service (Meta Cloud API Oficial)
//  Número central MarkaAI envia para todos os clientes
// ============================================================

import * as functions from "firebase-functions";

// ─── Helpers ─────────────────────────────────────────────────

/**
 * Formata telefone para padrão internacional sem +
 * Ex: "(31) 9 9999-9999" → "5531999999999"
 */
function formatPhone(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  if (digits.startsWith("55") && digits.length >= 12) return digits;
  if (digits.length === 11) return `55${digits}`;
  if (digits.length === 10) return `55${digits}`;
  return digits;
}

/**
 * Função base — envia qualquer template via Meta Cloud API
 */
async function sendWhatsAppTemplate(
  to: string,
  templateName: string,
  components: object[]
): Promise<void> {
  const token = process.env.WHATSAPP_TOKEN;
  const phoneId = process.env.WHATSAPP_PHONE_ID;

  if (!token || !phoneId) {
    throw new Error("WhatsApp credentials not configured. Set WHATSAPP_TOKEN and WHATSAPP_PHONE_ID secrets.");
  }

  const formattedPhone = formatPhone(to);
  const url = `https://graph.facebook.com/v20.0/${phoneId}/messages`;

  const body = {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: formattedPhone,
    type: "template",
    template: {
      name: templateName,
      language: { code: "pt_BR" },
      components,
    },
  };

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const error = await response.json();
    functions.logger.error("WhatsApp API error", {
      phone: formattedPhone,
      template: templateName,
      error,
    });
    throw new Error(`WhatsApp API error: ${JSON.stringify(error)}`);
  }

  functions.logger.info("WhatsApp message sent", {
    phone: formattedPhone,
    template: templateName,
  });
}

// ─── Notificações específicas ─────────────────────────────────

/**
 * Envia confirmação de agendamento
 * Template: markaai_confirmation
 * Variáveis: clientName, salonName, serviceName, date, time, professionalName
 */
export async function sendAppointmentConfirmationWhatsApp(params: {
  clientPhone: string;
  clientName: string;
  salonName: string;
  serviceName: string;
  date: string;
  time: string;
  professionalName: string;
}): Promise<void> {
  try {
    await sendWhatsAppTemplate(
      params.clientPhone,
      "markaai_confirmation",
      [
        {
          type: "body",
          parameters: [
            { type: "text", text: params.clientName },
            { type: "text", text: params.salonName },
            { type: "text", text: params.serviceName },
            { type: "text", text: params.date },
            { type: "text", text: params.time },
            { type: "text", text: params.professionalName },
          ],
        },
      ]
    );
  } catch (err) {
    functions.logger.error("sendAppointmentConfirmationWhatsApp failed", { params, err });
    // Não propaga erro para não quebrar o fluxo principal
  }
}

/**
 * Envia lembrete 24h antes do agendamento
 * Template: markaai_reminder
 * Variáveis: clientName, salonName, serviceName, date, time
 */
export async function sendAppointmentReminderWhatsApp(params: {
  clientPhone: string;
  clientName: string;
  salonName: string;
  serviceName: string;
  date: string;
  time: string;
}): Promise<void> {
  try {
    await sendWhatsAppTemplate(
      params.clientPhone,
      "markaai_reminder",
      [
        {
          type: "body",
          parameters: [
            { type: "text", text: params.clientName },
            { type: "text", text: params.salonName },
            { type: "text", text: params.serviceName },
            { type: "text", text: params.date },
            { type: "text", text: params.time },
          ],
        },
      ]
    );
  } catch (err) {
    functions.logger.error("sendAppointmentReminderWhatsApp failed", { params, err });
  }
}

/**
 * Envia notificação de cancelamento
 * Template: markaai_cancellation
 * Variáveis: clientName, salonName, date, time
 */
export async function sendAppointmentCancellationWhatsApp(params: {
  clientPhone: string;
  clientName: string;
  salonName: string;
  date: string;
  time: string;
}): Promise<void> {
  try {
    await sendWhatsAppTemplate(
      params.clientPhone,
      "markaai_cancellation",
      [
        {
          type: "body",
          parameters: [
            { type: "text", text: params.clientName },
            { type: "text", text: params.salonName },
            { type: "text", text: params.date },
            { type: "text", text: params.time },
          ],
        },
      ]
    );
  } catch (err) {
    functions.logger.error("sendAppointmentCancellationWhatsApp failed", { params, err });
  }
}

/**
 * Envia código OTP para verificação de telefone
 * Template: markaai_otp
 * Variáveis: code
 */
export async function sendOTPWhatsApp(params: {
  clientPhone: string;
  code: string;
}): Promise<void> {
  // OTP: propaga erro pois é crítico para o fluxo de autenticação
  await sendWhatsAppTemplate(
    params.clientPhone,
    "markaai_otp",
    [
      {
        type: "body",
        parameters: [
          { type: "text", text: params.code },
        ],
      },
      {
        type: "button",
        sub_type: "url",
        index: "0",
        parameters: [
          { type: "text", text: params.code },
        ],
      },
    ]
  );
}
