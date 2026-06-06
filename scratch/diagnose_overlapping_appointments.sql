-- =====================================================================
-- DIAGNÓSTICO: Agendamentos com sobreposição (preparação para migration 179)
-- Execute cada query separadamente no SQL Editor do Supabase.
-- =====================================================================

-- ▼▼▼ QUERY 1: Lista TODOS os pares com overlap (visão completa) ▼▼▼
SELECT
  a1.id                AS id_a,
  a1.scheduled_at      AS inicio_a,
  a1.duration_min      AS dur_min_a,
  (a1.scheduled_at + (a1.duration_min || ' minutes')::INTERVAL) AS fim_a,
  a1.status            AS status_a,
  a1.client_name       AS cliente_a,
  a1.service_name      AS servico_a,
  a2.id                AS id_b,
  a2.scheduled_at      AS inicio_b,
  a2.duration_min      AS dur_min_b,
  (a2.scheduled_at + (a2.duration_min || ' minutes')::INTERVAL) AS fim_b,
  a2.status            AS status_b,
  a2.client_name       AS cliente_b,
  a2.service_name      AS servico_b,
  a1.professional_id,
  a1.professional_name
FROM public.appointments a1
JOIN public.appointments a2
  ON a1.professional_id = a2.professional_id
 AND a1.id < a2.id
 AND a1.status NOT IN ('cancelado','rejeitado','recusado','excluido')
 AND a2.status NOT IN ('cancelado','rejeitado','recusado','excluido')
 AND public.appointment_time_range(a1.scheduled_at, a1.duration_min)
     && public.appointment_time_range(a2.scheduled_at, a2.duration_min)
ORDER BY a1.scheduled_at;


-- ▼▼▼ QUERY 2: Agendamentos com duration_min suspeita (> 480 min = > 8h) ▼▼▼
-- Provavelmente preenchidos em horas em vez de minutos, ou bloqueios de dia inteiro
SELECT
  id,
  scheduled_at,
  duration_min,
  status,
  client_name,
  service_name,
  professional_name,
  shop_id
FROM public.appointments
WHERE duration_min > 480
  AND status NOT IN ('cancelado','rejeitado','recusado','excluido')
ORDER BY duration_min DESC;


-- ▼▼▼ QUERY 3: Contagem por shop_id (priorizar lojas mais afetadas) ▼▼▼
SELECT
  a1.shop_id,
  COUNT(*) AS pares_em_conflito
FROM public.appointments a1
JOIN public.appointments a2
  ON a1.professional_id = a2.professional_id
 AND a1.id < a2.id
 AND a1.status NOT IN ('cancelado','rejeitado','recusado','excluido')
 AND a2.status NOT IN ('cancelado','rejeitado','recusado','excluido')
 AND public.appointment_time_range(a1.scheduled_at, a1.duration_min)
     && public.appointment_time_range(a2.scheduled_at, a2.duration_min)
GROUP BY a1.shop_id
ORDER BY pares_em_conflito DESC;


-- ▼▼▼ QUERY 4: Ver o caso específico do erro do usuário ▼▼▼
SELECT
  id, scheduled_at, duration_min, status, client_name, service_name,
  (scheduled_at + (duration_min || ' minutes')::INTERVAL) AS fim,
  created_at
FROM public.appointments
WHERE professional_id = '5628104f-4547-4ebf-861c-a26d51460b27'
  AND scheduled_at::date = '2026-04-08'
  AND status NOT IN ('cancelado','rejeitado','recusado','excluido')
ORDER BY scheduled_at;
