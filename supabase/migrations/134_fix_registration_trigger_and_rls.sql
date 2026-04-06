-- 134_fix_registration_trigger_and_rls.sql
-- CORREÇÃO CIRÚRGICA dos dois bugs de cadastro de usuários:
--
-- BUG 2: O trigger handle_new_user estava usando nomes de colunas antigos
-- (tipo, plano, telefone) que foram renomeados em migrations anteriores
-- (101, 113) para (role, plan, phone). Isso causava o erro:
--   {"code":"unexpected_failure","message":"Database error saving new user"}
--
-- ADICIONALMENTE: Adiciona política de INSERT na tabela public.users para
-- permitir que o upsert feito pelo Flutter logo após o signUp() funcione.

-- ══════════════════════════════════════════════════════════════════════════
-- 1. Atualizar trigger handle_new_user com nomes de colunas corretos
-- ══════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.users (
        id,
        name,     -- renomeado de 'nome' na migration 101
        email,
        role,     -- renomeado de 'tipo' em migrations posteriores
        shop_id,
        plan,     -- renomeado de 'plano' em migrations posteriores
        phone     -- renomeado de 'telefone' na migration 113
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'name', NEW.email),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'role', 'cliente'),
        NULLIF(NEW.raw_user_meta_data->>'shop_id', ''),
        COALESCE(NEW.raw_user_meta_data->>'plan', 'free'),
        NEW.raw_user_meta_data->>'phone'
    )
    ON CONFLICT (id) DO UPDATE SET
        name       = EXCLUDED.name,
        role       = EXCLUDED.role,
        shop_id    = EXCLUDED.shop_id,
        plan       = EXCLUDED.plan,
        phone      = EXCLUDED.phone,
        updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Garantir que o trigger ainda está ativado (caso tenha sido dropado por alguma migration)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ══════════════════════════════════════════════════════════════════════════
-- 2. Adicionar política de INSERT para usuários autenticados
--    (necessário para o upsert direto feito pelo Flutter após signUp)
-- ══════════════════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
CREATE POLICY "Users can insert own profile" ON public.users
    FOR INSERT WITH CHECK (auth.uid() = id);
