-- =============================================================================
-- 144_create_nfse_tables.sql
-- Módulo NFS-e (Nota Fiscal de Serviço Eletrônica — Padrão Nacional)
--
-- ATENÇÃO: shop_id e appointment_id são TEXT neste projeto (não UUID),
-- compatível com public.shops(id) e public.appointments(id).
-- RLS usa shops.owner_id = auth.uid()::text (sem tabela user_profiles).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. Função utilitária updated_at (idempotente — pode já existir)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- 1. TABELA: nfse_config
-- Configuração fiscal por tenant (shop). Uma linha por shop.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.nfse_config (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Vínculo com o tenant (TEXT, igual ao PK de public.shops)
  shop_id                     TEXT NOT NULL UNIQUE REFERENCES public.shops(id) ON DELETE CASCADE,

  -- Dados do prestador de serviço
  cnpj                        TEXT NOT NULL,
  inscricao_municipal         TEXT,
  codigo_municipio            TEXT NOT NULL,   -- IBGE 7 dígitos, ex: '3550308'
  codigo_servico_lc116        TEXT NOT NULL,   -- ex: '7.09' (cabeleireiros/similares)
  aliquota_iss                NUMERIC(5,4) NOT NULL DEFAULT 0.05, -- ex: 0.0500 = 5 %
  regime_tributario           INT  NOT NULL DEFAULT 1,
    -- 1 = Simples Nacional
    -- 2 = Simples Nacional – Excesso de Sublimite
    -- 3 = Regime Normal (Lucro Presumido / Real)
    -- 4 = Simples Nacional – MEI

  -- Certificado digital A1 (armazenado criptografado)
  cert_pfx_base64             TEXT,   -- conteúdo .pfx em Base64 (criptografar antes de salvar)
  cert_senha_hash             TEXT,   -- senha do cert (criptografada com Vault / env secret)

  -- Controle de ambiente e emissão automática
  ambiente                    TEXT NOT NULL DEFAULT 'homologacao'
    CHECK (ambiente IN ('homologacao', 'producao')),
  emitir_automatico_dinheiro  BOOLEAN NOT NULL DEFAULT false,
    -- se false → pagamentos em Dinheiro ficam na fila manual de emissão
  ativo                       BOOLEAN NOT NULL DEFAULT false,

  created_at                  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Trigger updated_at
DROP TRIGGER IF EXISTS set_updated_at_nfse_config ON public.nfse_config;
CREATE TRIGGER set_updated_at_nfse_config
  BEFORE UPDATE ON public.nfse_config
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Índice de busca rápida por shop
CREATE INDEX IF NOT EXISTS idx_nfse_config_shop_id ON public.nfse_config (shop_id);

-- RLS: dono da loja gerencia sua própria configuração
ALTER TABLE public.nfse_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "nfse_config_shop_owner" ON public.nfse_config;
DROP POLICY IF EXISTS "nfse_config_shop_staff" ON public.nfse_config;
CREATE POLICY "nfse_config_shop_staff" ON public.nfse_config
    FOR ALL TO authenticated
    USING (
        shop_id IN (
            SELECT shop_id FROM public.users WHERE id = auth.uid()
        )
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    )
    WITH CHECK (
        shop_id IN (
            SELECT shop_id FROM public.users WHERE id = auth.uid()
        )
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

-- Edge Functions (service_role) precisam ler/escrever sem RLS
DROP POLICY IF EXISTS "nfse_config_service_role" ON public.nfse_config;
CREATE POLICY "nfse_config_service_role" ON public.nfse_config
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE  public.nfse_config IS 'Configuração fiscal NFS-e por tenant (shop). Uma linha por shop.';
COMMENT ON COLUMN public.nfse_config.aliquota_iss IS 'Alíquota ISS em decimal: 0.0500 = 5%.';
COMMENT ON COLUMN public.nfse_config.cert_pfx_base64 IS 'Certificado A1 .pfx em Base64. Deve ser criptografado antes de persistir.';
COMMENT ON COLUMN public.nfse_config.emitir_automatico_dinheiro IS 'Se false, agendamentos pagos em Dinheiro não geram NFS-e automaticamente.';

-- =============================================================================
-- 2. TABELA: nfse_emissoes
-- Registro de cada tentativa/emissão de nota fiscal.
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.nfse_emissoes (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Vínculos (TEXT, igual aos PKs de public.shops e public.appointments)
  shop_id             TEXT        NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  appointment_id      TEXT        REFERENCES public.appointments(id) ON DELETE SET NULL,

  -- Dados da nota retornada pela Sefin
  numero_nfse         TEXT,
  chave_acesso        TEXT,
  codigo_verificacao  TEXT,

  -- Ciclo de vida
  status              TEXT        NOT NULL DEFAULT 'pendente'
    CHECK (status IN ('pendente', 'autorizada', 'rejeitada', 'cancelada')),

  -- Valores
  valor_servico       NUMERIC(10,2) NOT NULL DEFAULT 0,

  -- Tomador (cliente)
  tomador_cpf_cnpj    TEXT,
  tomador_nome        TEXT,

  -- Payloads XML (para auditoria / reprocessamento)
  xml_dps             TEXT,   -- XML da DPS enviado à Sefin
  xml_nfse            TEXT,   -- XML de retorno da Sefin

  -- DANFSe
  pdf_url             TEXT,

  -- Diagnóstico de erros
  motivo_rejeicao     TEXT,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Trigger updated_at
DROP TRIGGER IF EXISTS set_updated_at_nfse_emissoes ON public.nfse_emissoes;
CREATE TRIGGER set_updated_at_nfse_emissoes
  BEFORE UPDATE ON public.nfse_emissoes
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Índices de performance
CREATE INDEX IF NOT EXISTS idx_nfse_emissoes_shop_id        ON public.nfse_emissoes (shop_id);
CREATE INDEX IF NOT EXISTS idx_nfse_emissoes_appointment_id ON public.nfse_emissoes (appointment_id);
CREATE INDEX IF NOT EXISTS idx_nfse_emissoes_status         ON public.nfse_emissoes (status);
CREATE INDEX IF NOT EXISTS idx_nfse_emissoes_chave_acesso   ON public.nfse_emissoes (chave_acesso);

-- Garante que cada agendamento gere no máximo 1 nota autorizada
CREATE UNIQUE INDEX IF NOT EXISTS uniq_nfse_emissoes_autorizada_per_appointment
  ON public.nfse_emissoes (appointment_id)
  WHERE status = 'autorizada' AND appointment_id IS NOT NULL;

-- RLS: dono da loja vê suas próprias notas
ALTER TABLE public.nfse_emissoes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "nfse_emissoes_shop_owner" ON public.nfse_emissoes;
DROP POLICY IF EXISTS "nfse_emissoes_shop_staff" ON public.nfse_emissoes;
CREATE POLICY "nfse_emissoes_shop_staff" ON public.nfse_emissoes
    FOR ALL TO authenticated
    USING (
        shop_id IN (
            SELECT shop_id FROM public.users WHERE id = auth.uid()
        )
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    )
    WITH CHECK (
        shop_id IN (
            SELECT shop_id FROM public.users WHERE id = auth.uid()
        )
        OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
    );

-- Edge Functions (service_role) lêem/escrevem sem restrição
DROP POLICY IF EXISTS "nfse_emissoes_service_role" ON public.nfse_emissoes;
CREATE POLICY "nfse_emissoes_service_role" ON public.nfse_emissoes
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

COMMENT ON TABLE  public.nfse_emissoes IS 'Histórico de emissões/tentativas de NFS-e por agendamento.';
COMMENT ON COLUMN public.nfse_emissoes.status IS 'pendente | autorizada | rejeitada | cancelada';
COMMENT ON COLUMN public.nfse_emissoes.xml_dps IS 'XML da DPS (Declaração de Prestação de Serviços) assinado e enviado à Sefin.';
COMMENT ON COLUMN public.nfse_emissoes.xml_nfse IS 'XML de retorno da Sefin com a NFS-e autorizada.';
