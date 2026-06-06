-- 183_fix_signup_regression.sql
-- ============================================================
-- CORREÇÃO: Regressão introduzida pela migration 20260423_fix_role_reset_on_oauth.sql
--
-- PROBLEMA 1: O trigger handle_new_user() passou a inserir role='cliente'
--             hardcoded, ignorando o metadata do signup. Isso quebrou o
--             cadastro de novos donos de loja.
--
-- PROBLEMA 2: A policy users_update_own_profile impede o upsert pós-signup
--             de corrigir o role, porque o WITH CHECK compara o role
--             enviado com o role atual (que já é 'cliente' por causa do trigger).
--
-- PROBLEMA 3: O trigger perdeu os campos de endereço, birth_date, verified
--             e photo_url que existiam na versão da migration 160.
--
-- SOLUÇÃO: Restaurar a leitura de role do metadata para NOVOS usuários,
--          mantendo a proteção de não sobrescrever role em ON CONFLICT
--          (fix do OAuth preservado).
-- ============================================================

-- ══════════════════════════════════════════════════════════════
-- 1. Corrigir trigger handle_new_user()
-- ══════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (
    id,
    name,
    email,
    role,
    shop_id,
    plan,
    phone,
    zip_code,
    street,
    neighborhood,
    city,
    state,
    number,
    birth_date,
    verified,
    photo_url,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    COALESCE(
      NULLIF(TRIM(NEW.raw_user_meta_data->>'name'), ''),
      NULLIF(TRIM(NEW.raw_user_meta_data->>'full_name'), ''),
      INITCAP(SPLIT_PART(NEW.email, '@', 1))
    ),
    NEW.email,
    -- Lê o role do metadata (dono, cliente, business) — default 'cliente'
    COALESCE(NEW.raw_user_meta_data->>'role', 'cliente'),
    NULLIF(NEW.raw_user_meta_data->>'shop_id', ''),
    COALESCE(NEW.raw_user_meta_data->>'plan', 'free'),
    NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'zip_code',
    NEW.raw_user_meta_data->>'street',
    NEW.raw_user_meta_data->>'neighborhood',
    NEW.raw_user_meta_data->>'city',
    NEW.raw_user_meta_data->>'state',
    NEW.raw_user_meta_data->>'number',
    NULLIF(NEW.raw_user_meta_data->>'birth_date', '')::DATE,
    COALESCE((NEW.raw_user_meta_data->>'verified')::boolean, false),
    COALESCE(
      NEW.raw_user_meta_data->>'avatar_url',
      NEW.raw_user_meta_data->>'picture'
    ),
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    -- Atualiza nome (preserva existente se novo for vazio)
    name = CASE
      WHEN EXCLUDED.name IS NOT NULL AND EXCLUDED.name != ''
      THEN EXCLUDED.name
      ELSE public.users.name
    END,
    email = COALESCE(EXCLUDED.email, public.users.email),
    -- ⚠️ ROLE JAMAIS É ALTERADO para usuários existentes (fix OAuth preservado)
    -- role permanece intacto — apenas o INSERT inicial define o role correto
    photo_url = COALESCE(public.users.photo_url, EXCLUDED.photo_url),
    updated_at = now();
  RETURN NEW;
END;
$$;

-- ══════════════════════════════════════════════════════════════
-- 2. Ajustar policy de UPDATE para permitir upsert pós-signup
--    Mantém a proteção contra mudança de role via client.
-- ══════════════════════════════════════════════════════════════

-- A policy existente bloqueia o upsert quando o Flutter envia role='dono'
-- mas o trigger já inseriu role='cliente'. Agora que o trigger insere o role
-- correto, o upsert do Flutter enviará o MESMO role — então o WITH CHECK passa.
-- Mas como segurança extra, removemos a exigência de role no WITH CHECK
-- e protegemos o role de outra forma: o upsert do Flutter já envia o role
-- correto, e o ON CONFLICT do trigger não muda role.

DROP POLICY IF EXISTS "users_update_own_profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS "Allow users to update own data" ON public.users;

-- Policy de UPDATE: usuário só pode atualizar o próprio registro
-- O role é protegido pelo fato de que o trigger ON CONFLICT não o altera,
-- e esta policy impede qualquer alteração de role via client.
CREATE POLICY "users_update_own_profile"
ON public.users
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id
  AND role = (SELECT role FROM public.users WHERE id = auth.uid())
);

-- Policy de INSERT: necessária para o upsert direto pós-signup
DROP POLICY IF EXISTS "Users can insert own profile" ON public.users;
CREATE POLICY "Users can insert own profile" ON public.users
    FOR INSERT WITH CHECK (auth.uid() = id);

-- ══════════════════════════════════════════════════════════════
-- 3. Backfill: Corrigir registros de donos que ficaram como 'cliente'
--    Identificamos pela presença de metadata 'role' = 'dono' no auth.users
--    mas role = 'cliente' na public.users.
-- ══════════════════════════════════════════════════════════════
UPDATE public.users u
SET 
  role = au.raw_user_meta_data->>'role',
  updated_at = now()
FROM auth.users au
WHERE u.id = au.id
  AND u.role = 'cliente'
  AND au.raw_user_meta_data->>'role' IN ('dono', 'business')
  AND u.shop_id IS NULL;

-- ══════════════════════════════════════════════════════════════
-- VERIFICAÇÃO PÓS-MIGRATION
-- ══════════════════════════════════════════════════════════════
-- Confirmar que o trigger foi atualizado
-- SELECT prosrc FROM pg_proc WHERE proname = 'handle_new_user';

-- Confirmar policies de UPDATE
-- SELECT policyname, cmd, qual, with_check
-- FROM pg_policies
-- WHERE tablename = 'users' AND schemaname = 'public';
