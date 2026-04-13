-- =============================================================================
-- 152_support_ticket_client_rpcs.sql
-- RPC functions that allow clients to close/reopen their own tickets
-- (clients can't UPDATE support_tickets directly via RLS)
-- =============================================================================

-- Client confirms resolved → closes the ticket
CREATE OR REPLACE FUNCTION public.client_close_ticket(p_ticket_id UUID)
RETURNS VOID AS $$
BEGIN
  -- Verify the caller owns this ticket
  IF NOT EXISTS (
    SELECT 1 FROM public.support_tickets
    WHERE id = p_ticket_id AND opened_by_user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Ticket não encontrado ou sem permissão.';
  END IF;

  UPDATE public.support_tickets
  SET status = 'closed'
  WHERE id = p_ticket_id
    AND opened_by_user_id = auth.uid()
    AND status = 'resolved';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Client reopens a resolved ticket
CREATE OR REPLACE FUNCTION public.client_reopen_ticket(p_ticket_id UUID, p_author_name TEXT DEFAULT 'Cliente')
RETURNS VOID AS $$
BEGIN
  -- Verify the caller owns this ticket
  IF NOT EXISTS (
    SELECT 1 FROM public.support_tickets
    WHERE id = p_ticket_id AND opened_by_user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Ticket não encontrado ou sem permissão.';
  END IF;

  UPDATE public.support_tickets
  SET status = 'open'
  WHERE id = p_ticket_id
    AND opened_by_user_id = auth.uid()
    AND status IN ('resolved', 'closed');

  -- Add a system history entry
  INSERT INTO public.ticket_history (ticket_id, actor_name, actor_role, action, old_value, new_value)
  VALUES (p_ticket_id, p_author_name, 'client', 'Ticket reaberto pelo cliente', 'resolved', 'open');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.client_close_ticket(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.client_reopen_ticket(UUID, TEXT) TO authenticated;
