-- 05_add_holiday_columns_to_shops.sql
-- Adiciona colunas necessárias para o sistema de feriados na tabela shops

-- 1. Adicionar colunas se não existirem
DO $$ 
BEGIN 
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='pending_holidays') THEN
        ALTER TABLE public.shops ADD COLUMN pending_holidays JSONB DEFAULT '[]'::jsonb;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='configured_holidays') THEN
        ALTER TABLE public.shops ADD COLUMN configured_holidays JSONB DEFAULT '{}'::jsonb;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='custom_holidays') THEN
        ALTER TABLE public.shops ADD COLUMN custom_holidays JSONB DEFAULT '[]'::jsonb;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='shops' AND column_name='config') THEN
        ALTER TABLE public.shops ADD COLUMN config JSONB DEFAULT '{"auto_block_holidays": false}'::jsonb;
    END IF;
END $$;

-- 2. Garantir que o RLS permita que os donos atualizem essas colunas
-- Normalmente o RLS de shops já permite update pelo owner_id.
-- Vamos garantir que os tipos de usuários autorizados possam gerenciar a loja.

DROP POLICY IF EXISTS "Shops are updatable by owners" ON public.shops;
CREATE POLICY "Shops are updatable by owners" ON public.shops
    FOR UPDATE TO authenticated
    USING (
        owner_id::text = auth.uid()::text 
        OR EXISTS (
            SELECT 1 FROM public.users 
            WHERE id = auth.uid() AND (role IN ('admin', 'dono', 'business'))
        )
    );
