-- 99_add_social_columns_to_shops.sql
-- Adiciona colunas para TikTok e YouTube na tabela shops

DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='tiktok') THEN
        ALTER TABLE public.shops ADD COLUMN tiktok TEXT;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='youtube') THEN
        ALTER TABLE public.shops ADD COLUMN youtube TEXT;
    END IF;
END $$;
