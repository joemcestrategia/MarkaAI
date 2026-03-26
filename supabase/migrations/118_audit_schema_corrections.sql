-- ============================================================================
-- Migration 118: Audit Schema Corrections
-- Adds missing columns identified during scheduling/business logic audit.
-- Uses ADD COLUMN IF NOT EXISTS to be idempotent.
-- ============================================================================

-- ── 1. USERS: Client classification columns ─────────────────────────────────
-- These columns allow manual override of client status (VIP/problematic)
-- by the shop owner, independent of the automatic calculation.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_vip BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_problematic BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS vip_since TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS problematic_since TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS visit_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_visit_at TIMESTAMPTZ;

-- ── 2. APPOINTMENTS: Missing audit/tracking columns ─────────────────────────

ALTER TABLE public.appointments
  ADD COLUMN IF NOT EXISTS client_phone TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT;

-- ── 3. Ensure column types are correct ──────────────────────────────────────
-- duration_min should never be null; set default for future inserts
ALTER TABLE public.appointments
  ALTER COLUMN duration_min SET DEFAULT 30;

-- ── 4. INDEX for common query patterns ──────────────────────────────────────
-- Speed up conflict detection queries in checkAvailability and slot generation
CREATE INDEX IF NOT EXISTS idx_appointments_professional_scheduled
  ON public.appointments (professional_id, scheduled_at)
  WHERE status NOT IN ('cancelado', 'rejeitado', 'excluido');

-- Speed up client appointment lookups
CREATE INDEX IF NOT EXISTS idx_appointments_client_shop
  ON public.appointments (client_id, shop_id)
  WHERE status NOT IN ('cancelado', 'rejeitado', 'excluido');

-- Speed up birthday discount registry anti-fraud lookups
CREATE INDEX IF NOT EXISTS idx_birthday_registry_shop_year
  ON public.birthday_discount_registry (shop_id, year, identifier);
