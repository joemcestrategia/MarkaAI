-- ============================================================================
-- 164: Fix revenue status filter in shop_monthly_stats
-- The previous recalculate_shop_month incorrectly included 'confirmado',
-- 'agendado' and 'pendente' causing inflated dashboard revenue vs financial page.
-- Only truly completed/paid appointments should count as revenue.
-- ============================================================================

-- 1. Fix the recalculate function with correct status set
CREATE OR REPLACE FUNCTION public.recalculate_shop_month(
    p_shop_id TEXT, p_year INT, p_month INT
) RETURNS VOID
LANGUAGE plpgsql AS $$
DECLARE
    v_revenue NUMERIC := 0;
    v_count   INT     := 0;
BEGIN
    SELECT
        COALESCE(SUM(
            public.get_appointment_revenue(
                a.total_payable, a.total_price, a.total_value,
                a.valor_com_desconto, a.labor_value
            )
        ), 0),
        COUNT(*)
    INTO v_revenue, v_count
    FROM public.appointments a
    WHERE a.shop_id = p_shop_id
      AND EXTRACT(YEAR  FROM a.scheduled_at)::INT = p_year
      AND EXTRACT(MONTH FROM a.scheduled_at)::INT = p_month
      AND LOWER(a.status) IN (
          'concluido', 'finalizado', 'pago', 'efetuado', 'completed'
      );

    INSERT INTO public.shop_monthly_stats
           (shop_id, year, month, revenue, appointments_count, updated_at)
    VALUES (p_shop_id, p_year::SMALLINT, p_month::SMALLINT, v_revenue, v_count, now())
    ON CONFLICT (shop_id, year, month) DO UPDATE SET
        revenue            = v_revenue,
        appointments_count = v_count,
        updated_at         = now();
END;
$$;

-- 2. Repopulate all existing data with corrected status filter
INSERT INTO public.shop_monthly_stats (shop_id, year, month, revenue, appointments_count, updated_at)
SELECT
    a.shop_id,
    EXTRACT(YEAR  FROM a.scheduled_at)::SMALLINT,
    EXTRACT(MONTH FROM a.scheduled_at)::SMALLINT,
    COALESCE(SUM(
        public.get_appointment_revenue(
            a.total_payable, a.total_price, a.total_value,
            a.valor_com_desconto, a.labor_value
        )
    ), 0),
    COUNT(*),
    now()
FROM public.appointments a
WHERE LOWER(a.status) IN (
    'concluido', 'finalizado', 'pago', 'efetuado', 'completed'
)
GROUP BY a.shop_id,
         EXTRACT(YEAR  FROM a.scheduled_at),
         EXTRACT(MONTH FROM a.scheduled_at)
ON CONFLICT (shop_id, year, month) DO UPDATE SET
    revenue            = EXCLUDED.revenue,
    appointments_count = EXCLUDED.appointments_count,
    updated_at         = now();
