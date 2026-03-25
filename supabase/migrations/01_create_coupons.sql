-- MARKA AI - Standardized Coupon System
-- This script ensures the coupons and coupon_usage tables exist with correctly named columns.

-- 1. Table: coupons
CREATE TABLE IF NOT EXISTS public.coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id UUID NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    description TEXT,
    discount_percent NUMERIC NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    valid_until TIMESTAMPTZ,
    valid_month INTEGER,
    max_usage INTEGER DEFAULT 0,
    usage_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(shop_id, code)
);

-- 2. Table: coupon_usage
CREATE TABLE IF NOT EXISTS public.coupon_usage (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coupon_id UUID NOT NULL REFERENCES public.coupons(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    used_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. RLS Policies
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_usage ENABLE ROW LEVEL SECURITY;

-- Shops can manage their own coupons
-- Note: Assuming public.shops has an owner_id column as per typical architecture
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Shops can manage their own coupons" ON public.coupons;
    CREATE POLICY "Shops can manage their own coupons" ON public.coupons
        FOR ALL TO authenticated
        USING (shop_id IN (SELECT id FROM public.shops WHERE owner_id = auth.uid()));
EXCEPTION WHEN undefined_table THEN
    -- Fallback if shops table is different, but based on context it should exist
END $$;

-- Users can view coupons (to apply them during booking)
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view coupons" ON public.coupons;
    CREATE POLICY "Users can view coupons" ON public.coupons
        FOR SELECT TO authenticated
        USING (true);
END $$;

-- Users can see their own usages
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view own coupon usage" ON public.coupon_usage;
    CREATE POLICY "Users can view own coupon usage" ON public.coupon_usage
        FOR SELECT TO authenticated
        USING (auth.uid() = user_id);
END $$;

-- Authenticated users can insert coupon usage when booking
DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Authenticated users can insert coupon usage" ON public.coupon_usage;
    CREATE POLICY "Authenticated users can insert coupon usage" ON public.coupon_usage
        FOR INSERT TO authenticated
        WITH CHECK (auth.uid() = user_id);
END $$;

-- 4. RPC for incrementing usage (optional but recommended for concurrency)
CREATE OR REPLACE FUNCTION public.increment_coupon_usage(coupon_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE public.coupons
    SET usage_count = usage_count + 1
    WHERE id = coupon_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
