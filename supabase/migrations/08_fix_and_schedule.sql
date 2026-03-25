-- 08_fix_and_schedule.sql
-- Atualiza os agendamentos antigos que vieram da migração com valores nulos

BEGIN;

-- Preenche agendamentos que ficaram órfãos de nome e ID na migração
UPDATE public.appointments
SET 
  client_name = COALESCE(client_name, 'Cliente Migrado'),
  service_name = COALESCE(service_name, 'Serviço Antigo'),
  duration_min = COALESCE(duration_min, 30)
WHERE 
  client_name IS NULL 
  OR service_name IS NULL
  OR TRIM(client_name) = ''
  OR TRIM(service_name) = '';

-- Atualiza METADATA para forçar o Supabase Realtime a dar um "Wake Up" no cache do Flutter
UPDATE public.appointments
SET 
  metadata = COALESCE(metadata, '{}'::jsonb) 
             || jsonb_build_object('client_nome', client_name) 
             || jsonb_build_object('servico_nome', service_name)
WHERE 
  client_name IS NOT NULL 
  OR service_name IS NOT NULL;

COMMIT;
