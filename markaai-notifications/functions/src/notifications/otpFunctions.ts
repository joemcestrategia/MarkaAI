// ============================================================
//  MarkaAI — OTP Functions (verificação de telefone/email)
// ============================================================

import * as functions from "firebase-functions";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { OTPDocument, SendOTPRequest, VerifyOTPRequest } from "../types";
import { sendOTPWhatsApp } from "../services/whatsappService";
import { sendOTPEmail } from "../services/emailService";

const SECRETS = ["WHATSAPP_TOKEN", "WHATSAPP_PHONE_ID", "RESEND_API_KEY", "EMAIL_FROM"];
const OTP_EXPIRY_MINUTES = 10;
const MAX_ATTEMPTS = 5;

// ─── Gera código OTP aleatório ────────────────────────────────

function generateOTPCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// ─── Envia OTP por WhatsApp ───────────────────────────────────

export const sendOTPCode = functions
  .runWith({ secrets: SECRETS, timeoutSeconds: 30 })
  .https.onCall(async (data: SendOTPRequest) => {
    const { phone } = data;

    if (!phone) {
      throw new functions.https.HttpsError("invalid-argument", "Telefone é obrigatório.");
    }

    // Remove caracteres não numéricos
    const cleanPhone = phone.replace(/\D/g, "");
    if (cleanPhone.length < 10) {
      throw new functions.https.HttpsError("invalid-argument", "Telefone inválido.");
    }

    const code = generateOTPCode();
    const db = getFirestore();
    const expiresAt = Timestamp.fromDate(
      new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000)
    );

    // Salva OTP no Firestore
    const otpData: OTPDocument = {
      code,
      phone: cleanPhone,
      expiresAt,
      verified: false,
      createdAt: Timestamp.now(),
    };

    await db.collection("otpCodes").doc(cleanPhone).set(otpData);

    // Envia via WhatsApp
    try {
      await sendOTPWhatsApp({ clientPhone: cleanPhone, code });
    } catch (err) {
      functions.logger.error("Failed to send OTP WhatsApp", { phone: cleanPhone, err });
      throw new functions.https.HttpsError("internal", "Falha ao enviar código. Tente novamente.");
    }

    functions.logger.info("OTP sent", { phone: cleanPhone });
    return { success: true, message: "Código enviado com sucesso." };
  });

// ─── Envia OTP por Email (alternativo) ───────────────────────

export const sendOTPByEmail = functions
  .runWith({ secrets: SECRETS, timeoutSeconds: 30 })
  .https.onCall(async (data: { email: string; clientName: string }) => {
    const { email, clientName } = data;

    if (!email) {
      throw new functions.https.HttpsError("invalid-argument", "Email é obrigatório.");
    }

    const code = generateOTPCode();
    const db = getFirestore();
    const expiresAt = Timestamp.fromDate(
      new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000)
    );

    const otpData: OTPDocument = {
      code,
      phone: email, // reutiliza o campo como chave
      expiresAt,
      verified: false,
      createdAt: Timestamp.now(),
    };

    await db.collection("otpCodes").doc(email.replace(/[@.]/g, "_")).set(otpData);

    try {
      await sendOTPEmail({ to: email, clientName: clientName || "Cliente", code });
    } catch (err) {
      functions.logger.error("Failed to send OTP email", { email, err });
      throw new functions.https.HttpsError("internal", "Falha ao enviar código. Tente novamente.");
    }

    functions.logger.info("OTP email sent", { email });
    return { success: true, message: "Código enviado para seu email." };
  });

// ─── Verifica OTP ─────────────────────────────────────────────

export const verifyOTPCode = functions
  .runWith({ secrets: SECRETS, timeoutSeconds: 15 })
  .https.onCall(async (data: VerifyOTPRequest) => {
    const { phone, code } = data;

    if (!phone || !code) {
      throw new functions.https.HttpsError("invalid-argument", "Telefone e código são obrigatórios.");
    }

    const cleanPhone = phone.replace(/\D/g, "");
    const db = getFirestore();
    const docRef = db.collection("otpCodes").doc(cleanPhone);
    const doc = await docRef.get();

    if (!doc.exists) {
      throw new functions.https.HttpsError("not-found", "Código não encontrado. Solicite um novo.");
    }

    const otpData = doc.data() as OTPDocument;

    // Verifica expiração
    if (otpData.expiresAt.toDate() < new Date()) {
      await docRef.delete();
      throw new functions.https.HttpsError("deadline-exceeded", "Código expirado. Solicite um novo.");
    }

    // Verifica se já foi usado
    if (otpData.verified) {
      throw new functions.https.HttpsError("already-exists", "Código já utilizado.");
    }

    // Verifica o código
    if (otpData.code !== code.trim()) {
      throw new functions.https.HttpsError("unauthenticated", "Código incorreto.");
    }

    // Marca como verificado
    await docRef.update({ verified: true, verifiedAt: FieldValue.serverTimestamp() });

    functions.logger.info("OTP verified successfully", { phone: cleanPhone });
    return { success: true, message: "Telefone verificado com sucesso." };
  });
