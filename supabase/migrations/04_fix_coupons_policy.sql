-- Fix Coupons and Coupon Usage RLS Policies
-- Align with 02_harden_security.sql pattern and project structure

-- 1. Coupons Table
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

-- Remove old restrictive policies
DROP POLICY IF EXISTS "Shops can manage their own coupons" ON public.coupons;
DROP POLICY IF EXISTS "Shop Manage coupons" ON public.coupons;
DROP POLICY IF EXISTS "Users can view coupons" ON public.coupons;
DROP POLICY IF EXISTS "Public Select coupons" ON public.coupons;

-- New flexible policy for Management (Shop Owners, Staff, and Admins)
CREATE POLICY "Shop Manage coupons" ON public.coupons 
FOR ALL TO authenticated 
USING (
    shop_id::text IN (SELECT shop_id::text FROM public.users WHERE id = auth.uid()) 
    OR (SELECT role FROM public.users WHERE id = auth.uid()) IN ('admin', 'dono', 'business')
);

-- Public view policy (to allow customers to apply coupons)
CREATE POLICY "Public Select coupons" ON public.coupons 
FOR SELECT 
USING (true);


-- 2. Coupon Usage Table (Visibility for Shop Management)
ALTER TABLE public.coupon_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Shop View coupon usage" ON public.coupon_usage;

-- Allow shop management to view usages of their own coupons
CREATE POLICY "Shop View coupon usage" ON public.coupon_usage
FOR SELECT TO authenticated
USING (
    coupon_id IN (
        SELECT id FROM public.coupons 
        WHERE shop_id::text IN (SELECT shop_id::text FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) IN ('admin', 'dono', 'business')
    )
);

-- Keep existing user policies for coupon_usage if they exist, or recreate them to be safe
DROP POLICY IF EXISTS "Users can view own coupon usage" ON public.coupon_usage;
CREATE POLICY "Users can view own coupon usage" ON public.coupon_usage
    FOR SELECT TO authenticated
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authenticated users can insert coupon usage" ON public.coupon_usage;
CREATE POLICY "Authenticated users can insert coupon usage" ON public.coupon_usage
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);
