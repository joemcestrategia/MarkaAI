-- 172_fix_inventory_constraints.sql
-- Corrige a constraint de tipo em stock_movements e garante tabela sales.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── 1. Garantir tabela sales (caso migration 171 ainda não foi aplicada) ────
CREATE TABLE IF NOT EXISTS public.sales (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id    UUID NOT NULL,
    items      JSONB DEFAULT '[]',
    total      NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.sales ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Shop Manage sales" ON public.sales;
CREATE POLICY "Shop Manage sales" ON public.sales
    FOR ALL TO authenticated
    USING (
        shop_id::text IN (SELECT shop_id FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

CREATE INDEX IF NOT EXISTS idx_sales_shop_id ON public.sales(shop_id);

-- ─── 2. Garantir tabela purchases ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.purchases (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id    UUID NOT NULL,
    items      JSONB DEFAULT '[]',
    total      NUMERIC DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.purchases ALTER COLUMN id SET DEFAULT gen_random_uuid();
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Shop Manage purchases 2" ON public.purchases;
CREATE POLICY "Shop Manage purchases 2" ON public.purchases
    FOR ALL TO authenticated
    USING (
        shop_id::text IN (SELECT shop_id FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

CREATE INDEX IF NOT EXISTS idx_purchases_shop_id ON public.purchases(shop_id);

-- ─── 3. Corrigir constraint de tipo em stock_movements ────────────────────────
-- Remove a constraint antiga (que rejeita 'sale' e 'purchase')
ALTER TABLE IF EXISTS public.stock_movements
    DROP CONSTRAINT IF EXISTS stock_movements_type_check;

-- Garante tabela stock_movements com os campos corretos (caso não exista)
CREATE TABLE IF NOT EXISTS public.stock_movements (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id    UUID NOT NULL,
    product_id UUID,
    type       TEXT,
    delta      INTEGER DEFAULT 0,
    ref_id     UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.stock_movements ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Adiciona colunas que podem estar faltando
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='stock_movements' AND column_name='product_id') THEN
        ALTER TABLE public.stock_movements ADD COLUMN product_id UUID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='stock_movements' AND column_name='ref_id') THEN
        ALTER TABLE public.stock_movements ADD COLUMN ref_id UUID;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='stock_movements' AND column_name='delta') THEN
        ALTER TABLE public.stock_movements ADD COLUMN delta INTEGER DEFAULT 0;
    END IF;
END $$;

-- Nova constraint permissiva com todos os tipos usados pelo app
ALTER TABLE public.stock_movements
    ADD CONSTRAINT stock_movements_type_check
    CHECK (type IN ('sale', 'purchase', 'adjustment', 'in', 'out', 'manual'));

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Shop Manage stock_movements 2" ON public.stock_movements;
CREATE POLICY "Shop Manage stock_movements 2" ON public.stock_movements
    FOR ALL TO authenticated
    USING (
        shop_id::text IN (SELECT shop_id FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

CREATE INDEX IF NOT EXISTS idx_stock_movements_shop_id    ON public.stock_movements(shop_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON public.stock_movements(product_id);
