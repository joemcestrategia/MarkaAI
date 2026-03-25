-- Migration to add service_ids to coupons table
ALTER TABLE public.coupons ADD COLUMN IF NOT EXISTS service_ids UUID[] DEFAULT NULL;

COMMENT ON COLUMN public.coupons.service_ids IS 'List of service UUIDs that this coupon applies to. If NULL or empty, applies to all services.';
