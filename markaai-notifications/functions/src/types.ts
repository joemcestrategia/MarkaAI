// ============================================================
//  MarkaAI — Tipos compartilhados do sistema de notificações
// ============================================================

export interface Appointment {
  id?: string;
  clientName: string;
  clientPhone: string;       // formato: "5531999999999"
  clientEmail: string;
  salonId: string;
  salonName: string;
  salonAddress?: string;
  professionalName: string;
  serviceName: string;
  date: string;              // "18/03/2025"
  time: string;              // "14:30"
  status: "pending" | "confirmed" | "cancelled" | "completed";
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
}

export interface NotificationResult {
  success: boolean;
  channel: "whatsapp" | "email";
  error?: string;
}

export interface OTPDocument {
  code: string;
  phone: string;
  expiresAt: FirebaseFirestore.Timestamp;
  verified: boolean;
  createdAt: FirebaseFirestore.Timestamp;
}

export interface SendOTPRequest {
  phone: string;
}

export interface VerifyOTPRequest {
  phone: string;
  code: string;
}
