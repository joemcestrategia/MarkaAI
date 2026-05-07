-- ============================================================================
-- 165: shop_monthly_stats counts all active (non-cancelled) appointments
-- This gives the full projected revenue for the annual bar chart.
-- The monthly drill-down view uses client-side filtering (Todos/Concluído/Pendentes).
-- ============================================================================

-- Update recalculate function: exclude only cancelled/falta/recusado
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
      AND LOWER(a.status) NOT IN ('cancelado', 'falta', 'recusado', 'rejected', 'cancelled');

    INSERT INTO public.shop_monthly_stats
           (shop_id, year, month, revenue, appointments_count, updated_at)
    VALUES (p_shop_id, p_year::SMALLINT, p_month::SMALLINT, v_revenue, v_count, now())
    ON CONFLICT (shop_id, year, month) DO UPDATE SET
        revenue            = v_revenue,
        appointments_count = v_count,
        updated_at         = now();
END;
$$;

-- Repopulate with corrected filter (all active, not just completed)
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
WHERE LOWER(a.status) NOT IN ('cancelado', 'falta', 'recusado', 'rejected', 'cancelled')
GROUP BY a.shop_id,
         EXTRACT(YEAR  FROM a.scheduled_at),
         EXTRACT(MONTH FROM a.scheduled_at)
ON CONFLICT (shop_id, year, month) DO UPDATE SET
    revenue            = EXCLUDED.revenue,
    appointments_count = EXCLUDED.appointments_count,
    updated_at         = now();
