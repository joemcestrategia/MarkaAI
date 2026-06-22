-- Fix: get_shop_blocked_slots e get_professional_blocked_slots type casting
-- A coluna appointments.shop_id e professional_id é do tipo UUID, mas os params são TEXT.
-- Adicionando ::text às colunas para evitar o erro "operator does not exist: text = uuid"

CREATE OR REPLACE FUNCTION public.get_professional_blocked_slots(
  p_professional_id TEXT,
  p_start_date TIMESTAMPTZ,
  p_end_date TIMESTAMPTZ
)
RETURNS TABLE(
  id TEXT,
  scheduled_at TIMESTAMPTZ,
  duration_min INT,
  service_id TEXT,
  status TEXT,
  professional_id TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    a.id::text,
    a.scheduled_at,
    a.duration_min,
    a.service_id::text,
    a.status,
    a.professional_id::text
  FROM public.appointments a
  WHERE a.professional_id::text = p_professional_id
    AND a.scheduled_at >= p_start_date
    AND a.scheduled_at < p_end_date;
$$;

CREATE OR REPLACE FUNCTION public.get_professionals_blocked_slots(
  p_professional_ids TEXT[],
  p_start_date TIMESTAMPTZ,
  p_end_date TIMESTAMPTZ
)
RETURNS TABLE(
  id TEXT,
  scheduled_at TIMESTAMPTZ,
  duration_min INT,
  service_id TEXT,
  status TEXT,
  professional_id TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    a.id::text,
    a.scheduled_at,
    a.duration_min,
    a.service_id::text,
    a.status,
    a.professional_id::text
  FROM public.appointments a
  WHERE a.professional_id::text = ANY(p_professional_ids)
    AND a.scheduled_at >= p_start_date
    AND a.scheduled_at < p_end_date;
$$;

CREATE OR REPLACE FUNCTION public.get_shop_blocked_slots(
  p_shop_id TEXT,
  p_start_date TIMESTAMPTZ,
  p_end_date TIMESTAMPTZ
)
RETURNS TABLE(
  id TEXT,
  scheduled_at TIMESTAMPTZ,
  duration_min INT,
  service_id TEXT,
  status TEXT,
  professional_id TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    a.id::text,
    a.scheduled_at,
    a.duration_min,
    a.service_id::text,
    a.status,
    a.professional_id::text
  FROM public.appointments a
  WHERE a.shop_id::text = p_shop_id
    AND a.scheduled_at >= p_start_date
    AND a.scheduled_at < p_end_date;
$$;
