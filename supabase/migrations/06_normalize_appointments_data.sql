-- 06_normalize_appointments_data.sql
-- Normaliza os dados dos agendamentos migrados do Firebase
-- SEGURO: só atualiza colunas que confirmadamente existem na tabela.

-- ════════════════════════════════════════
-- PASSO 1: Ver quais colunas existem (diagnóstico)
-- ════════════════════════════════════════
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'appointments'
ORDER BY ordinal_position;

-- ════════════════════════════════════════
-- PASSO 2: Preenche client_name a partir de users onde client_id existir
-- ════════════════════════════════════════
UPDATE public.appointments a
SET client_name = u.name
FROM public.users u
WHERE
  a.client_id = u.id::text
  AND (a.client_name IS NULL OR a.client_name = '' OR a.client_name = 'Cliente')
  AND u.name IS NOT NULL
  AND u.name <> '';

-- ════════════════════════════════════════
-- PASSO 3: Preenche client_phone a partir de users onde client_id existir
-- ════════════════════════════════════════
UPDATE public.appointments a
SET client_phone = u.phone
FROM public.users u
WHERE
  a.client_id = u.id::text
  AND (a.client_phone IS NULL OR a.client_phone = '')
  AND u.phone IS NOT NULL
  AND u.phone <> '';

-- ════════════════════════════════════════
-- PASSO 4: Preenche service_name a partir de services onde service_id existir
-- ════════════════════════════════════════
UPDATE public.appointments a
SET service_name = s.name
FROM public.services s
WHERE
  a.service_id = s.id::text
  AND (a.service_name IS NULL OR a.service_name = '' OR a.service_name = 'Serviço')
  AND s.name IS NOT NULL;

-- ════════════════════════════════════════
-- PASSO 5: Normaliza status para valores em português
-- ════════════════════════════════════════
UPDATE public.appointments
SET status = CASE
  WHEN LOWER(status) IN ('completed', 'done', 'paid', 'finalizado') THEN 'concluido'
  WHEN LOWER(status) IN ('canceled', 'cancelled') THEN 'cancelado'
  WHEN LOWER(status) IN ('pending', 'waiting', 'agendado', 'scheduled') THEN 'pendente'
  ELSE status
END
WHERE status IS NOT NULL
  AND status NOT IN ('pendente', 'concluido', 'cancelado');

-- ════════════════════════════════════════
-- RESULTADO: relatório final
-- ════════════════════════════════════════
SELECT
  COUNT(*) AS total_agendamentos,
  COUNT(client_name) FILTER (WHERE client_name IS NOT NULL AND client_name != '') AS com_nome,
  COUNT(*) FILTER (WHERE client_name IS NULL OR client_name = '' OR client_name = 'Cliente') AS sem_nome,
  COUNT(service_name) FILTER (WHERE service_name IS NOT NULL AND service_name != '') AS com_servico,
  COUNT(*) FILTER (WHERE service_name IS NULL OR service_name = '') AS sem_servico
FROM public.appointments;
