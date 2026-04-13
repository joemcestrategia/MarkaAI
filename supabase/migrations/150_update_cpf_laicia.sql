-- Registrar a NFS-e nº 1 que foi emitida manualmente em 09/04/2026 para Laicia
-- Isso garante que o sistema saiba que a nota já foi emitida

-- 1. Registrar a emissão da nota nº 1 (emitida manualmente no portal)
INSERT INTO public.nfse_emissoes (
  shop_id,
  appointment_id,
  status,
  numero_nfse,
  codigo_verificacao,
  valor_servico,
  tomador_nome,
  xml_nfse,
  motivo_rejeicao,
  created_at
) VALUES (
  '290d91b6-7519-4856-96dc-bcda3fd3b9f9',
  '183883fd-f287-4ae9-b524-257b1fdd7f33',
  'autorizada',
  '1',
  '4637090426232340600410274092026047397142',
  450.00,
  'LAICIA FERNANDA DE ARAUJO',
  'Emitida manualmente no portal nfse-itabirito.atende.net em 09/04/2026 23:23',
  NULL,
  '2026-04-09 23:23:40-03'
)
ON CONFLICT DO NOTHING;

-- 2. Atualizar CPF da cliente no agendamento
UPDATE public.appointments
SET client_user_cpf = '12549013611'
WHERE id = '183883fd-f287-4ae9-b524-257b1fdd7f33';

-- 3. Atualizar os códigos corretos na configuração NFS-e baseados na nota real
-- (confirmados via XML da nota nº 1 emitida com sucesso em Itabirito)
UPDATE public.nfse_config
SET 
  codigo_servico_lc116       = '60101',          -- código real no sistema IPM de Itabirito
  codigo_tributacao_municipio = '960250100',      -- CNAE completo (9 dígitos)
  codigo_nbs                 = '1.2602.10.00',   -- NBS com pontos (convertemos para sem pontos ao enviar)
  aliquota_iss               = 2.01,             -- alíquota real confirmada: 2,0100%
  proximo_numero_rps         = 2                 -- próxima nota será a nº 2
WHERE shop_id = '290d91b6-7519-4856-96dc-bcda3fd3b9f9';
