-- 186_add_affiliate_columns_to_products.sql

DO $$
BEGIN
    -- image_url
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='image_url') THEN
        ALTER TABLE public.products ADD COLUMN image_url TEXT;
    END IF;

    -- is_affiliate
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='is_affiliate') THEN
        ALTER TABLE public.products ADD COLUMN is_affiliate BOOLEAN DEFAULT false;
    END IF;

    -- affiliate_url
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='products' AND column_name='affiliate_url') THEN
        ALTER TABLE public.products ADD COLUMN affiliate_url TEXT;
    END IF;
END $$;
