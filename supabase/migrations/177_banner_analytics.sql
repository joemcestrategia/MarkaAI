-- 177_banner_analytics.sql
-- Adiciona tracking de impressões/cliques nos banners de marketing.
-- Suporta modelo de negócio: venda de espaço publicitário para anunciantes.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Colunas de métricas agregadas na tabela principal (fast-read)
-- ─────────────────────────────────────────────────────────────────────────────
ALTER TABLE public.app_banners
  ADD COLUMN IF NOT EXISTS impressions     bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS clicks          bigint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS advertiser_name text   NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS advertiser_email text  NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS starts_at       timestamptz,
  ADD COLUMN IF NOT EXISTS ends_at         timestamptz,
  ADD COLUMN IF NOT EXISTS budget_impressions bigint;  -- limite de impressões contratado (null = ilimitado)

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Tabela de eventos (log detalhado — útil para relatórios por período)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.banner_events (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  banner_id  uuid NOT NULL REFERENCES public.app_banners(id) ON DELETE CASCADE,
  event_type text NOT NULL CHECK (event_type IN ('impression', 'click')),
  platform   text NOT NULL DEFAULT 'mobile',    -- 'mobile' | 'web'
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- Índice para consultas rápidas por banner + período
CREATE INDEX IF NOT EXISTS idx_banner_events_banner_date
  ON public.banner_events (banner_id, occurred_at DESC);

-- RLS: apenas service_role escreve; admin lê
ALTER TABLE public.banner_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_read_banner_events"
  ON public.banner_events FOR SELECT
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Usuários autenticados e anon podem INSERIR eventos (tracking)
CREATE POLICY "anyone_insert_banner_events"
  ON public.banner_events FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Função + Trigger: incrementa contadores agregados automaticamente
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.increment_banner_counter()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.event_type = 'impression' THEN
    UPDATE public.app_banners
       SET impressions = impressions + 1
     WHERE id = NEW.banner_id;
  ELSIF NEW.event_type = 'click' THEN
    UPDATE public.app_banners
       SET clicks = clicks + 1
     WHERE id = NEW.banner_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_increment_banner_counter ON public.banner_events;
CREATE TRIGGER trg_increment_banner_counter
  AFTER INSERT ON public.banner_events
  FOR EACH ROW EXECUTE FUNCTION public.increment_banner_counter();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RPC: resumo de analytics por banner (para o painel admin)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_banner_analytics(
  p_banner_id uuid,
  p_days      int DEFAULT 30
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result json;
BEGIN
  SELECT json_build_object(
    'banner_id',    p_banner_id,
    'period_days',  p_days,
    'impressions',  COALESCE(SUM(CASE WHEN event_type = 'impression' THEN 1 ELSE 0 END), 0),
    'clicks',       COALESCE(SUM(CASE WHEN event_type = 'click'      THEN 1 ELSE 0 END), 0),
    'ctr_percent',  ROUND(
                      CASE
                        WHEN SUM(CASE WHEN event_type = 'impression' THEN 1 ELSE 0 END) = 0 THEN 0
                        ELSE SUM(CASE WHEN event_type = 'click' THEN 1 ELSE 0 END)::numeric
                             / SUM(CASE WHEN event_type = 'impression' THEN 1 ELSE 0 END) * 100
                      END, 2
                    ),
    'daily', (
      SELECT json_agg(day_data ORDER BY day_data->>'date')
      FROM (
        SELECT json_build_object(
          'date', to_char(occurred_at::date, 'YYYY-MM-DD'),
          'impressions', COUNT(*) FILTER (WHERE event_type = 'impression'),
          'clicks',      COUNT(*) FILTER (WHERE event_type = 'click')
        ) AS day_data
        FROM public.banner_events
        WHERE banner_id = p_banner_id
          AND occurred_at >= now() - (p_days || ' days')::interval
        GROUP BY occurred_at::date
      ) d
    )
  )
  INTO v_result
  FROM public.banner_events
  WHERE banner_id = p_banner_id
    AND occurred_at >= now() - (p_days || ' days')::interval;

  RETURN COALESCE(v_result, '{"impressions":0,"clicks":0,"ctr_percent":0,"daily":[]}'::json);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_banner_analytics(uuid, int) TO authenticated;
