-- 128_sync_services_data_and_schema.sql
-- Objetivo: Garantir colunas em inglês e snake_case (shop_id) em todas as tabelas críticas.

DO $$ 
DECLARE
    t TEXT;
BEGIN 
    -- 1. Padronizar shopId -> shop_id em TODAS as tabelas conhecidas
    FOR t IN SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_name IN ('services', 'categories', 'employees', 'products', 'appointments', 'financial_transactions', 'bank_accounts', 'purchases', 'stock_movements', 'coupons', 'favorites', 'shops', 'users')
    LOOP
        -- Se shopId existe (camelCase)
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='shopId') THEN
            -- Se shop_id não existe, renomeia
            IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='shop_id') THEN
                EXECUTE format('ALTER TABLE public.%I RENAME COLUMN "shopId" TO shop_id', t);
            ELSE
                -- Se ambos existem, migra dados e mantém shop_id
                EXECUTE format('UPDATE public.%I SET shop_id = "shopId" WHERE shop_id IS NULL', t);
            END IF;
        END IF;
    END LOOP;

    -- 2. Saneamento específico da tabela SERVICES
    -- nome -> name
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='name') THEN
        ALTER TABLE public.services ADD COLUMN name TEXT;
    END IF;
    UPDATE public.services SET name = nome WHERE name IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='nome');

    -- preco -> price
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='price') THEN
        ALTER TABLE public.services ADD COLUMN price NUMERIC DEFAULT 0;
    END IF;
    UPDATE public.services SET price = preco WHERE price IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='preco');

    -- tempo_min -> duration_min
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='duration_min') THEN
        ALTER TABLE public.services ADD COLUMN duration_min INTEGER DEFAULT 30;
    END IF;
    UPDATE public.services SET duration_min = tempo_min WHERE duration_min IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='tempo_min');

    -- descricao -> description
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='description') THEN
        ALTER TABLE public.services ADD COLUMN description TEXT;
    END IF;
    UPDATE public.services SET description = descricao WHERE description IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='descricao');

    -- ativo -> is_active
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='is_active') THEN
        ALTER TABLE public.services ADD COLUMN is_active BOOLEAN DEFAULT true;
    END IF;
    UPDATE public.services SET is_active = ativo WHERE is_active IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='ativo');

    -- fotos_urls -> photos_urls
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='photos_urls') THEN
        ALTER TABLE public.services ADD COLUMN photos_urls TEXT[] DEFAULT '{}';
    END IF;
    UPDATE public.services SET photos_urls = fotos_urls WHERE photos_urls IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='fotos_urls');

    -- 3. Saneamento da tabela CATEGORIES
    -- nome -> name
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='categories' AND column_name='name') THEN
        ALTER TABLE public.categories ADD COLUMN name TEXT;
    END IF;
    UPDATE public.categories SET name = nome WHERE name IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='categories' AND column_name='nome');

    -- ativo -> is_active
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='categories' AND column_name='is_active') THEN
        ALTER TABLE public.categories ADD COLUMN is_active BOOLEAN DEFAULT true;
    END IF;
    UPDATE public.categories SET is_active = ativo WHERE is_active IS NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='categories' AND column_name='ativo');

END $$;

-- Garantir RLS para leitura pública em tabelas críticas
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select services" ON public.services;
CREATE POLICY "Public Select services" ON public.services FOR SELECT USING (true);

ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public Select categories" ON public.categories;
CREATE POLICY "Public Select categories" ON public.categories FOR SELECT USING (true);

-- Ativar Realtime para as tabelas principais
ALTER PUBLICATION supabase_realtime ADD TABLE public.services;
ALTER PUBLICATION supabase_realtime ADD TABLE public.categories;
EXCEPTION WHEN OTHERS THEN NULL; -- Ignora se já estiver na publicação
