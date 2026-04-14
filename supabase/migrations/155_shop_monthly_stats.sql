-- ============================================================================
-- 155: Pre-calculated monthly statistics per shop
-- Eliminates heavy full-table scans on appointments for the dashboard.
-- The trigger auto-recalculates the affected month on every appointment change.
-- ============================================================================

-- 1. Table
CREATE TABLE IF NOT EXISTS public.shop_monthly_stats (
    shop_id  TEXT     NOT NULL,
    year     SMALLINT NOT NULL,
    month    SMALLINT NOT NULL,
    revenue           NUMERIC  DEFAULT 0,
    appointments_count INT     DEFAULT 0,
    updated_at        TIMESTAMPTZ DEFAULT now(),
    PRIMARY KEY (shop_id, year, month)
);

-- 2. RLS
ALTER TABLE public.shop_monthly_stats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "shop_owner_read_stats"
    ON public.shop_monthly_stats FOR SELECT
    USING (
        shop_id IN (SELECT u.shop_id FROM public.users u WHERE u.id::text = auth.uid()::text)
    );

CREATE POLICY "service_role_all_stats"
    ON public.shop_monthly_stats FOR ALL
    USING (auth.role() = 'service_role');

-- 3. Helper: extract best non-zero value from an appointment row
CREATE OR REPLACE FUNCTION public.get_appointment_revenue(
    p_total_payable NUMERIC,
    p_total_price NUMERIC,
    p_total_value NUMERIC,
    p_valor_com_desconto NUMERIC,
    p_labor_value NUMERIC
) RETURNS NUMERIC
LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN COALESCE(p_total_payable, 0) > 0 THEN p_total_payable
        WHEN COALESCE(p_total_price, 0) > 0   THEN p_total_price
        WHEN COALESCE(p_total_value, 0) > 0   THEN p_total_value
        WHEN COALESCE(p_valor_com_desconto, 0) > 0 THEN p_valor_com_desconto
        WHEN COALESCE(p_labor_value, 0) > 0    THEN p_labor_value
        ELSE 0
    END;
$$;

-- 4. Recalculate a single (shop, year, month) bucket
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

-- 5. Trigger function
CREATE OR REPLACE FUNCTION public.trigger_update_monthly_stats()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    -- Recalculate the NEW row's month
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM public.recalculate_shop_month(
            NEW.shop_id,
            EXTRACT(YEAR  FROM NEW.scheduled_at)::INT,
            EXTRACT(MONTH FROM NEW.scheduled_at)::INT
        );
    END IF;

    -- Recalculate the OLD row's month on DELETE
    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_shop_month(
            OLD.shop_id,
            EXTRACT(YEAR  FROM OLD.scheduled_at)::INT,
            EXTRACT(MONTH FROM OLD.scheduled_at)::INT
        );
    END IF;

    -- If UPDATE moved the appointment to a different month, also fix the old month
    IF TG_OP = 'UPDATE' AND (
        EXTRACT(YEAR  FROM OLD.scheduled_at) != EXTRACT(YEAR  FROM NEW.scheduled_at) OR
        EXTRACT(MONTH FROM OLD.scheduled_at) != EXTRACT(MONTH FROM NEW.scheduled_at) OR
        OLD.shop_id != NEW.shop_id
    ) THEN
        PERFORM public.recalculate_shop_month(
            OLD.shop_id,
            EXTRACT(YEAR  FROM OLD.scheduled_at)::INT,
            EXTRACT(MONTH FROM OLD.scheduled_at)::INT
        );
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- 6. Attach trigger
DROP TRIGGER IF EXISTS trg_appointments_monthly_stats ON public.appointments;
CREATE TRIGGER trg_appointments_monthly_stats
    AFTER INSERT OR UPDATE OR DELETE ON public.appointments
    FOR EACH ROW EXECUTE FUNCTION public.trigger_update_monthly_stats();

-- 7. Populate with all existing data
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
    'concluido','finalizado','pago','confirmado',
    'agendado','pendente','completed','efetuado'
)
GROUP BY a.shop_id,
         EXTRACT(YEAR  FROM a.scheduled_at),
         EXTRACT(MONTH FROM a.scheduled_at)
ON CONFLICT (shop_id, year, month) DO UPDATE SET
    revenue            = EXCLUDED.revenue,
    appointments_count = EXCLUDED.appointments_count,
    updated_at         = now();

-- 8. Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_shop_monthly_stats_shop_year
    ON public.shop_monthly_stats (shop_id, year);
