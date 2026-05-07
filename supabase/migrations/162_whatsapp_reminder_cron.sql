-- ══════════════════════════════════════════════════════════════════
-- Migration 162: pg_cron — Job de Lembrete WhatsApp a cada 15 min
-- ══════════════════════════════════════════════════════════════════
-- ATENÇÃO: Execute este script no SQL Editor do Supabase Dashboard.
-- Requer pg_cron e pg_net habilitados no projeto.

-- Habilitar extensões (idempotente)
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remover jobs legados se existirem (idempotente)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'appointment-reminders') THEN
    PERFORM cron.unschedule('appointment-reminders');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'edge-appointment-reminders') THEN
    PERFORM cron.unschedule('edge-appointment-reminders');
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'whatsapp-reminder-job') THEN
    PERFORM cron.unschedule('whatsapp-reminder-job');
  END IF;
END $$;

-- Criar job a cada 15 minutos
SELECT cron.schedule(
  'whatsapp-reminder-job',
  '*/15 * * * *',
  $$
    SELECT net.http_post(
      url     := 'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/send-appointment-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
      ),
      body    := '{}'::jsonb
    );
  $$
);

-- Verificar criação
SELECT jobid, jobname, schedule, active
FROM cron.job
WHERE jobname = 'whatsapp-reminder-job';

-- ─────────────────────────────────────────────────────────────
-- Se app.settings.service_role_key não estiver configurado,
-- execute antes no SQL Editor:
--
-- ALTER DATABASE postgres
--   SET "app.settings.service_role_key" = '<sua_service_role_key>';
-- ─────────────────────────────────────────────────────────────
