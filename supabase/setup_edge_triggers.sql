-- CRON JOB para executar calcularFeriados diariamente

-- Certifique-se de que a extensão pg_cron e pg_net estão ativadas
create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Agenda a chamada HTTP todo dia às 00:30 (Horário do banco, recomendado usar UTC equivalentemente 03:30 depende do tz)
select cron.schedule(
  'edge-calcular-feriados', -- job name
  '30 0 * * *',             -- cron schedule (every day at 00:30)
  $$
    select net.http_post(
      url:='https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/calcularFeriados',
      headers:='{"Content-Type": "application/json", "Authorization": "Bearer SUA_SERVICE_ROLE_KEY"}'::jsonb,
      body:='{}'::jsonb
    );
  $$
);


-- DATABASE WEBHOOK para Notificações de Agendamentos
-- Chamamos a Edge Function automaticamente em INSERT e UPDATE (somente status cancelado lidado dentro) na tabela appointments

-- Gatilho usando a extensão pg_net (recomendado) para chamar a Edge Function
-- Nota: A função no config.toml foi configurada com verify_jwt = false para facilitar.
create or replace function public.notify_appointment_changes()
returns trigger as $$
begin
  perform net.http_post(
    url := 'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/appointmentTriggers',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVoY2NnY29qd3F2a2Z5enJtZWJ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM5NjYwNDgsImV4cCI6MjA4OTU0MjA0OH0.bK3UsISxVqw5gJktnBkMwmh7Swb17eV-UgD2Ia9e_PA'
    ),
    body := jsonb_build_object(
      'type', TG_OP,
      'table', TG_TABLE_NAME,
      'record', row_to_json(NEW),
      'old_record', (case when TG_OP = 'UPDATE' then row_to_json(OLD) else null end)
    ),
    timeout_milliseconds := 10000
  );
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists appointments_trigger_webhook on public.appointments;

create trigger appointments_trigger_webhook
  after insert or update on public.appointments
  for each row execute function public.notify_appointment_changes();
