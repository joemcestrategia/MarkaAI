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

create or replace trigger "appointments_trigger_webhook"
  after insert or update on "public"."appointments"
  for each row execute function "supabase_functions"."http_request"(
    'https://uhccgcojwqvkfyzrmebv.supabase.co/functions/v1/appointmentTriggers',
    'POST',
    '{"Content-type":"application/json"}',
    '{}',
    '10000'
  );
