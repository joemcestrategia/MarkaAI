-- 149_restore_municipal_nfse_columns.sql
-- Restaura os campos para integração direta municipal Assinada
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS cert_pfx_base64 TEXT,
  ADD COLUMN IF NOT EXISTS cert_senha_hash TEXT,
  ADD COLUMN IF NOT EXISTS provedor_nfse TEXT DEFAULT 'atende.net',
  ADD COLUMN IF NOT EXISTS url_webservice TEXT,
  ADD COLUMN IF NOT EXISTS usuario_prefeitura TEXT,
  ADD COLUMN IF NOT EXISTS senha_prefeitura TEXT;

COMMENT ON COLUMN public.nfse_config.cert_pfx_base64 IS 'Certificado A1 .pfx em Base64.';
COMMENT ON COLUMN public.nfse_config.cert_senha_hash IS 'Senha do certificado PFX.';
