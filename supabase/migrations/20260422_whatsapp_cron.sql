-- Migração: Agendamento do pg_cron para lembretes automáticos de WhatsApp
-- Executa a Edge Function send-appointment-reminders a cada hora

-- PASSO 1: Habilitar extensão pg_cron (se ainda não estiver ativa)
-- Nota: Em projetos Supabase, execute este passo no SQL Editor do Dashboard
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- CREATE EXTENSION IF NOT EXISTS pg_net;

-- PASSO 2: Remover agendamento existente (idempotente)
SELECT cron.unschedule('appointment-reminders')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'appointment-reminders'
);

-- PASSO 3: Criar agendamento horário
SELECT cron.schedule(
  'appointment-reminders',
  '0 * * * *',  -- A cada hora exata
  $$
  SELECT net.http_post(
    url := current_setting('app.settings.supabase_url') || '/functions/v1/send-appointment-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
    ),
    body := '{}'::jsonb
  );
  $$
);

-- PASSO 4: Verificar que o cron foi criado
SELECT jobid, jobname, schedule, active
FROM cron.job
WHERE jobname = 'appointment-reminders';

-- ─────────────────────────────────────────────────────────────
-- ALTERNATIVA: Definir as variáveis de configuração se não existirem
-- Execute primeiro no SQL Editor:
-- ─────────────────────────────────────────────────────────────
--
-- ALTER DATABASE postgres SET "app.settings.supabase_url" = 'https://uhccgcojwqvkfyzrmebv.supabase.co';
-- ALTER DATABASE postgres SET "app.settings.service_role_key" = '<sua_service_role_key>';
--
-- Depois execute o SELECT cron.schedule acima.
