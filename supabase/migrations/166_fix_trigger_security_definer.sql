-- ============================================================================
-- 166: Fix RLS violation — ensure trigger function runs as SECURITY DEFINER
-- Corrige: PostgrestException new row violates row-level security policy
--          for table "shop_monthly_stats" ao salvar ou excluir agendamentos.
-- A migration 156 já tentou corrigir a função recalculate_shop_month, mas
-- o trigger_update_monthly_stats também precisa de SECURITY DEFINER para que
-- o contexto de execução do trigger tenha permissão de escrita na tabela.
-- ============================================================================

-- 1. Recria a função helper com SECURITY DEFINER (idempotente)
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

-- 2. Recria a função do trigger com SECURITY DEFINER
--    Isso garante que o trigger execute com privilégios do owner (postgres),
--    ignorando a RLS da tabela shop_monthly_stats independente de quem disparou.
CREATE OR REPLACE FUNCTION public.trigger_update_monthly_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Recalculate the NEW row's month on INSERT or UPDATE
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

    -- If UPDATE moved the appointment to a different month, fix the old month too
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

-- 3. Garante que o trigger está corretamente associado (recria se necessário)
DROP TRIGGER IF EXISTS trg_appointments_monthly_stats ON public.appointments;
CREATE TRIGGER trg_appointments_monthly_stats
    AFTER INSERT OR UPDATE OR DELETE ON public.appointments
    FOR EACH ROW EXECUTE FUNCTION public.trigger_update_monthly_stats();
