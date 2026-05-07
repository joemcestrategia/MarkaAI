-- ============================================================================
-- 167: Definitive fix — all trigger/helper functions that write to RLS-protected
--      tables must run as SECURITY DEFINER.
--
-- Root causes fixed here:
--   A) recalculate_shop_month — migrations 164 & 165 overwrote it without
--      SECURITY DEFINER, breaking appointment booking (code 42501).
--      This version preserves the 165 filter logic (NOT IN cancelled/falta/etc.)
--      while restoring SECURITY DEFINER.
--
--   B) fn_ticket_last_reply — fires AFTER INSERT on ticket_messages, then does
--      UPDATE on support_tickets. Clients have INSERT on ticket_messages but
--      no UPDATE policy on support_tickets → would fail with 42501 when a
--      client posts a reply.
--
--   C) fn_ticket_history — fires AFTER UPDATE on support_tickets, INSERTs into
--      ticket_history. Admin path is fine (full access policy), but adding
--      SECURITY DEFINER makes it robust against future access patterns.
-- ============================================================================

-- ── A. recalculate_shop_month ─────────────────────────────────────────────
-- Uses the filter from migration 165 (exclude cancelled/falta/recusado only).
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

-- ── A2. trigger_update_monthly_stats ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trigger_update_monthly_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM public.recalculate_shop_month(
            NEW.shop_id,
            EXTRACT(YEAR  FROM NEW.scheduled_at)::INT,
            EXTRACT(MONTH FROM NEW.scheduled_at)::INT
        );
    END IF;

    IF TG_OP = 'DELETE' THEN
        PERFORM public.recalculate_shop_month(
            OLD.shop_id,
            EXTRACT(YEAR  FROM OLD.scheduled_at)::INT,
            EXTRACT(MONTH FROM OLD.scheduled_at)::INT
        );
    END IF;

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

-- Reattach trigger (idempotent)
DROP TRIGGER IF EXISTS trg_appointments_monthly_stats ON public.appointments;
CREATE TRIGGER trg_appointments_monthly_stats
    AFTER INSERT OR UPDATE OR DELETE ON public.appointments
    FOR EACH ROW EXECUTE FUNCTION public.trigger_update_monthly_stats();

-- ── B. fn_ticket_last_reply ───────────────────────────────────────────────
-- Fires AFTER INSERT on ticket_messages. UPDATEs support_tickets (which has
-- no client UPDATE policy). SECURITY DEFINER allows the UPDATE regardless of
-- who inserted the message.
CREATE OR REPLACE FUNCTION public.fn_ticket_last_reply()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.support_tickets SET
        last_reply_at     = NEW.created_at,
        last_reply_by     = CASE WHEN NEW.author_role = 'client' THEN 'client' ELSE 'support' END,
        has_unread_admin  = CASE WHEN NEW.author_role = 'client' THEN true ELSE has_unread_admin END,
        has_unread_client = CASE
            WHEN NEW.author_role IN ('support', 'admin') AND NEW.is_internal = false
            THEN true
            ELSE has_unread_client
        END
    WHERE id = NEW.ticket_id;
    RETURN NEW;
END;
$$;

-- ── C. fn_ticket_history ──────────────────────────────────────────────────
-- Fires AFTER UPDATE on support_tickets. INSERTs into ticket_history.
-- Clients never UPDATE support_tickets directly (only via SECURITY DEFINER
-- RPCs), so this was safe before, but explicit SECURITY DEFINER is more robust.
CREATE OR REPLACE FUNCTION public.fn_ticket_history()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
        VALUES (NEW.id, 'Sistema', 'system', 'Status alterado', OLD.status, NEW.status);
    END IF;
    IF OLD.priority IS DISTINCT FROM NEW.priority THEN
        INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
        VALUES (NEW.id, 'Sistema', 'system', 'Prioridade alterada', OLD.priority, NEW.priority);
    END IF;
    IF OLD.assigned_to IS DISTINCT FROM NEW.assigned_to THEN
        INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
        VALUES (NEW.id, 'Sistema', 'system', 'Atribuição alterada', OLD.assigned_to::TEXT, NEW.assigned_to::TEXT);
    END IF;
    IF OLD.category IS DISTINCT FROM NEW.category THEN
        INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
        VALUES (NEW.id, 'Sistema', 'system', 'Categoria alterada', OLD.category, NEW.category);
    END IF;
    IF NEW.status = 'resolved' AND OLD.status != 'resolved' THEN
        NEW.resolved_at := now();
    END IF;
    IF NEW.status = 'closed' AND OLD.status != 'closed' THEN
        NEW.closed_at := now();
    END IF;
    RETURN NEW;
END;
$$;
