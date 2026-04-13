-- =============================================================================
-- 146_focus_nfe_cleanup.sql
-- Limpa os campos antigos (Atende.Net / Padrão Nacional / ABRASF)
-- para uso exclusivo da Focus NFe na emissão de NFS-e (Conta Mestre)
-- =============================================================================

-- Remover colunas obsoletas da configuração fiscal
ALTER TABLE public.nfse_config
  DROP COLUMN IF EXISTS cert_pfx_base64,
  DROP COLUMN IF EXISTS cert_senha_hash,
  DROP COLUMN IF EXISTS provedor_nfse,
  DROP COLUMN IF EXISTS url_webservice,
  DROP COLUMN IF EXISTS usuario_prefeitura,
  DROP COLUMN IF EXISTS senha_prefeitura;

-- =============================================================================
-- Ajuste em nfse_emissoes (opcional, manter XML_DPS e XML_NFSE para fins de log,
-- mas podemos renomear para reuso na Focus se fizesse sentido. A Focus devolve PDF
-- url e o XML original, então vamos reaproveitar o campo xml_nfse ou deixá-lo nulo).
--
-- Mas a Focus precisa de uma referência. Vamos usar o proprio appointment_id
-- =============================================================================

-- O status retornado pela Focus é "processando", "autorizado", "cancelado", "erro"
-- Podemos atualizar o check constraint do status se necessário (já possui pendente, autorizada, rejeitada, cancelada)
ALTER TABLE public.nfse_emissoes DROP CONSTRAINT IF EXISTS nfse_emissoes_status_check;
ALTER TABLE public.nfse_emissoes ADD CONSTRAINT nfse_emissoes_status_check 
  CHECK (status IN ('pendente', 'processando', 'autorizada', 'rejeitada', 'cancelada'));

COMMENT ON TABLE public.nfse_config IS 'Configuração NFS-e via Focus NFe.';
