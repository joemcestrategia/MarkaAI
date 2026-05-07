-- ══════════════════════════════════════════════════════════════════
-- Migration 161: WhatsApp Reminder — Meta Cloud API (Full Setup)
-- ══════════════════════════════════════════════════════════════════

-- 1. Garantir coluna reminder_sent na tabela appointments (idempotente)
ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT false;

-- 2. Tabela de log de erros de envio WhatsApp
CREATE TABLE IF NOT EXISTS public.whatsapp_send_errors (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  appointment_id  text, -- text para compatibilidade com appointments.id (tipo text no schema)
  shop_id         text,
  error_code      text,
  raw_response    jsonb,
  attempt_number  int DEFAULT 1,
  created_at      timestamptz DEFAULT now()
);

-- RLS: apenas o dono da loja pode ler seus erros
ALTER TABLE public.whatsapp_send_errors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "owner_read_errors" ON public.whatsapp_send_errors;
CREATE POLICY "owner_read_errors" ON public.whatsapp_send_errors
  FOR SELECT USING (
    shop_id IN (
      SELECT shop_id::text FROM public.users WHERE id = auth.uid()
    ) OR shop_id = auth.uid()::text
  );

-- 3. Índice para o job de lembretes (busca eficiente)
CREATE INDEX IF NOT EXISTS idx_appointments_reminder_job
  ON public.appointments (scheduled_at, status, reminder_sent)
  WHERE reminder_sent = false;

-- 4. Preencher automaticamente wa_template_reminder_name para lojas existentes
--    (o template aprovado no Meta for Devs chama-se "markaai_reminder")
UPDATE public.shop_whatsapp_config
  SET wa_template_reminder_name = 'markaai_reminder'
  WHERE wa_template_reminder_name IS NULL
     OR wa_template_reminder_name = '';
