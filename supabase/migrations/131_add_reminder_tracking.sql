-- Colunas de controle de lembretes (substitui o reminder_sent genérico)
ALTER TABLE "public"."appointments"
ADD COLUMN IF NOT EXISTS "reminder_48h_sent" boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS "reminder_1h_sent" boolean DEFAULT false;

-- Índice para a query de lembretes ser rápida
CREATE INDEX IF NOT EXISTS idx_appointments_reminders
  ON "public"."appointments" (scheduled_at, status, reminder_48h_sent, reminder_1h_sent)
  WHERE status IN ('agendado', 'confirmado');
