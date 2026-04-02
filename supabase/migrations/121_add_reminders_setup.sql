-- Cria a coluna reminder_sent para evitar envio repetido de lembretes
ALTER TABLE "public"."appointments" 
ADD COLUMN IF NOT EXISTS "reminder_sent" boolean DEFAULT false;

-- Certifique-se de que a extensão pg_cron e pg_net estão ativadas
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Pega o URL base de alguma function existente (o ID é dinâmico mas o hostname geralmente é o mesmo do projeto)
-- Aqui configuramos como agendamento a cada hora.
-- O endpoint vai para /appointmentReminders
SELECT cron.schedule(
  'edge-appointment-reminders', -- job name
  '0 * * * *',                  -- cron schedule (toda hora)
  $$
    SELECT net.http_post(
      url:='https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/appointmentReminders',
      headers:='{"Content-Type": "application/json", "Authorization": "Bearer SUA_SERVICE_ROLE_KEY"}'::jsonb,
      body:='{}'::jsonb
    );
  $$
);
