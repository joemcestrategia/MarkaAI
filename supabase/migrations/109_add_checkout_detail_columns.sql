-- 109_add_checkout_detail_columns.sql
-- Adiciona colunas de detalhamento do checkout nos agendamentos
-- e padroniza coluna phone na tabela users

-- 1. Colunas de detalhamento do checkout em appointments
DO $$ 
BEGIN 
    -- birthday_discount_percent: armazena a porcentagem do desconto de aniversário aplicado
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='birthday_discount_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN birthday_discount_percent NUMERIC DEFAULT 0;
    END IF;

    -- card_tax_percent: armazena a porcentagem da taxa de cartão aplicada
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='card_tax_percent') THEN
        ALTER TABLE public.appointments ADD COLUMN card_tax_percent NUMERIC DEFAULT 0;
    END IF;

    -- valor_sinal: garante que existe (pode já ter sido criado)
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='appointments' AND column_name='valor_sinal') THEN
        ALTER TABLE public.appointments ADD COLUMN valor_sinal NUMERIC DEFAULT 0;
    END IF;
END $$;

-- 2. Padronização: garante coluna phone na tabela users (renomeia telefone se existir)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='telefone')
       AND NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='phone') THEN
        ALTER TABLE public.users RENAME COLUMN telefone TO phone;
    ELSIF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='users' AND column_name='phone') THEN
        ALTER TABLE public.users ADD COLUMN phone TEXT;
    END IF;
END $$;
