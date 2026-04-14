-- ============================================================
-- Migration 155: Fix RLS policy for ticket creation
-- The old policy required shop_id to match an owned shop,
-- which blocked regular clients (non-owners) from creating tickets.
-- New policy: any authenticated user can create a ticket as long as
-- opened_by_user_id matches their auth.uid().
-- ============================================================

DROP POLICY IF EXISTS "client_insert_ticket" ON public.support_tickets;

CREATE POLICY "client_insert_ticket"
  ON public.support_tickets FOR INSERT TO authenticated
  WITH CHECK (
    opened_by_user_id = auth.uid()
  );
