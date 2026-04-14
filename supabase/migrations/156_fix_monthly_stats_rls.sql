-- ============================================================================
-- 156: Fix RLS violation on shop_monthly_stats when trigger fires
-- The recalculate function must run as SECURITY DEFINER so the trigger
-- (which executes in the caller's context) can INSERT/UPDATE the stats table.
-- ============================================================================

-- Recreate recalculate_shop_month as SECURITY DEFINER
CREATE OR REPLACE FUNCTION public.recalculate_shop_month(
    p_shop_id TEXT, p_year INT, p_month INT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
          'concluido','finalizado','pago','confirmado',
          'agendado','pendente','completed','efetuado'
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
