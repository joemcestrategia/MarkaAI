-- Migration: Suporte a emissão automática de NFS-e para pagamentos online (cartão/pix)
-- Distinto de emitir_automatico_dinheiro (que é para pagamentos presenciais em dinheiro)
-- Aplicada quando webhook do Mercado Pago confirma pagamento aprovado
ALTER TABLE nfse_config
  ADD COLUMN IF NOT EXISTS emitir_automatico_cartao BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN nfse_config.emitir_automatico_cartao IS
  'Quando true, emite NFS-e automaticamente ao receber webhook de pagamento aprovado (Mercado Pago). Não se aplica a pagamentos em dinheiro ou pessoalmente. Exclusivo para plano Pro.';
