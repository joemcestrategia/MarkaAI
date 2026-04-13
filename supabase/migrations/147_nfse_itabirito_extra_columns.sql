-- 147_nfse_itabirito_extra_columns.sql
-- Adiciona colunas para tornar a emissão municipal 100% dinâmica e automática
ALTER TABLE public.nfse_config 
  ADD COLUMN IF NOT EXISTS serie_rps TEXT DEFAULT 'A',
  ADD COLUMN IF NOT EXISTS proximo_numero_rps BIGINT DEFAULT 1;

COMMENT ON COLUMN public.nfse_config.serie_rps IS 'Série do RPS (ex: A, 1, NF)';
COMMENT ON COLUMN public.nfse_config.proximo_numero_rps IS 'Próximo número de RPS a ser emitido para este shop.';

-- Função para incrementar o RPS de forma atômica via Edge Function
CREATE OR REPLACE FUNCTION public.incrementar_rps(shop_id_param TEXT)
RETURNS VOID AS $$
BEGIN
  UPDATE public.nfse_config
  SET proximo_numero_rps = COALESCE(proximo_numero_rps, 1) + 1
  WHERE shop_id = shop_id_param;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
