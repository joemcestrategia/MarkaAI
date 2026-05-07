-- 171_create_inventory_tables.sql
-- Garante que as tabelas de vendas, compras e movimentações existam com
-- as colunas corretas (snake_case) e RLS básico.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── SALES ───────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.sales (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id    UUID NOT NULL,
    items      JSONB DEFAULT '[]',
    total      NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Shop Manage sales" ON public.sales;
CREATE POLICY "Shop Manage sales" ON public.sales
    FOR ALL TO authenticated
    USING (
        shop_id::text IN (SELECT shop_id FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

CREATE INDEX IF NOT EXISTS idx_sales_shop_id ON public.sales(shop_id);

-- ─── PURCHASES ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.purchases (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id    UUID NOT NULL,
    items      JSONB DEFAULT '[]',
    total      NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Shop Manage purchases" ON public.purchases;
CREATE POLICY "Shop Manage purchases" ON public.purchases
    FOR ALL TO authenticated
    USING (
        shop_id::text IN (SELECT shop_id FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

CREATE INDEX IF NOT EXISTS idx_purchases_shop_id ON public.purchases(shop_id);

-- ─── STOCK MOVEMENTS ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.stock_movements (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id    UUID NOT NULL,
    product_id UUID,
    type       TEXT,   -- 'sale' | 'purchase' | 'adjustment'
    delta      INTEGER DEFAULT 0,
    ref_id     UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Shop Manage stock_movements" ON public.stock_movements;
CREATE POLICY "Shop Manage stock_movements" ON public.stock_movements
    FOR ALL TO authenticated
    USING (
        shop_id::text IN (SELECT shop_id FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

CREATE INDEX IF NOT EXISTS idx_stock_movements_shop_id   ON public.stock_movements(shop_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON public.stock_movements(product_id);
