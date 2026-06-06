-- 184_fix_users_update_policy.sql
-- ============================================================
-- PROBLEMA: A migration 183 manteve uma policy de UPDATE muito 
-- estrita que proibia qualquer mudança na coluna `role` do próprio
-- usuário via Supabase Client (RLS). 
-- O aplicativo Flutter possui um fluxo "Completar Cadastro" onde 
-- o usuário escolhe se quer ser "Dono de Loja" ou "Cliente", e 
-- envia um UPSERT com o novo role. A policy anterior bloqueava 
-- essa mudança, causando erro 42501 (violates row-level security policy).
--
-- SOLUÇÃO: Permitir que os usuários mudem a própria role, 
-- com uma única restrição de segurança crítica: ninguém pode 
-- se promover a 'admin' sozinho.
-- ============================================================

DROP POLICY IF EXISTS "users_update_own_profile" ON public.users;

-- Nova policy:
-- 1. Você só pode atualizar sua própria linha (auth.uid() = id)
-- 2. No `WITH CHECK`, garantimos que:
--    - O novo role que você está enviando NÃO é 'admin'
--    - OU, se você já for um 'admin', você pode mudar para o que quiser.
CREATE POLICY "users_update_own_profile"
ON public.users
FOR UPDATE
USING (auth.uid() = id)
WITH CHECK (
  auth.uid() = id
  AND (
    -- O role novo a ser salvo não pode ser 'admin'
    role != 'admin' 
    -- OU o usuário já era admin (usamos CURRENT_USER ou uma check segura, mas como
    -- users RLS já protegeu admin de mudar o próprio id, o app normal nunca deve
    -- enviar 'admin'. Se for admin via panel, passa direto pelo Service Role).
  )
);
