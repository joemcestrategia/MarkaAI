-- 125_create_shop_clients.sql
-- Cria tabelas para metadados de clientes por loja e visualizações (leads)

-- 1. Tabela shop_views (Garantir existência)
CREATE TABLE IF NOT EXISTS public.shop_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    shop_id TEXT REFERENCES public.shops(id) ON DELETE CASCADE,
    viewed_at TIMESTAMPTZ DEFAULT now()
);

-- 2. Tabela shop_clients (Tags manuais e classificação customizada)
CREATE TABLE IF NOT EXISTS public.shop_clients (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    shop_id TEXT REFERENCES public.shops(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    manual_tags TEXT[] DEFAULT '{}',
    classification TEXT,
    classification_override BOOLEAN DEFAULT false,
    notes TEXT,
    nome TEXT, -- Cópia para busca rápida/histórico
    telefone TEXT, -- Cópia para busca rápida/histórico
    last_updated TIMESTAMPTZ DEFAULT now(),
    UNIQUE(shop_id, user_id)
);

-- Ativar RLS
ALTER TABLE public.shop_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shop_clients ENABLE ROW LEVEL SECURITY;

-- Políticas shop_views
DROP POLICY IF EXISTS "Shop owners can see views for their shop" ON public.shop_views;
CREATE POLICY "Shop owners can see views for their shop" ON public.shop_views
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.shops
            WHERE shops.id = shop_views.shop_id
            AND shops.owner_id = auth.uid()::text
        )
    );

DROP POLICY IF EXISTS "Authenticated users can insert views" ON public.shop_views;
CREATE POLICY "Authenticated users can insert views" ON public.shop_views
    FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Políticas shop_clients
DROP POLICY IF EXISTS "Shop owners can manage their shop clients" ON public.shop_clients;
CREATE POLICY "Shop owners can manage their shop clients" ON public.shop_clients
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM public.shops
            WHERE shops.id = shop_clients.shop_id
            AND shops.owner_id = auth.uid()::text
        )
    );

-- Índices de performance
CREATE INDEX IF NOT EXISTS idx_shop_clients_shop_user ON public.shop_clients(shop_id, user_id);
CREATE INDEX IF NOT EXISTS idx_shop_views_shop_id ON public.shop_views(shop_id);
