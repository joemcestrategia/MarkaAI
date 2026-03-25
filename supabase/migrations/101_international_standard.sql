-- Migração Global: Padronização Internacional (Inglês)

-- ════════════════════════════════════════
-- 1. Tabela public.users
-- ════════════════════════════════════════
DO $$ 
BEGIN 
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='nome') THEN
        ALTER TABLE public.users RENAME COLUMN nome TO name;
    END IF;
END $$;

-- Atualizar Trigger handle_new_user para usar 'name'
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (
        id, 
        name, -- Alterado de nome
        email, 
        tipo, 
        shop_id, 
        plano,
        telefone
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'role', 'cliente'),
        (NEW.raw_user_meta_data->>'establishment_id')::UUID,
        COALESCE(NEW.raw_user_meta_data->>'plano', 'free'),
        NEW.raw_user_meta_data->>'phone'
    )
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name, -- Alterado de nome
        tipo = EXCLUDED.tipo,
        shop_id = EXCLUDED.shop_id,
        plano = EXCLUDED.plano,
        telefone = EXCLUDED.telefone,
        updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ════════════════════════════════════════
-- 2. Tabela public.services
-- ════════════════════════════════════════
DO $$ 
BEGIN 
    -- nome -> name
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='nome') THEN
        ALTER TABLE public.services RENAME COLUMN nome TO name;
    END IF;
    
    -- preco -> price
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='preco') THEN
        ALTER TABLE public.services RENAME COLUMN preco TO price;
    END IF;

    -- tempo_min -> duration_min
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='tempo_min') THEN
        ALTER TABLE public.services RENAME COLUMN tempo_min TO duration_min;
    END IF;

    -- descricao -> description
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='descricao') THEN
        ALTER TABLE public.services RENAME COLUMN descricao TO description;
    END IF;

    -- ativo -> is_active
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='ativo') THEN
        ALTER TABLE public.services RENAME COLUMN ativo TO is_active;
    END IF;

    -- fotos_urls -> photos_urls
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='fotos_urls') THEN
        ALTER TABLE public.services RENAME COLUMN fotos_urls TO photos_urls;
    END IF;

    -- shopId -> shop_id (Standardizing snake_case)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='shopId') THEN
        ALTER TABLE public.services RENAME COLUMN "shopId" TO shop_id;
    END IF;
END $$;
