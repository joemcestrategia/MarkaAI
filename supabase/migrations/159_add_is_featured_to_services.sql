-- Migration 159: Adiciona coluna is_featured na tabela services
-- Permite que o dono da loja marque serviços específicos para aparecer
-- na seção "Destaques da Vitrine" em vez de exibir todos com fotos.

ALTER TABLE services
  ADD COLUMN IF NOT EXISTS is_featured BOOLEAN NOT NULL DEFAULT FALSE;

-- Índice para facilitar a query de destaques por loja
CREATE INDEX IF NOT EXISTS idx_services_shop_featured
  ON services (shop_id, is_featured)
  WHERE is_featured = TRUE;

COMMENT ON COLUMN services.is_featured IS
  'Quando TRUE, o serviço aparece na seção Destaques da Vitrine da loja.';
