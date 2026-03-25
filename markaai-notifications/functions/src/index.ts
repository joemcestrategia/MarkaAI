// ============================================================
//  MarkaAI — index.ts
//  Exporta todas as Cloud Functions de notificação
// ============================================================

import * as admin from "firebase-admin";

// Inicializa Firebase Admin (só uma vez)
if (!admin.apps.length) {
  admin.initializeApp();
}

// ─── Triggers de Agendamento ──────────────────────────────────
export {
  onAppointmentCreated,
  onAppointmentUpdated,
  sendReminderManual,
} from "./notifications/appointmentTriggers";

// ─── OTP ──────────────────────────────────────────────────────
export {
  sendOTPCode,
  sendOTPByEmail,
  verifyOTPCode,
} from "./notifications/otpFunctions";
