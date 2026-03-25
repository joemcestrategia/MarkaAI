-- 105_fix_shops_and_birthday_discount.sql
-- Adiciona colunas faltantes na tabela shops e implementa controle de desconto de aniversário

-- 1. Tabelas de Configuração da Loja (Shops)
DO $$ 
BEGIN 
    -- notification_settings
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='notification_settings') THEN
        ALTER TABLE public.shops ADD COLUMN notification_settings JSONB DEFAULT '{"send_reminders": true, "default_reminder_days": 1}'::jsonb;
    END IF;

    -- mercadopago
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='mercadopago') THEN
        ALTER TABLE public.shops ADD COLUMN mercadopago JSONB DEFAULT '{}'::jsonb;
    END IF;

    -- mp_access_token
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='mp_access_token') THEN
        ALTER TABLE public.shops ADD COLUMN mp_access_token TEXT;
    END IF;
END $$;

-- 2. Controle de Desconto no Client (Users)
DO $$ 
BEGIN 
    -- birthday_locked
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='birthday_locked') THEN
        ALTER TABLE public.users ADD COLUMN birthday_locked BOOLEAN DEFAULT false;
    END IF;

    -- last_birthday_discount_year
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='last_birthday_discount_year') THEN
        ALTER TABLE public.users ADD COLUMN last_birthday_discount_year INTEGER;
    END IF;
END $$;

-- 3. Controle no Agendamento (Appointments)
DO $$ 
BEGIN 
    -- birthday_discount_applied
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='birthday_discount_applied') THEN
        ALTER TABLE public.appointments ADD COLUMN birthday_discount_applied BOOLEAN DEFAULT false;
    END IF;
END $$;

-- 4. Tabela de Categorias (Categories)
DO $$ 
BEGIN 
    -- ordem
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='categories' AND column_name='ordem') THEN
        ALTER TABLE public.categories ADD COLUMN ordem INTEGER DEFAULT 0;
    END IF;
END $$;

-- 5. Tabela de Registro de Uso de Desconto (Anti-fraude)
CREATE TABLE IF NOT EXISTS public.birthday_discount_registry (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id TEXT REFERENCES public.shops(id) ON DELETE CASCADE,
    identifier TEXT NOT NULL, -- e.g., 'email_xxx' ou 'phone_xxx'
    year INTEGER NOT NULL,
    user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    used_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(shop_id, identifier, year)
);

-- Ativar RLS
ALTER TABLE public.birthday_discount_registry ENABLE ROW LEVEL SECURITY;

-- Políticas de RLS para birthday_discount_registry
DROP POLICY IF EXISTS "Allow select for owners" ON public.birthday_discount_registry;
CREATE POLICY "Allow select for owners" ON public.birthday_discount_registry
    FOR SELECT TO authenticated
    USING (
        EXISTS (
            SELECT 1 FROM public.shops 
            WHERE id = birthday_discount_registry.shop_id AND owner_id = auth.uid()::text
        )
    );

DROP POLICY IF EXISTS "Allow insert for clients" ON public.birthday_discount_registry;
CREATE POLICY "Allow insert for clients" ON public.birthday_discount_registry
    FOR INSERT TO authenticated
    WITH CHECK (auth.uid() = user_id);

-- 6. Garantir que as colunas novas em shops sejam editáveis
-- (Políticas existentes em shops geralmente já cobrem isso via owner_id)
