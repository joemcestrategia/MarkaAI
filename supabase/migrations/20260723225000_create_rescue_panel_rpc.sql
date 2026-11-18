-- 20260723225000_create_rescue_panel_rpc.sql
-- RPC para buscar e agregar os clientes para o Painel de Resgate (Pro Only)

DROP FUNCTION IF EXISTS public.normalize_phone;
CREATE OR REPLACE FUNCTION public.normalize_phone(p TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
RETURNS NULL ON NULL INPUT
AS $$
  WITH digits_only AS (
    SELECT regexp_replace(p, '[^0-9]', '', 'g') AS d
  ),
  strip_country AS (
    SELECT CASE
      WHEN length(d) >= 12 AND d LIKE '55%'
      THEN substring(d FROM 3)
      ELSE d
    END AS d
    FROM digits_only
  ),
  strip_operator AS (
    SELECT CASE
      WHEN length(d) > 11 AND d LIKE '0%'
      THEN substring(d FROM 2)
      ELSE d
    END AS d
    FROM strip_country
  )
  SELECT d FROM strip_operator;
$$;

DROP FUNCTION IF EXISTS public.get_rescue_clients;
CREATE OR REPLACE FUNCTION public.get_rescue_clients(p_shop_id UUID)
RETURNS TABLE (
    client_uid TEXT,
    client_name TEXT,
    client_phone TEXT,
    client_photo_url TEXT,
    days_since_last_visit INTEGER,
    total_spent DOUBLE PRECISION,
    total_visits INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shop_id_str TEXT := p_shop_id::text;
    v_is_pro BOOLEAN := false;
BEGIN
    -- 1. Check shop plan
    SELECT EXISTS (
        SELECT 1 FROM public.shops
        WHERE id::text = v_shop_id_str
          AND (
              plan_id = 'pro'
              OR subscription->>'plan_id' = 'pro'
          )
    ) INTO v_is_pro;

    IF NOT v_is_pro THEN
        RAISE EXCEPTION 'Acesso negado: o Painel de Resgate e um recurso exclusivo do Plano Pro.';
    END IF;

    -- 2. Aggregate data (apenas concluido, confirmado, confirmed_by_client)
    RETURN QUERY
    WITH base_data AS (
        SELECT 
            COALESCE(NULLIF(a.client_id, ''), public.normalize_phone(a.client_phone)) AS can_id,
            a.client_id,
            a.client_phone,
            a.client_name,
            a.scheduled_at,
            COALESCE(a.total_price, a.total_value, 0) AS safe_price
        FROM public.appointments a
        WHERE a.shop_id::text = v_shop_id_str
          AND a.status IN ('concluido', 'confirmado', 'confirmed_by_client')
          AND a.scheduled_at <= NOW()
    ),
    aggregated AS (
        SELECT 
            b.can_id,
            MAX(b.client_id::text) AS matched_client_id,
            MAX(b.client_phone) AS raw_phone,
            MAX(b.client_name) AS raw_name,
            MAX(b.scheduled_at) AS max_scheduled_at,
            SUM(b.safe_price) AS sum_spent,
            COUNT(1) AS count_visits
        FROM base_data b
        WHERE b.can_id IS NOT NULL AND b.can_id != ''
        GROUP BY b.can_id
    ),
    enriched AS (
        SELECT 
            a.matched_client_id AS out_uid,
            COALESCE(u.name, a.raw_name) AS out_name,
            COALESCE(u.phone, a.raw_phone) AS out_phone,
            u.photo_url AS out_photo_url,
            EXTRACT(DAY FROM (now() - a.max_scheduled_at))::INTEGER AS out_days_since_last_visit,
            a.sum_spent::DOUBLE PRECISION AS out_total_spent,
            a.count_visits::INTEGER AS out_total_visits
        FROM aggregated a
        LEFT JOIN public.users u ON u.id::text = a.matched_client_id
    )
    SELECT e.out_uid, e.out_name, e.out_phone, e.out_photo_url,
           e.out_days_since_last_visit, e.out_total_spent, e.out_total_visits
    FROM enriched e
    WHERE e.out_name IS NOT NULL
      AND e.out_name != ''
      AND e.out_name != 'Desconhecido'
    ORDER BY e.out_days_since_last_visit DESC;
END;
$$;
