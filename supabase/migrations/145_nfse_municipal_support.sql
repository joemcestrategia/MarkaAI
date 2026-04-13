-- =============================================================================
-- 145_nfse_municipal_support.sql
-- Suporte a sistemas municipais de NFS-e (IPM REST / ABRASF 2.4)
-- + Campos obrigatórios Reforma Tributária 2026 (NBS, descontos)
-- =============================================================================

-- ── Provedor de emissão ───────────────────────────────────────────────────────
-- 'nacional'  → api.nfse.gov.br  (padrão Sefin — DPS XML)
-- 'abrasf_24' → WebService SOAP ABRASF 2.4  (maioria das prefeituras municipais)
-- 'ipm_rest'  → API REST IPM  (prefeituras que usam o sistema IPM)
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS provedor_nfse TEXT NOT NULL DEFAULT 'nacional'
    CHECK (provedor_nfse IN ('nacional', 'abrasf_24', 'ipm_rest'));

-- ── URL do WebService municipal (obrigatório para abrasf_24 / ipm_rest) ───────
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS url_webservice TEXT;

-- ── Código NBS — obrigatório a partir de 01/01/2026 ──────────────────────────
-- Nomenclatura Brasileira de Serviços, ex: '01040001' (cabeleireiros)
-- Ref: https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS codigo_nbs TEXT;

-- ── Credenciais portal municipal (IPM / outros que exigem autenticação) ───────
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS usuario_prefeitura TEXT;

ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS senha_prefeitura TEXT;

-- ── Código de tributação municipal (diferente do LC 116 em alguns municípios) ─
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS codigo_tributacao_municipio TEXT;

-- ── Descontos (Reforma Tributária 2026) ──────────────────────────────────────
-- Desconto incondicional: reduz a base de cálculo antes do ISS
-- Desconto condicional: não reduz base mas pode ser informado
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS desconto_incondicional NUMERIC(10,2) NOT NULL DEFAULT 0;

ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS desconto_condicional NUMERIC(10,2) NOT NULL DEFAULT 0;

-- ── Exigibilidade ISS (padrão ABRASF 2.4) ────────────────────────────────────
-- 1=Exigível, 2=Não Incidência, 3=Isenção, 4=Exportação, 5=Imunidade,
-- 6=Exig.Susp.Judicial, 7=Exig.Susp.Adm
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS exigibilidade_iss INT NOT NULL DEFAULT 1;

-- ── Incentivador cultural ─────────────────────────────────────────────────────
ALTER TABLE public.nfse_config
  ADD COLUMN IF NOT EXISTS incentivador_cultural BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN public.nfse_config.provedor_nfse IS
  'nacional=api.nfse.gov.br | abrasf_24=SOAP ABRASF 2.4 | ipm_rest=REST IPM';
COMMENT ON COLUMN public.nfse_config.url_webservice IS
  'URL base do WebService municipal (ex: https://nfse.prefeitura.sp.gov.br/ws)';
COMMENT ON COLUMN public.nfse_config.codigo_nbs IS
  'Código NBS (Nomenclatura Brasileira de Serviços). Obrigatório a partir 01/01/2026. Ex: 01040001';
COMMENT ON COLUMN public.nfse_config.codigo_tributacao_municipio IS
  'Código de tributação no município (pode diferir do LC 116). Ex: 0709';
COMMENT ON COLUMN public.nfse_config.exigibilidade_iss IS
  '1=Exigível | 2=Não Incidência | 3=Isenção | 4=Exportação | 5=Imunidade | 6=Susp.Judicial | 7=Susp.Adm';

-- ── Correção RLS (Módulos Baseados no `public.users`) ──────────────
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
