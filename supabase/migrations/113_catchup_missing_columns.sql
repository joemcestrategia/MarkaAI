-- 113_catchup_missing_columns.sql
-- Consolidação de migrations que não foram registradas no remoto (00-112, exceto 110)

-- 1. Tabela public.coupons: Adicionar service_ids
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='coupons' AND column_name='service_ids') THEN
        ALTER TABLE public.coupons ADD COLUMN service_ids UUID[] DEFAULT NULL;
        COMMENT ON COLUMN public.coupons.service_ids IS 'List of service UUIDs that this coupon applies to. If NULL or empty, applies to all services.';
    END IF;
END $$;

-- 2. Tabela public.users: photo_url, google_calendar e phone
DO $$ 
BEGIN 
    -- photo_url
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='photo_url') THEN
        ALTER TABLE public.users ADD COLUMN photo_url TEXT;
    END IF;

    -- google_calendar
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='google_calendar') THEN
        ALTER TABLE public.users ADD COLUMN google_calendar JSONB DEFAULT '{}'::jsonb;
    END IF;

    -- phone (padronização)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='telefone')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='phone') THEN
        ALTER TABLE public.users RENAME COLUMN telefone TO phone;
    ELSIF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='phone') THEN
        ALTER TABLE public.users ADD COLUMN phone TEXT;
    END IF;
END $$;

-- 3. Tabela public.appointments: cupons, checkout details e payment_id
DO $$ 
BEGIN 
    -- coupon columns
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_applied') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_applied BOOLEAN DEFAULT false;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_code') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_code TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_discount_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_discount_percent NUMERIC DEFAULT 0;
    END IF;

    -- checkout detail columns
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='birthday_discount_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN birthday_discount_percent NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='card_tax_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN card_tax_percent NUMERIC DEFAULT 0;
    END IF;

    -- payment_id
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='payment_id') THEN
        ALTER TABLE public.appointments ADD COLUMN payment_id TEXT;
    END IF;
    
    -- total_price e campos legados
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_price') THEN
        ALTER TABLE public.appointments ADD COLUMN total_price NUMERIC DEFAULT 0;
    END IF;
END $$;

-- 4. Correção do default ID em appointments
DO $$ 
BEGIN
    ALTER TABLE public.appointments ALTER COLUMN id SET DEFAULT gen_random_uuid();
EXCEPTION WHEN OTHERS THEN
    -- Ignorar se a alteração falhar por já ser o padrão ou restrições
END $$;
