-- 170_setup_products_table.sql
-- Garante que a tabela products existe com todas as colunas necessárias,
-- incluindo os novos campos: color, weight, description, sku, category.

-- 0. Garantir extensão para geração de UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Criar tabela products se não existir
CREATE TABLE IF NOT EXISTS public.products (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id     UUID NOT NULL,
    name        TEXT NOT NULL,
    price       NUMERIC DEFAULT 0,
    qty         INTEGER DEFAULT 0,
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 1b. Garantir DEFAULT no id (necessário se a tabela já existia sem DEFAULT)
ALTER TABLE public.products ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 2. Garantir coluna de quantidade: stock_quantity é o nome canônico.
--    Se a tabela tiver 'qty' mas não 'stock_quantity', adiciona stock_quantity.
--    Se a tabela tiver 'stock_quantity' mas não 'qty', adiciona qty para
--    compatibilidade com sales_page e purchases_page (legado).
DO $$
BEGIN
    -- id (chave primária — adicionada se não existir)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='id') THEN
        ALTER TABLE public.products ADD COLUMN id UUID DEFAULT gen_random_uuid();
        ALTER TABLE public.products ADD PRIMARY KEY (id);
    END IF;

    -- shop_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='shop_id') THEN
        ALTER TABLE public.products ADD COLUMN shop_id UUID;
    END IF;

    -- name
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='name') THEN
        ALTER TABLE public.products ADD COLUMN name TEXT;
    END IF;

    -- price
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='price') THEN
        ALTER TABLE public.products ADD COLUMN price NUMERIC DEFAULT 0;
    END IF;

    -- created_at
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='created_at') THEN
        ALTER TABLE public.products ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Garantir stock_quantity (coluna principal — usada pelo app)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='stock_quantity') THEN
        ALTER TABLE public.products ADD COLUMN stock_quantity INTEGER DEFAULT 0;
    END IF;

    -- Garantir qty (coluna legada — usada por sales_page e purchases_page)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='qty') THEN
        ALTER TABLE public.products ADD COLUMN qty INTEGER DEFAULT 0;
        -- Sincronizar valor inicial de qty a partir de stock_quantity
        UPDATE public.products SET qty = stock_quantity WHERE qty = 0 AND stock_quantity > 0;
    END IF;

    -- description
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='description') THEN
        ALTER TABLE public.products ADD COLUMN description TEXT;
    END IF;

    -- sku (código do produto)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='sku') THEN
        ALTER TABLE public.products ADD COLUMN sku TEXT;
    END IF;

    -- category
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='category') THEN
        ALTER TABLE public.products ADD COLUMN category TEXT;
    END IF;

    -- color (cor do produto)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='color') THEN
        ALTER TABLE public.products ADD COLUMN color TEXT;
    END IF;

    -- weight (peso/volume numérico)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='weight') THEN
        ALTER TABLE public.products ADD COLUMN weight NUMERIC;
    END IF;

    -- weight_unit (unidade: 'g', 'kg', 'ml', 'L')
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='weight_unit') THEN
        ALTER TABLE public.products ADD COLUMN weight_unit TEXT DEFAULT 'g';
    END IF;

    -- is_active
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='is_active') THEN
        ALTER TABLE public.products ADD COLUMN is_active BOOLEAN DEFAULT true;
    END IF;

    -- updated_at
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='updated_at') THEN
        ALTER TABLE public.products ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- 2b. Trigger para manter qty e stock_quantity sincronizados automaticamente
CREATE OR REPLACE FUNCTION public.sync_product_quantity()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        -- Usa o maior valor entre os dois para garantir consistência
        IF COALESCE(NEW.stock_quantity, 0) >= COALESCE(NEW.qty, 0) THEN
            NEW.qty := COALESCE(NEW.stock_quantity, 0);
        ELSE
            NEW.stock_quantity := COALESCE(NEW.qty, 0);
        END IF;
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.stock_quantity IS DISTINCT FROM OLD.stock_quantity THEN
            NEW.qty := NEW.stock_quantity;
        ELSIF NEW.qty IS DISTINCT FROM OLD.qty THEN
            NEW.stock_quantity := NEW.qty;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS sync_product_qty_trigger ON public.products;
CREATE TRIGGER sync_product_qty_trigger
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.sync_product_quantity();

-- 3. Trigger de updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_updated_at_products ON public.products;
CREATE TRIGGER set_updated_at_products
    BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 4. RLS (idempotente)
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public Select products" ON public.products;
CREATE POLICY "Public Select products" ON public.products
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Shop Manage products" ON public.products;
CREATE POLICY "Shop Manage products" ON public.products
    FOR ALL TO authenticated
    USING (
        shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid())
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

-- 5. Índices
CREATE INDEX IF NOT EXISTS idx_products_shop_id ON public.products(shop_id);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON public.products(is_active);
