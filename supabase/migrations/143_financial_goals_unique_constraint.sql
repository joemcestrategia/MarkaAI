# CONTEXTO DO SISTEMA
Você está trabalhando no projeto MarkaAI (C:\src\MarkaAI), um SaaS multi-tenant de agendamento para salões e barbearias, construído com Flutter (frontend) e Supabase (backend). O projeto usa Edge Functions (Deno/TypeScript) para lógica server-side.

# OBJETIVO
Implementar emissão automática de NFS-e (Nota Fiscal de Serviço Eletrônica) no padrão nacional, usando a API oficial gratuita do governo federal: https://api.nfse.gov.br — sem nenhum intermediário pago.

# RESTRIÇÃO ABSOLUTA DE ESCOPO
- Toque SOMENTE nos arquivos listados nesta tarefa
- Não refatore nem mova código existente
- Não altere nenhuma tela de agendamento, clientes ou financeiro já existente
- Se encontrar código relacionado mas fora do escopo, NÃO mexa — apenas documente o que seria necessário ajustar futuramente

---

# ARQUITETURA ESPERADA

## 1. Supabase — nova tabela `nfse_emissoes`
Crie via migration SQL a tabela:
```sql
create table nfse_emissoes (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references shops(id),
  appointment_id uuid references appointments(id),
  numero_nfse text,
  chave_acesso text,
  status text not null default 'pendente', -- pendente | autorizada | rejeitada | cancelada
  valor_servico numeric(10,2) not null,
  tomador_cpf_cnpj text,
  tomador_nome text,
  xml_dps text,
  xml_nfse text,
  pdf_url text,
  codigo_verificacao text,
  motivo_rejeicao text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- RLS: cada shop só vê suas próprias notas
alter table nfse_emissoes enable row level security;
create policy "shop_owner_nfse" on nfse_emissoes
  using (shop_id = (select shop_id from user_profiles where id = auth.uid()));
```

## 2. Supabase — nova tabela `nfse_config`
Configuração fiscal por tenant (shop):
```sql
create table nfse_config (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null unique references shops(id),
  cnpj text not null,
  inscricao_municipal text,
  codigo_municipio text not null, -- IBGE 7 dígitos
  codigo_servico_lc116 text not null, -- ex: "7.09" para cabeleireiros
  aliquota_iss numeric(5,4) not null, -- ex: 0.0500 = 5%
  regime_tributario int not null default 1, -- 1=simples, 3=normal
  cert_pfx_base64 text, -- certificado A1 criptografado
  cert_senha_hash text, -- senha do cert (criptografada com chave do Vault)
  ambiente text not null default 'homologacao', -- homologacao | producao
  ativo boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table nfse_config enable row level security;
create policy "shop_owner_nfse_config" on nfse_config
  using (shop_id = (select shop_id from user_profiles where id = auth.uid()));
```

## 3. Supabase Edge Function — `emitir-nfse`
Crie o arquivo: `supabase/functions/emitir-nfse/index.ts`

### Responsabilidades desta função:
1. Receber `{ appointment_id, shop_id }` no body
2. Buscar dados do agendamento (valor, cliente, serviço)
3. Buscar configuração fiscal do shop em `nfse_config`
4. Descriptografar o certificado A1 (usando Supabase Vault ou variável de ambiente)
5. Montar o XML da DPS (Declaração de Prestação de Serviços) no padrão nacional
6. Assinar o XML com o certificado digital (usar biblioteca `node-forge` ou equivalente Deno)
7. Enviar via POST para `https://api.nfse.gov.br/v1/nfse` (produção) ou `https://api.producaorestrita.nfse.gov.br/v1/nfse` (homologação)
8. Processar retorno: extrair `chaveAcesso`, `numeroNFSe`, `codigoVerificacao`
9. Salvar resultado na tabela `nfse_emissoes`
10. Retornar `{ success: true, chave_acesso, numero_nfse, pdf_url }`

### Estrutura mínima do XML DPS (padrão nacional):
```xml
<DPS xmlns="http://www.sped.fazenda.gov.br/nfse">
  <infDPS Id="DPS{codigoMunicipio}{tipoInscricao}{cnpj14}{serie}{numero}">
    <tpAmb>{1=producao|2=homologacao}</tpAmb>
    <dhEmi>{ISO8601}</dhEmi>
    <verAplic>1.00</verAplic>
    <serie>1</serie>
    <nDPS>{numero sequencial}</nDPS>
    <dCompet>{YYYY-MM-DD}</dCompet>
    <prest>
      <CNPJ>{cnpj_prestador}</CNPJ>
      <IM>{inscricao_municipal}</IM>
      <CRT>{regime_tributario}</CRT>
    </prest>
    <toma>
      <CPF>{cpf_tomador ou 00000000000 se consumidor}</CPF>
      <xNome>{nome_tomador}</xNome>
    </toma>
    <serv>
      <cServ>
        <cTribNac>{codigo NBS equivalente ao LC116}</cTribNac>
        <cTribMun>{codigo_servico_municipal}</cTribMun>
        <xDescServ>{descricao do servico realizado}</xDescServ>
      </cServ>
      <vServPrest>
        <vReceb>{valor_total}</vReceb>
      </vServPrest>
      <vDeducRed>0</vDeducRed>
      <tribut>
        <tribMun>
          <tribISSQN>1</tribISSQN>
          <pAliq>{aliquota_iss}</pAliq>
        </tribMun>
      </tribut>
    </serv>
  </infDPS>
</DPS>
```

### Assinatura digital (padrão xmldsig):
- Usar `SignedInfo` com algoritmo `rsa-sha256`
- Referenciar `Id` do `infDPS` com URI `#DPS...`
- Canonicalização: `http://www.w3.org/TR/2001/REC-xml-c14n-20010315`
- Assinar com a chave privada do certificado A1

### Autenticação na API da Sefin:
- mTLS: apresentar o certificado do prestador na conexão TLS
- Header: `Content-Type: application/xml`
- Endpoint produção: `POST https://api.nfse.gov.br/v1/nfse`
- Endpoint homologação: `POST https://api.producaorestrita.nfse.gov.br/v1/nfse`
- Swagger oficial: `https://www.nfse.gov.br/swagger/contribuintesissqn/`

## 4. Supabase Edge Function — `cancelar-nfse`
Crie o arquivo: `supabase/functions/cancelar-nfse/index.ts`

Responsabilidades:
1. Receber `{ nfse_id, motivo }`
2. Montar XML do Pedido de Cancelamento com `chaveAcesso`
3. Enviar para `POST https://api.nfse.gov.br/v1/nfse/{chaveAcesso}/cancelamento`
4. Atualizar status para `cancelada` na tabela `nfse_emissoes`

## 5. Flutter — Serviço `NfseService`
Crie o arquivo: `lib/services/nfse_service.dart`
```dart
class NfseService {
  // Emite nota após conclusão de agendamento
  Future<NfseResult> emitirNota({
    required String appointmentId,
    required String shopId,
  });

  // Cancela uma nota emitida
  Future<void> cancelarNota(String nfseId, String motivo);

  // Busca histórico de notas do shop
  Future<List<NfseEmissao>> listarNotas(String shopId);

  // Verifica se o shop tem configuração fiscal ativa
  Future<bool> configuracaoAtiva(String shopId);
}
```

### Regras de negócio no Flutter:
- A emissão deve ser OPCIONAL — nunca bloquear o fluxo de agendamento se falhar
- Chamar `emitirNota` apenas quando o agendamento for marcado como `concluido`
- Exibir toast de sucesso com número da nota, ou toast de aviso (não erro crítico) se falhar
- Salvar `nfse_id` no registro de agendamento para rastreio

## 6. Flutter — Tela de Configuração Fiscal
Crie o arquivo: `lib/screens/fiscal/nfse_config_screen.dart`

Campos necessários:
- CNPJ do estabelecimento (com máscara)
- Inscrição Municipal
- Código IBGE do município (com busca por nome usando BrasilAPI)
- Código de serviço LC 116 (ex: 7.09 — cabeleireiros e similares)
- Alíquota ISS (%)
- Regime tributário (Simples Nacional / Lucro Presumido / Lucro Real)
- Upload do certificado .pfx (A1)
- Senha do certificado
- Toggle ambiente: Homologação / Produção
- Botão "Testar conexão" — emite DPS de teste no ambiente de homologação

## 7. Flutter — Tela de Histórico de NFS-e
Crie o arquivo: `lib/screens/fiscal/nfse_historico_screen.dart`

Exibir lista de notas emitidas com:
- Número da nota
- Data/hora
- Nome do tomador
- Valor
- Status (badge colorido)
- Botão "Baixar PDF" (abre URL do DANFSe)
- Botão "Cancelar" (apenas para notas autorizadas com menos de 24h)

---

# FLUXO COMPLETO DE EMISSÃO (referência)

1. Agendamento marcado como `concluido` no app
2. Flutter chama `NfseService.emitirNota(appointmentId, shopId)`
3. NfseService chama a Edge Function `emitir-nfse` via POST
4. Edge Function monta e assina o XML DPS
5. Edge Function faz mTLS POST para `api.nfse.gov.br/v1/nfse`
6. Sefin valida e retorna `chaveAcesso` + `numeroNFSe`
7. Edge Function salva resultado na tabela `nfse_emissoes`
8. Flutter recebe resposta e exibe toast de sucesso

---

# IMPORTANTE — LIMITAÇÕES DO PADRÃO NACIONAL
- **Cobertura**: funciona apenas para municípios que aderiram ao padrão nacional. Para municípios não aderentes, o sistema deve informar ao usuário que a nota deve ser emitida manualmente pelo portal da prefeitura.
- **Verificar adesão do município**: usar `GET https://api.nfse.gov.br/v1/parametros_municipais/{codigoMunicipio}` — se retornar 404, o município ainda não aderiu.
- **MEI**: usa o mesmo endpoint mas a autenticação pode ser feita com conta gov.br nível Prata/Ouro em vez de certificado digital.
- **Rejeições comuns**: alíquota inválida para o município, inscrição municipal incorreta, certificado expirado — tratar cada código de erro da Sefin com mensagem amigável ao usuário.

---

# CHECKLIST DE ENTREGA
- [ ] Migration SQL criada e documentada
- [ ] Edge Function `emitir-nfse` funcional em homologação
- [ ] Edge Function `cancelar-nfse` funcional
- [ ] `NfseService` no Flutter com tratamento de erro não-bloqueante
- [ ] Tela de configuração fiscal com teste de conexão
- [ ] Tela de histórico com download de PDF
- [ ] Verificação de adesão municipal antes de tentar emitir
- [ ] Nenhum arquivo fora do escopo modificado

# ENTREGUE PRIMEIRO: apenas a migration SQL e a estrutura de pastas. Aguarde confirmação antes de implementar as Edge Functions.