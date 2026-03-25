-- 00_auth_schema.sql
-- Plano de Migração MarkaAI: Estrutura de Perfis e Sincronização

-- 1. Tabela de Perfis (Extensão de auth.users) -- RENOMEADA PARA users para bater com o Flutter
CREATE TABLE IF NOT EXISTS public.users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    nome TEXT,
    email TEXT,
    telefone TEXT,
    documento TEXT,
    tipo TEXT CHECK (tipo IN ('admin', 'dono', 'business', 'funcionario', 'cliente')) DEFAULT 'cliente',
    shop_id UUID, -- Link para o shopId
    plano TEXT DEFAULT 'free',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Habilitar RLS
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

-- Politicas
CREATE POLICY "Users are viewable by everyone" ON public.users
    FOR SELECT USING (true);

CREATE POLICY "Users can update their own profile" ON public.users
    FOR UPDATE USING (auth.uid() = id);

-- 2. Trigger para Sincronização Automática (Auth -> users)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (
        id, 
        nome, 
        email, 
        tipo, 
        shop_id, 
        plano,
        telefone
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'role', 'cliente'),
        (NEW.raw_user_meta_data->>'establishment_id')::UUID,
        COALESCE(NEW.raw_user_meta_data->>'plano', 'free'),
        NEW.raw_user_meta_data->>'phone'
    )
    ON CONFLICT (id) DO UPDATE SET
        nome = EXCLUDED.nome,
        tipo = EXCLUDED.tipo,
        shop_id = EXCLUDED.shop_id,
        plano = EXCLUDED.plano,
        telefone = EXCLUDED.telefone,
        updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger disparado no INSERT em auth.users
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 3. Índices para performance multi-tenant
CREATE INDEX IF NOT EXISTS idx_users_shop ON public.users(shop_id);
CREATE INDEX IF NOT EXISTS idx_users_tipo ON public.users(tipo);
