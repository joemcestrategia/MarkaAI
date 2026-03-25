-- MARKA AI - Full Coupon System Setup
-- This script creates the tables AND enables Realtime

-- 1. Table: coupons
CREATE TABLE IF NOT EXISTS public.coupons (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id TEXT NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
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
    appointment_id TEXT, -- Usando TEXT para compatibilidade caso appointments também use TEXT
    used_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. RLS Policies
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_usage ENABLE ROW LEVEL SECURITY;

DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Shops can manage their own coupons" ON public.coupons;
    CREATE POLICY "Shops can manage their own coupons" ON public.coupons
        FOR ALL TO authenticated
        USING (shop_id IN (SELECT id FROM public.shops WHERE owner_id = auth.uid()));
EXCEPTION WHEN others THEN
    RAISE NOTICE 'Erro ao criar política coupons: %', SQLERRM;
END $$;

DO $$ 
BEGIN
    DROP POLICY IF EXISTS "Users can view coupons" ON public.coupons;
    CREATE POLICY "Users can view coupons" ON public.coupons
        FOR SELECT TO authenticated
        USING (true);
END $$;

-- 4. RPC for incrementing usage
CREATE OR REPLACE FUNCTION public.increment_coupon_usage(coupon_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE public.coupons
    SET usage_count = usage_count + 1
    WHERE id = coupon_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Enable Realtime
-- Nota: Pode falhar se já estiver na publicação, por isso usamos DO para tratar
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.coupons;
EXCEPTION WHEN others THEN
    RAISE NOTICE 'A tabela já está na publicação ou outro erro ocorreu: %', SQLERRM;
END $$;

ALTER TABLE public.coupons REPLICA IDENTITY FULL;
