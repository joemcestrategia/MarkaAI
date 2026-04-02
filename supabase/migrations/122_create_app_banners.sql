-- 122_create_app_banners.sql
-- Tabela de banners promocionais do MarkaAI (editável via painel admin)

CREATE TABLE IF NOT EXISTS public.app_banners (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  title       text NOT NULL DEFAULT 'MarkaAI',
  subtitle    text NOT NULL DEFAULT '',
  image_url   text NOT NULL DEFAULT '',
  cta_text    text NOT NULL DEFAULT 'Saiba mais',
  cta_url     text NOT NULL DEFAULT 'https://markaai.com.br',
  is_active   boolean NOT NULL DEFAULT true,
  sort_order  int NOT NULL DEFAULT 0,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.app_banners ENABLE ROW LEVEL SECURITY;

-- Qualquer usuário autenticado (ou anônimo) pode ler banners ativos
CREATE POLICY "read_active_banners"
  ON public.app_banners FOR SELECT
  USING (is_active = true);

-- Apenas a service role (admin) pode inserir/atualizar/deletar
CREATE POLICY "admin_manage_banners"
  ON public.app_banners FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Banner inicial do MarkaAI
INSERT INTO public.app_banners (title, subtitle, cta_text, cta_url, is_active, sort_order)
VALUES (
  'MarkaAI',
  'Agende serviços de beleza com facilidade e sem complicação',
  'Conhecer',
  'https://markaai.com.br',
  true,
  0
) ON CONFLICT DO NOTHING;
