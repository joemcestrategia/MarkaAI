// ============================================================
//  MarkaAI — Triggers de Agendamento (Firestore)
//  Dispara notificações automaticamente ao criar/cancelar
// ============================================================

import * as functions from "firebase-functions";
import { Appointment } from "../types";
import {
  sendAppointmentConfirmationWhatsApp,
  sendAppointmentCancellationWhatsApp,
  sendAppointmentReminderWhatsApp,
} from "../services/whatsappService";
import {
  sendAppointmentConfirmationEmail,
  sendAppointmentCancellationEmail,
  sendAppointmentReminderEmail,
} from "../services/emailService";

const SECRETS = ["WHATSAPP_TOKEN", "WHATSAPP_PHONE_ID", "RESEND_API_KEY", "EMAIL_FROM"];

// ─── Criação de agendamento ───────────────────────────────────

export const onAppointmentCreated = functions
  .runWith({ secrets: SECRETS, timeoutSeconds: 30 })
  .firestore.document("appointments/{appointmentId}")
  .onCreate(async (snap, context) => {
    const appointment = snap.data() as Appointment;
    const appointmentId = context.params.appointmentId;

    functions.logger.info("New appointment created", { appointmentId, salonId: appointment.salonId });

    // Validações básicas
    if (!appointment.clientPhone && !appointment.clientEmail) {
      functions.logger.warn("No contact info for appointment", { appointmentId });
      return;
    }

    const notificationParams = {
      clientName: appointment.clientName || "Cliente",
      salonName: appointment.salonName,
      serviceName: appointment.serviceName,
      date: appointment.date,
      time: appointment.time,
      professionalName: appointment.professionalName,
      address: appointment.salonAddress,
    };

    // Envia em paralelo — falha de um não afeta o outro
    const tasks: Promise<void>[] = [];

    if (appointment.clientPhone) {
      tasks.push(
        sendAppointmentConfirmationWhatsApp({
          clientPhone: appointment.clientPhone,
          ...notificationParams,
        })
      );
    }

    if (appointment.clientEmail) {
      tasks.push(
        sendAppointmentConfirmationEmail({
          to: appointment.clientEmail,
          ...notificationParams,
        })
      );
    }

    await Promise.allSettled(tasks);
    functions.logger.info("Confirmation notifications sent", { appointmentId });
  });

// ─── Atualização de agendamento (cancelamento) ────────────────

export const onAppointmentUpdated = functions
  .runWith({ secrets: SECRETS, timeoutSeconds: 30 })
  .firestore.document("appointments/{appointmentId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data() as Appointment;
    const after = change.after.data() as Appointment;
    const appointmentId = context.params.appointmentId;

    // Só age se o status mudou para "cancelled"
    if (before.status === after.status) return;
    if (after.status !== "cancelled") return;

    functions.logger.info("Appointment cancelled", { appointmentId });

    const cancellationParams = {
      clientName: after.clientName || "Cliente",
      salonName: after.salonName,
      date: after.date,
      time: after.time,
    };

    const tasks: Promise<void>[] = [];

    if (after.clientPhone) {
      tasks.push(
        sendAppointmentCancellationWhatsApp({
          clientPhone: after.clientPhone,
          ...cancellationParams,
        })
      );
    }

    if (after.clientEmail) {
      tasks.push(
        sendAppointmentCancellationEmail({
          to: after.clientEmail,
          ...cancellationParams,
        })
      );
    }

    await Promise.allSettled(tasks);
    functions.logger.info("Cancellation notifications sent", { appointmentId });
  });

// ─── Lembrete manual (callable) ──────────────────────────────
// Pode ser chamada por um Cloud Scheduler ou manualmente

export const sendReminderManual = functions
  .runWith({ secrets: SECRETS, timeoutSeconds: 30 })
  .https.onCall(async (data: { appointmentId: string }, context) => {
    // Verifica autenticação básica (admin)
    if (!context.auth) {
      throw new functions.https.HttpsError("unauthenticated", "Autenticação necessária.");
    }

    const { appointmentId } = data;
    if (!appointmentId) {
      throw new functions.https.HttpsError("invalid-argument", "appointmentId é obrigatório.");
    }

    const { getFirestore } = await import("firebase-admin/firestore");
    const db = getFirestore();
    const doc = await db.collection("appointments").doc(appointmentId).get();

    if (!doc.exists) {
      throw new functions.https.HttpsError("not-found", "Agendamento não encontrado.");
    }

    const appointment = doc.data() as Appointment;

    const reminderParams = {
      clientName: appointment.clientName || "Cliente",
      salonName: appointment.salonName,
      serviceName: appointment.serviceName,
      date: appointment.date,
      time: appointment.time,
    };

    const tasks: Promise<void>[] = [];

    if (appointment.clientPhone) {
      tasks.push(sendAppointmentReminderWhatsApp({ clientPhone: appointment.clientPhone, ...reminderParams }));
    }

    if (appointment.clientEmail) {
      tasks.push(sendAppointmentReminderEmail({ to: appointment.clientEmail, ...reminderParams }));
    }

    await Promise.allSettled(tasks);

    return { success: true, appointmentId };
  });
