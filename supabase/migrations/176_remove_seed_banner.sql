-- 176_remove_seed_banner.sql
-- Remove o banner inicial (seed) inserido automaticamente pela migration 122.
-- A partir de agora todos os banners são gerenciados exclusivamente pelo painel admin.

DELETE FROM public.app_banners
WHERE title = 'MarkaAI'
  AND cta_url = 'https://markaai.com.br'
  AND sort_order = 0;
