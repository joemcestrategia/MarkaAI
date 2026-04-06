-- pg_cron job: chama appointmentReminders a cada hora
-- Execute este script no SQL Editor do Supabase Dashboard (ou via supabase db push).
-- Certifique-se de que pg_cron e pg_net estão ativados no projeto.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Remove job antigo se existir (idempotente)
select cron.unschedule('edge-appointment-reminders') where exists (
  select 1 from cron.job where jobname = 'edge-appointment-reminders'
);

-- Agenda chamada a cada hora (no :05 para evitar colisão com outros jobs)
select cron.schedule(
  'edge-appointment-reminders',
  '5 * * * *',
  $$
    select net.http_post(
      url     := 'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/appointmentReminders',
      headers := '{"Content-Type": "application/json"}'::jsonb,
      body    := '{}'::jsonb
    );
  $$
);
