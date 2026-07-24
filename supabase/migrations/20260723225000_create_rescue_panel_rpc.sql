-- 20260723225000_create_rescue_panel_rpc.sql
-- RPC para buscar e agregar os clientes para o Painel de Resgate (Pro Only)

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

CREATE OR REPLACE FUNCTION public.get_rescue_clients(p_shop_id UUID)
RETURNS TABLE (
    canonical_id TEXT,
    client_name TEXT,
    client_phone TEXT,
    client_photo_url TEXT,
    days_since_last_visit INTEGER,
    total_spent DOUBLE PRECISION,
    total_visits INTEGER,
    last_visit_date TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_plan_id TEXT;
    v_trial_active BOOLEAN;
    v_subscription JSONB;
    v_is_pro BOOLEAN := false;
BEGIN
    -- 1. Check shop plan
    SELECT plan_id, trial_active, subscription
    INTO v_plan_id, v_trial_active, v_subscription
    FROM public.shops
    WHERE id = p_shop_id;

    IF v_plan_id = 'pro' THEN
        v_is_pro := true;
    ELSIF v_trial_active = true AND v_subscription->>'plan_id' = 'pro' THEN
        v_is_pro := true;
    ELSIF v_subscription->>'plan_id' = 'pro' THEN
        v_is_pro := true;
    ELSIF v_subscription->>'status' = 'trial' THEN
        v_is_pro := true;
    END IF;

    IF NOT v_is_pro THEN
        RAISE EXCEPTION 'Access Denied: Rescue Panel is a Pro feature.';
    END IF;

    -- 2. Aggregate data
    RETURN QUERY
    WITH base_data AS (
        SELECT 
            COALESCE(NULLIF(a.client_id, ''), public.normalize_phone(a.client_phone)) AS can_id,
            a.client_id,
            a.client_phone,
            a.client_name,
            a.scheduled_at,
            COALESCE(a.total_price, a.total_value, 0) AS val
        FROM public.appointments a
        WHERE a.shop_id = p_shop_id
          AND a.status = 'concluido'
    ),
    aggregated AS (
        SELECT 
            can_id,
            MAX(client_id) AS matched_client_id,
            MAX(client_phone) AS raw_phone,
            MAX(client_name) AS raw_name,
            MAX(scheduled_at) AS max_scheduled_at,
            SUM(val) AS sum_spent,
            COUNT(1) AS count_visits
        FROM base_data
        WHERE can_id IS NOT NULL AND can_id != ''
        GROUP BY can_id
    )
    SELECT 
        agg.can_id,
        COALESCE(u.name, agg.raw_name) AS client_name,
        COALESCE(u.phone, agg.raw_phone) AS client_phone,
        u.photo_url AS client_photo_url,
        EXTRACT(DAY FROM (now() - agg.max_scheduled_at))::INTEGER AS days_since_last_visit,
        agg.sum_spent::DOUBLE PRECISION AS total_spent,
        agg.count_visits::INTEGER AS total_visits,
        agg.max_scheduled_at AS last_visit_date
    FROM aggregated agg
    LEFT JOIN public.users u ON agg.matched_client_id = u.id::text;
END;
$$;
