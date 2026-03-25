-- 104_add_google_business_to_shops.sql
-- Adiciona suporte para vinculação com Google Meu Negócio

DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='shops' AND column_name='google_business') THEN
        ALTER TABLE public.shops ADD COLUMN google_business JSONB;
    END IF;
END $$;
