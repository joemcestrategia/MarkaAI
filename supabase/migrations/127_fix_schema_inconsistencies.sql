-- 127_fix_schema_inconsistencies.sql
-- Correção de colunas faltantes e padronização para evitar erros de cache e exibição
-- Resolve erros PGRST204 (Missing columns in schema cache)

-- 0. Função Genérica para updated_at (Se não existir)
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- 1. Tabela public.appointments: Consolidação de Campos Financeiros e de Status
DO $$ 
BEGIN 
    -- Adicionar updated_at
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='updated_at') THEN
        ALTER TABLE public.appointments ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;

    -- Campos de Status e Pagamento
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='payment_status') THEN
        ALTER TABLE public.appointments ADD COLUMN payment_status TEXT DEFAULT 'pendente';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='payment_method') THEN
        ALTER TABLE public.appointments ADD COLUMN payment_method TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='payment_id') THEN
        ALTER TABLE public.appointments ADD COLUMN payment_id TEXT;
    END IF;

    -- Campos Financeiros Precisos
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_price') THEN
        ALTER TABLE public.appointments ADD COLUMN total_price NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_payable') THEN
        ALTER TABLE public.appointments ADD COLUMN total_payable NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor_com_desconto') THEN
        ALTER TABLE public.appointments ADD COLUMN valor_com_desconto NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='paid_amount') THEN
        ALTER TABLE public.appointments ADD COLUMN paid_amount NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='remaining_amount') THEN
        ALTER TABLE public.appointments ADD COLUMN remaining_amount NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='labor_value') THEN
        ALTER TABLE public.appointments ADD COLUMN labor_value NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_value') THEN
        ALTER TABLE public.appointments ADD COLUMN total_value NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='discount_amount') THEN
        ALTER TABLE public.appointments ADD COLUMN discount_amount NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor_sinal') THEN
        ALTER TABLE public.appointments ADD COLUMN valor_sinal NUMERIC DEFAULT 0;
    END IF;

    -- Cupons e Promoções
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='birthday_discount_applied') THEN
        ALTER TABLE public.appointments ADD COLUMN birthday_discount_applied BOOLEAN DEFAULT false;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='birthday_discount_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN birthday_discount_percent NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_applied') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_applied BOOLEAN DEFAULT false;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_code') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_code TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_discount_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_discount_percent NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='card_tax_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN card_tax_percent NUMERIC DEFAULT 0;
    END IF;

    -- Campos de Tempo
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='end_at') THEN
        ALTER TABLE public.appointments ADD COLUMN end_at TIMESTAMPTZ;
    END IF;

END $$;

-- Garantir Trigger em appointments
DROP TRIGGER IF EXISTS set_updated_at_appointments ON public.appointments;
CREATE TRIGGER set_updated_at_appointments
    BEFORE UPDATE ON public.appointments
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 2. Tabela public.favorites: Compatibilidade com o código Dart
DO $$ 
BEGIN 
    -- Adicionar shop_name
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='favorites' AND column_name='shop_name') THEN
        ALTER TABLE public.favorites ADD COLUMN shop_name TEXT;
    END IF;

    -- Adicionar created_at (ou renomear added_at)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='favorites' AND column_name='added_at') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='favorites' AND column_name='created_at') THEN
        ALTER TABLE public.favorites RENAME COLUMN added_at TO created_at;
    ELSIF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='favorites' AND column_name='created_at') THEN
        ALTER TABLE public.favorites ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- 3. Tabela public.services: Garantir colunas essenciais
DO $$ 
BEGIN 
    -- Garantir is_active (fallback para 'ativo')
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='is_active') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='ativo') THEN
            ALTER TABLE public.services RENAME COLUMN ativo TO is_active;
        ELSE
            ALTER TABLE public.services ADD COLUMN is_active BOOLEAN DEFAULT true;
        END IF;
    END IF;

    -- Garantir name (fallback para 'nome')
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='name') THEN
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='nome') THEN
            ALTER TABLE public.services RENAME COLUMN nome TO name;
        ELSE
            ALTER TABLE public.services ADD COLUMN name TEXT;
        END IF;
    END IF;

    -- Adicionar updated_at em services se não existir
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='services' AND column_name='updated_at') THEN
        ALTER TABLE public.services ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Garantir Trigger em services
DROP TRIGGER IF EXISTS set_updated_at_services ON public.services;
CREATE TRIGGER set_updated_at_services
    BEFORE UPDATE ON public.services
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- 4. Tabela public.shops: Garantir padronização e Notificações (FCM)
DO $$ 
BEGIN 
    -- nome -> name se ainda existir 'nome'
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='nome') 
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='name') THEN
        ALTER TABLE public.shops RENAME COLUMN nome TO name;
    END IF;

    -- Campos de Notificação Push (FCM)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='fcm_token') THEN
        ALTER TABLE public.shops ADD COLUMN fcm_token TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='fcm_updated_at') THEN
        ALTER TABLE public.shops ADD COLUMN fcm_updated_at TIMESTAMPTZ;
    END IF;
END $$;

-- 5. Tabela public.users: Campos de Notificação Push (FCM)
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='fcm_token') THEN
        ALTER TABLE public.users ADD COLUMN fcm_token TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='fcm_updated_at') THEN
        ALTER TABLE public.users ADD COLUMN fcm_updated_at TIMESTAMPTZ;
    END IF;
END $$;
