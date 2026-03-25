-- 108_fix_users_and_appointments_columns.sql
-- Padronização de nomes e adição de colunas para Google Calendar, Fotos e Cupons

-- 1. Tabela public.users
DO $$ 
BEGIN 
    -- Adicionar photo_url se não existir
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='photo_url') THEN
        ALTER TABLE public.users ADD COLUMN photo_url TEXT;
    END IF;

    -- Adicionar google_calendar (jsonb) se não existir
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='google_calendar') THEN
        ALTER TABLE public.users ADD COLUMN google_calendar JSONB DEFAULT '{}'::jsonb;
    END IF;

    -- Migrar dados de googleCalendar (camelCase) para google_calendar (snake_case)
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='googleCalendar') THEN
        UPDATE public.users SET google_calendar = "googleCalendar" WHERE "googleCalendar" IS NOT NULL;
        ALTER TABLE public.users DROP COLUMN "googleCalendar";
    END IF;
END $$;

-- 2. Tabela public.appointments
DO $$ 
BEGIN 
    -- Adicionar colunas de cupons
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_applied') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_applied BOOLEAN DEFAULT false;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_code') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_code TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='coupon_discount_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN coupon_discount_percent NUMERIC DEFAULT 0;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='birthday_discount_applied') THEN
        ALTER TABLE public.appointments ADD COLUMN birthday_discount_applied BOOLEAN DEFAULT false;
    END IF;

    -- Padronização de nomes (total_price, paid_amount, remaining_amount, valor_com_desconto)
    
    -- total_price
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_price') THEN
        ALTER TABLE public.appointments ADD COLUMN total_price NUMERIC DEFAULT 0;
        -- Fallback de nomes antigos (vários legados possíveis)
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='total_value') THEN
            UPDATE public.appointments SET total_price = total_value;
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor_total') THEN
            UPDATE public.appointments SET total_price = valor_total;
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor') THEN
            UPDATE public.appointments SET total_price = valor;
        END IF;
    END IF;

    -- paid_amount
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='paid_amount') THEN
        ALTER TABLE public.appointments ADD COLUMN paid_amount NUMERIC DEFAULT 0;
        -- Fallback de nomes antigos
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor_pago') THEN
            UPDATE public.appointments SET paid_amount = valor_pago;
        END IF;
    END IF;

    -- remaining_amount
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='remaining_amount') THEN
        ALTER TABLE public.appointments ADD COLUMN remaining_amount NUMERIC DEFAULT 0;
        -- Fallback de nomes antigos
        IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='restante_a_pagar') THEN
            UPDATE public.appointments SET remaining_amount = restante_a_pagar;
        END IF;
    END IF;

    -- valor_com_desconto
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor_com_desconto') THEN
        ALTER TABLE public.appointments ADD COLUMN valor_com_desconto NUMERIC;
        UPDATE public.appointments SET valor_com_desconto = total_price;
    END IF;

END $$;
