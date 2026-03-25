-- 102_create_favorites_table.sql
-- Tabela para salvar os favoritos dos clientes

CREATE TABLE IF NOT EXISTS public.favorites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    shop_id TEXT NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
    added_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, shop_id)
);

-- RLS Policies
ALTER TABLE public.favorites ENABLE ROW LEVEL SECURITY;

-- Usuários podem gerenciar seus próprios favoritos
DROP POLICY IF EXISTS "Users can manage their own favorites" ON public.favorites;
CREATE POLICY "Users can manage their own favorites" 
ON public.favorites 
FOR ALL TO authenticated 
USING (user_id = auth.uid());

-- Permitir leitura pública (opcional, mas comum para ver contagem de favoritos total)
DROP POLICY IF EXISTS "Favorites are viewable by everyone" ON public.favorites;
CREATE POLICY "Favorites are viewable by everyone" 
ON public.favorites 
FOR SELECT USING (true);
