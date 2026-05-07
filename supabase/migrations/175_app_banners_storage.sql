-- 175_app_banners_storage.sql
-- Cria bucket público para imagens dos banners de marketing do admin

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'app-banners',
  'app-banners',
  true,
  2097152, -- 2 MB
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Leitura pública (qualquer pessoa pode ver as imagens)
CREATE POLICY "public_read_app_banners_storage"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'app-banners');

-- Apenas admin pode fazer upload
CREATE POLICY "admin_upload_app_banners_storage"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'app-banners' AND
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Apenas admin pode atualizar
CREATE POLICY "admin_update_app_banners_storage"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'app-banners' AND
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Apenas admin pode deletar
CREATE POLICY "admin_delete_app_banners_storage"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'app-banners' AND
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );
