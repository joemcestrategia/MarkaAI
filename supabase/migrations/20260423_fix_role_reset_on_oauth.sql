-- ============================================================
-- FIX 1: Corrigir trigger handle_new_user()
-- Problema: ON CONFLICT sobrescreve role com 'cliente'
-- Solução: nunca tocar no role em usuários existentes
-- ============================================================

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
    phone,
    zip_code,
    role,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      ''
    ),
    NEW.email,
    NEW.raw_user_meta_data->>'phone',
    NEW.raw_user_meta_data->>'zip_code',
    'cliente',
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    -- Atualiza apenas dados não sensíveis de perfil
    name = CASE
      WHEN EXCLUDED.name IS NOT NULL AND EXCLUDED.name != ''
      THEN EXCLUDED.name
      ELSE public.users.name
    END,
    email = COALESCE(EXCLUDED.email, public.users.email),
    updated_at = now()
    -- ROLE JAMAIS É ATUALIZADO AQUI
    -- role permanece intacto para usuários existentes
  ;
  RETURN NEW;
END;
$$;

-- ============================================================
-- FIX 2: Proteger coluna role via WITH CHECK nas policies
-- Problema: policies de UPDATE sem WITH CHECK permitem
--           qualquer alteração incluindo role
-- Solução: garantir que role nunca mude via client
-- ============================================================

-- Remover policies de UPDATE existentes que não têm WITH CHECK
DROP POLICY IF EXISTS "Allow users to update own data" ON public.users;
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
DROP POLICY IF EXISTS "Users can update their own profile" ON public.users;

-- Recriar com WITH CHECK que trava o role
CREATE POLICY "users_update_own_profile"
ON public.users
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id
  AND role = (SELECT role FROM public.users WHERE id = auth.uid())
);

-- ============================================================
-- VERIFICAÇÃO PÓS-MIGRATION
-- ============================================================

-- Confirmar que o trigger foi atualizado
SELECT prosrc FROM pg_proc WHERE proname = 'handle_new_user';

-- Confirmar as novas policies
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'users'
  AND schemaname = 'public'
  AND cmd = 'UPDATE';
