-- Migration 119: Harden coupon system constraints
-- Fixes race conditions, invalid data, and abuse vectors

-- 1. CHECK constraint on discount_percent: must be between 0.01 and 100
-- Prevents 0% (useless), negative (exploitable), or >100% (generates credit) coupons
DO $$
BEGIN
    ALTER TABLE public.coupons
        ADD CONSTRAINT coupons_discount_percent_range
        CHECK (discount_percent > 0 AND discount_percent <= 100);
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint coupons_discount_percent_range already exists';
END $$;

-- 2. CHECK constraint on usage_count: must be >= 0
DO $$
BEGIN
    ALTER TABLE public.coupons
        ADD CONSTRAINT coupons_usage_count_non_negative
        CHECK (usage_count >= 0);
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint coupons_usage_count_non_negative already exists';
END $$;

-- 3. CHECK constraint on max_usage: must be >= 0
DO $$
BEGIN
    ALTER TABLE public.coupons
        ADD CONSTRAINT coupons_max_usage_non_negative
        CHECK (max_usage >= 0);
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint coupons_max_usage_non_negative already exists';
END $$;

-- 4. UNIQUE constraint on coupon_usage (coupon_id, user_id)
-- Prevents race condition where two concurrent requests both pass the
-- maybeSingle() check and both insert a usage record for the same user+coupon
DO $$
BEGIN
    ALTER TABLE public.coupon_usage
        ADD CONSTRAINT coupon_usage_unique_per_user
        UNIQUE (coupon_id, user_id);
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint coupon_usage_unique_per_user already exists';
END $$;

-- 5. Harden increment_coupon_usage RPC:
-- - Only increment if usage_count < max_usage (or max_usage = 0 = unlimited)
-- - Return the new count so caller can verify
CREATE OR REPLACE FUNCTION public.increment_coupon_usage(coupon_id UUID)
RETURNS INTEGER AS $$
DECLARE
    new_count INTEGER;
BEGIN
    UPDATE public.coupons
    SET usage_count = usage_count + 1
    WHERE id = coupon_id
      AND (max_usage = 0 OR usage_count < max_usage)
    RETURNING usage_count INTO new_count;

    IF new_count IS NULL THEN
        RAISE EXCEPTION 'Coupon % has reached its usage limit or does not exist', coupon_id;
    END IF;

    RETURN new_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. CHECK constraint on valid_month: must be between 1 and 12
DO $$
BEGIN
    ALTER TABLE public.coupons
        ADD CONSTRAINT coupons_valid_month_range
        CHECK (valid_month IS NULL OR (valid_month >= 1 AND valid_month <= 12));
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'Constraint coupons_valid_month_range already exists';
END $$;
