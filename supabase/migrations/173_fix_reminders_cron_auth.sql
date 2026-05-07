-- Fix: recria o job de lembretes com header de autenticação correto
-- Sem o header apikey, as Edge Functions retornam 401 silenciosamente.

-- Remove job antigo (todas as variações de nome)
SELECT cron.unschedule('edge-appointment-reminders')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'edge-appointment-reminders');

-- Recria com apikey no header (anon key do projeto)
SELECT cron.schedule(
  'edge-appointment-reminders',
  '5 * * * *',
  $$
    SELECT net.http_post(
      url     := 'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/appointmentReminders',
      headers := '{"Content-Type": "application/json", "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA"}'::jsonb,
      body    := '{}'::jsonb
    );
  $$
);

-- Verificar se foi criado corretamente:
-- SELECT jobid, jobname, schedule, command FROM cron.job WHERE jobname = 'edge-appointment-reminders';
