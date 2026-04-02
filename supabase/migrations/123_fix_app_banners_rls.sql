-- 123_fix_app_banners_rls.sql
-- Corrige políticas RLS da tabela app_banners para permitir que
-- usuários autenticados com role='admin' gerenciem os banners via painel admin.

-- Remove políticas anteriores
DROP POLICY IF EXISTS "read_active_banners" ON public.app_banners;
DROP POLICY IF EXISTS "admin_manage_banners" ON public.app_banners;

-- Leitura: usuários autenticados veem todos; anônimos veem apenas ativos
CREATE POLICY "anon_read_active_banners"
  ON public.app_banners FOR SELECT
  TO anon
  USING (is_active = true);

CREATE POLICY "auth_read_all_banners"
  ON public.app_banners FOR SELECT
  TO authenticated
  USING (true);

-- Escrita completa: apenas usuários com role='admin' na tabela users
CREATE POLICY "admin_insert_banners"
  ON public.app_banners FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "admin_update_banners"
  ON public.app_banners FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "admin_delete_banners"
  ON public.app_banners FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
