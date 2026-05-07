class LegalDocuments {
  static const String privacyPolicy = '''
# POLÍTICA DE PRIVACIDADE

**Data de vigência:** 04 de Maio de 2026  
**Última atualização:** 04 de Maio de 2026

## 1. INTRODUÇÃO

A MarkaAI Tecnologia Ltda. ("MarkaAI", "nós", "nos" ou "nosso") desenvolveu este aplicativo como uma plataforma de gestão e agendamento para profissionais e estabelecimentos do setor de beleza e bem-estar.

Esta Política de Privacidade descreve como coletamos, usamos, processamos, armazenamos e protegemos suas informações pessoais quando você utiliza o aplicativo MarkaAI. Ao utilizar nossos serviços, você concorda com as práticas descritas nesta política.

## 2. RESPONSÁVEL PELO TRATAMENTO (DPO)

**Encarregado de Proteção de Dados (DPO):**  
E-mail: dpo@markaai.com.br  
Endereço: [Inserir endereço da sede]  

O DPO é responsável por atender solicitações dos titulares de dados e prestar esclarecimentos sobre o tratamento de dados pessoais.

## 3. DADOS PESSOAIS COLETADOS

### 3.1 Dados de Cadastro (Obrigatórios)
- Nome completo
- Endereço de e-mail
- Número de telefone celular (WhatsApp)
- Data de nascimento (para clientes)
- Endereço completo (CEP, rua, número, bairro, cidade, estado)

### 3.2 Dados de Perfil Profissional (Para Donos)
- Razão social e nome fantasia do estabelecimento
- CNPJ (quando aplicável)
- CPF do responsável legal
- Descrição dos serviços oferecidos
- Fotos do estabelecimento e profissionais

### 3.3 Dados de Uso e Dispositivo
- Endereço IP
- Tipo de dispositivo e sistema operacional
- Versão do aplicativo
- Identificadores únicos de dispositivo
- Dados de localização geográfica (com consentimento)
- Logs de acesso e atividades no aplicativo

### 3.4 Dados Financeiros
- Informações de pagamento processadas pela API do Mercado Pago (instituição de pagamento regulada pelo BACEN)
- Identificadores de transação gerados pelo Mercado Pago (IDs de pagamento para rastreamento)
- Status de pagamento (aprovado, pendente, recusado, reembolsado)

**Importante — O que NÃO coletamos:** A MarkaAI **não armazena e não tem acesso** a número completo do cartão, CVV, senha de conta bancária ou dados bancários completos. Esses dados são inseridos pelo usuário diretamente no ambiente PCI DSS do Mercado Pago e **nunca trafegam pelos servidores da MarkaAI**.

**Política de privacidade do Mercado Pago:** Ao processar pagamentos, os dados financeiros também estão sujeitos à Política de Privacidade do Mercado Pago: mercadopago.com.br/privacidade

### 3.5 Dados de Comunicação
- Histórico de conversas com suporte
- Avaliações e feedbacks
- Notificações push e preferências de comunicação

## 4. BASES LEGAIS PARA TRATAMENTO (LGPD)

Tratamos seus dados pessoais com base nas seguintes fundamentações legais:

- **Consentimento (Art. 7º, I):** Quando você aceita expressamente esta política
- **Execução de Contrato (Art. 7º, II):** Para processar agendamentos e pagamentos
- **Cumprimento de Obrigação Legal (Art. 7º, III):** Para obrigações fiscais e contábeis
- **Legítimo Interesse (Art. 7º, IX):** Para prevenção de fraudes e segurança da plataforma
- **Proteção do Crédito (Art. 7º, V):** Para avaliação de risco em transações financeiras

## 5. FINALIDADES DO TRATAMENTO

| Finalidade | Descrição | Base Legal |
|------------|-----------|------------|
| Gestão de conta | Criar e manter seu cadastro | Execução de contrato |
| Agendamentos | Processar reservas de horários | Execução de contrato |
| Pagamentos | Processar transações financeiras | Execução de contrato |
| Notificações | Enviar lembretes e atualizações | Consentimento |
| Marketing | Comunicações promocionais (opcional) | Consentimento |
| Segurança | Prevenir fraudes e proteger dados | Legítimo interesse |
| Suporte | Atender solicitações e resolver problemas | Execução de contrato |
| Melhorias | Analisar uso para aprimorar serviços | Legítimo interesse |
| Obrigações legais | Cumprir exigências fiscais e regulatórias | Obrigação legal |

## 6. COMPARTILHAMENTO DE DADOS

### 6.1 Processadores Autorizados
Compartilhamos dados estritamente necessários com:

| Parceiro | Finalidade | Dados compartilhados | Localização |
|----------|------------|----------------------|-------------|
| Supabase | Banco de dados e autenticação | Dados de perfil, agendamentos, logs | Estados Unidos |
| Mercado Pago | Processamento de pagamentos | Nome, e-mail, CPF (para antifraude), valor da transação | Brasil |
| Google Cloud | Hospedagem e analytics | Dados anonimizados de uso | Estados Unidos |
| Resend | Envio de e-mails transacionais | Nome, e-mail | Estados Unidos |
| Apple Push Notification Service | Notificações push iOS | Token de dispositivo | Estados Unidos |
| Firebase Cloud Messaging | Notificações push Android | Token de dispositivo | Estados Unidos |

**Sobre o Mercado Pago:** Para processar pagamentos e realizar análise antifraude, o Mercado Pago pode solicitar dados complementares diretamente ao usuário conforme suas próprias políticas. A MarkaAI não controla esses dados adicionais. Consulte: mercadopago.com.br/privacidade

**Nota sobre transferência internacional:** Supabase e Google Cloud são provedores sediados nos EUA. A transferência é protegida por cláusulas contratuais específicas e certificações SOC 2 / ISO 27001 desses provedores.

### 6.2 Compartilhamento entre Usuários
- **Cliente → Estabelecimento:** Ao agendar, o estabelecimento recebe seu nome, telefone e serviço solicitado
- **Estabelecimento → Cliente:** Clientes veem nome, foto e avaliações do estabelecimento

### 6.3 Exigências Legais
Podemos divulgar dados quando exigido por:
- Ordem judicial ou administrativa
- Autoridades policiais em investigações
- Órgãos reguladores competentes

## 7. RETENÇÃO E EXCLUSÃO DE DADOS

### 7.1 Prazos de Retenção
- **Dados de cadastro:** Pelo tempo da relação contratual + 5 anos (prazo prescricional)
- **Dados de agendamentos:** 5 anos (obrigação fiscal)
- **Dados financeiros:** 5 anos (Código de Defesa do Consumidor e normas contábeis)
- **Logs de segurança:** 6 meses
- **Dados de comunicação:** 2 anos após o término da relação

### 7.2 Exclusão de Conta
Você pode solicitar a exclusão da conta em: **Configurações > Privacidade > Excluir Conta**

A exclusão será processada em até 30 dias, exceto quando houver obrigação legal de retenção.

## 8. SEUS DIREITOS COMO TITULAR (LGPD - Art. 18)

Você tem os seguintes direitos:

1. **Confirmação:** Confirmar a existência de tratamento de seus dados
2. **Acesso:** Obter cópia dos dados pessoais tratados
3. **Retificação:** Corrigir dados incompletos, inexatos ou desatualizados
4. **Anonimização:** Anonimizar dados desnecessários ou excessivos
5. **Bloqueio:** Suspender temporariamente o tratamento
6. **Eliminação:** Solicitar a exclusão dos dados (direito ao esquecimento)
7. **Portabilidade:** Receber dados em formato estruturado e interoperável
8. **Informação:** Saber as entidades com as quais compartilhamos dados
9. **Revogação:** Revogar o consentimento a qualquer momento

### Como exercer seus direitos
Envie sua solicitação para **dpo@markaai.com.br** com:
- Nome completo
- E-mail cadastrado
- Descrição do direito a ser exercido
- Documento de identificação (quando necessário)

Responderemos em até 15 dias úteis.

## 9. SEGURANÇA DA INFORMAÇÃO

Implementamos medidas técnicas e administrativas:
- Criptografia SSL/TLS em todas as transmissões
- Criptografia AES-256 para dados em repouso
- Autenticação multifator (MFA) opcional
- Monitoramento contínuo de segurança
- Backups regulares e criptografados
- Controle de acesso baseado em funções (RBAC)
- Treinamento de colaboradores em privacidade

## 10. COOKIES E TECNOLOGIAS SIMILARES

Utilizamos:
- **Cookies essenciais:** Funcionamento básico do aplicativo
- **Cookies de preferências:** Idioma, região
- **Cookies analíticos:** Google Analytics (anonimizado)
- **Cookies de marketing:** Apenas com consentimento explícito

## 11. TRANSFERÊNCIA INTERNACIONAL

Dados podem ser transferidos para servidores nos EUA (Supabase, Google Cloud). Garantimos proteção através de:
- Cláusulas Contratuais Tipo da Comissão Europeia
- Adequação decisions onde aplicável
- Certificações de compliance (SOC 2, ISO 27001)

## 12. IDADE MÍNIMA

O aplicativo é destinado a maiores de 18 anos. Menores de idade só podem utilizar com consentimento dos responsáveis legais.

## 13. ALTERAÇÕES DESTA POLÍTICA

Notificaremos sobre alterações significativas:
- Por e-mail 30 dias antes da vigência
- Aviso no aplicativo
- Requereremos novo consentimento para mudanças substantivas

## 14. DISPOSITIVOS MÓVEIS - PERMISSÕES ESPECÍFICAS

### iOS (Apple App Store)
O aplicativo solicita:
- **Localização quando em uso:** Para encontrar estabelecimentos próximos
- **Notificações:** Para lembretes de agendamentos
- **Câmera:** Para upload de foto de perfil (opcional)
- **Galeria de fotos:** Para upload de imagens do estabelecimento (opcional)

### Android (Google Play)
Permissões equivalentes às listadas acima, seguindo as políticas de privacidade do Google Play.

## 15. CONTATO

Para questões sobre privacidade:
- **E-mail:** dpo@markaai.com.br
- **Suporte:** Através do aplicativo em Configurações > Ajuda
- **Endereço:** [Inserir endereço completo]

---

*Esta política está em conformidade com a Lei Geral de Proteção de Dados (Lei 13.709/2018) e os requisitos das lojas Apple App Store e Google Play Store.*
''';

  static const String termsOfUse = '''
# TERMOS DE USO

**Data de vigência:** 04 de Maio de 2026  
**Última atualização:** 04 de Maio de 2026

## 1. ACEITAÇÃO DOS TERMOS

Bem-vindo à MarkaAI. Estes Termos de Uso ("Termos") constituem um acordo juridicamente vinculante entre você ("Usuário", "Cliente" ou "Dono de Negócio") e a MarkaAI Tecnologia Ltda., CNPJ [inserir], sediada em [inserir endereço].

Ao criar uma conta, acessar ou utilizar o aplicativo MarkaAI, você declara que:
- Tem capacidade legal para celebrar contratos (é maior de 18 anos)
- Leu, compreendeu e concorda com estes Termos
- Concorda com nossa Política de Privacidade
- Fornecerá informações verdadeiras e atualizadas

**SE VOCÊ NÃO CONCORDAR COM ESTES TERMOS, NÃO UTILIZE O APLICATIVO.**

## 2. DEFINIÇÕES

- **Aplicativo:** Software MarkaAI disponível para iOS, Android e Web
- **Plataforma:** Conjunto de serviços, APIs e infraestrutura da MarkaAI
- **Estabelecimento/Negócio:** Profissional ou empresa que oferece serviços através da plataforma
- **Cliente:** Pessoa física que agenda serviços através da plataforma
- **Conteúdo:** Informações, dados, textos, imagens, fotos, vídeos ou outros materiais

## 3. DESCRIÇÃO DO SERVIÇO E MODELO DE INTERMEDIAÇÃO

A MarkaAI é uma plataforma tecnológica que:
- Conecta clientes a estabelecimentos de beleza e bem-estar
- Oferece sistema de agendamento online
- Intermedia pagamentos entre clientes e estabelecimentos via API do Mercado Pago
- Fornece ferramentas de gestão para negócios

**A MarkaAI NÃO presta serviços de beleza diretamente** e **NÃO é parte do contrato de prestação de serviço** firmado entre o Cliente e o Estabelecimento.

### 3.1 Natureza Jurídica da Intermediação

A MarkaAI atua exclusivamente como **marketplace de intermediação tecnológica**, na modalidade prevista no Marco Civil da Internet (Lei 12.965/2014) e nas diretrizes do Banco Central do Brasil para plataformas de pagamento. Isso significa:

- O **contrato de prestação de serviços** (ex: corte de cabelo, manicure, estética) é celebrado **diretamente entre o Cliente e o Estabelecimento**. A MarkaAI não é parte desse contrato.
- O **pagamento** pelo serviço é processado pela API do **Mercado Pago** (instituição de pagamento regulada pelo Banco Central do Brasil, autorização nº 13.959.591/0001-38), atuando como facilitador financeiro independente.
- A **MarkaAI não recebe, retém nem custódia os valores** pagos pelos clientes pelos serviços dos estabelecimentos. Os valores transitam diretamente pelo sistema do Mercado Pago.
- A MarkaAI recebe **exclusivamente a taxa de uso da plataforma** (assinatura do estabelecimento e/ou taxa percentual sobre transações), separada e distinta do valor do serviço.

### 3.2 Responsabilidades Divididas

| Responsabilidade | MarkaAI | Estabelecimento | Mercado Pago |
|---|---|---|---|
| Disponibilidade da plataforma de agendamento | ✅ Sim | Não | Não |
| Qualidade do serviço prestado | **Não** | ✅ Sim | Não |
| Processamento seguro do pagamento | Não | Não | ✅ Sim |
| Repasse dos valores ao estabelecimento | Não | Não | ✅ Sim |
| Cancelamento e reembolso do serviço | **Não** | ✅ Sim (define a política) | Operacionaliza |
| Emissão de nota fiscal do serviço | **Não** | ✅ Sim | Não |
| Segurança dos dados de cartão | Não | Não | ✅ Sim (PCI DSS) |

## 4. CADASTRO E CONTA

### 4.1 Criação de Conta
Para utilizar o aplicativo, você deve:
- Fornecer informações precisas, completas e atualizadas
- Manter a confidencialidade de suas credenciais
- Notificar imediatamente qualquer uso não autorizado
- Ser responsável por toda a atividade em sua conta

### 4.2 Tipos de Conta
- **Conta de Cliente:** Para agendamento de serviços
- **Conta de Dono/Profissional:** Para gestão de estabelecimento
- **Conta de Funcionário:** Acesso limitado via convite do dono

### 4.3 Verificação
Podemos solicitar documentação para verificar:
- Identidade do usuário
- Titularidade do estabelecimento
- Regularidade fiscal (para negócios)

## 5. PLANOS E ASSINATURAS

### 5.1 Planos Disponíveis
- **Gratuito:** Funcionalidades básicas, com limitações
- **Start:** Recursos essenciais para pequenos negócios
- **Plus:** Recursos avançados incluindo financeiro e estoque
- **Pro:** Análises completas, 5 profissionais, suporte VIP

### 5.2 Período de Teste (Trial)
- 30 dias de teste gratuito para planos pagos
- **Um trial por conta** — tentativas de múltiplos trials serão bloqueadas
- Nenhuma cobrança automática sem consentimento explícito
- Ao término, o acesso premium é bloqueado automaticamente

### 5.3 Renovação e Cancelamento
- Assinaturas são renovadas automaticamente no ciclo contratado
- Cancelamento pode ser feito a qualquer momento no aplicativo
- Cancelamento interrompe a renovação, não o acesso imediato
- Reembolso conforme Política de Reembolso (Direito de Arrependimento: 7 dias)

### 5.4 In-App Purchases
Assinaturas via Apple App Store ou Google Play estão sujeitas aos termos adicionais:
- Apple: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
- Google: https://play.google.com/about/play-terms/

## 6. PAGAMENTOS E INTERMEDIAÇÃO FINANCEIRA

### 6.1 Processador de Pagamentos — Mercado Pago

Todos os pagamentos realizados por serviços de estabelecimentos dentro da plataforma MarkaAI são **exclusivamente processados pela API do Mercado Pago** (Mercado Pago Instituição de Pagamento Ltda., CNPJ 10.573.521/0001-91), empresa regulada e autorizada pelo Banco Central do Brasil.

**Fluxo do dinheiro:**
```
Cliente → [Mercado Pago API] → Estabelecimento
```
A MarkaAI **não toca, não retém e não custódia** os valores pagos pelos serviços.

**O que a MarkaAI recebe:** Exclusivamente a taxa de uso da plataforma (assinatura mensal e/ou taxa percentual sobre transações), cobrada do **estabelecimento**, não do cliente.

**Dados de pagamento:** A MarkaAI **não armazena** dados de cartão de crédito, CVV, ou dados bancários. Esses dados são inseridos diretamente no ambiente seguro e certificado PCI DSS do Mercado Pago.

**Ao efetuar um pagamento**, você também está sujeito aos Termos de Uso e Política de Privacidade do Mercado Pago, disponíveis em: mercadopago.com.br/privacidade

### 6.2 Taxas e Tarifas da Plataforma
- **Plano Gratuito:** Taxa percentual sobre transações processadas (cobrada do estabelecimento)
- **Planos Pagos:** Taxas reduzidas ou isenção conforme plano contratado pelo estabelecimento
- Valores e percentuais atualizados em markaai.com.br/precos
- **Clientes finais não pagam taxa de uso da plataforma** — pagam apenas o valor do serviço definido pelo estabelecimento

### 6.3 Repasse ao Estabelecimento
- O Mercado Pago é responsável pelo repasse dos valores ao estabelecimento
- Prazos de repasse seguem as regras do Mercado Pago: D+2 (cartão) e D+1 (PIX) para conta Mercado Pago
- A MarkaAI não tem poder de antecipar, reter ou bloquear repasses — tais operações são de competência exclusiva do Mercado Pago
- Em casos de disputa ou chargeback, o Mercado Pago pode reter valores preventivamente conforme suas próprias políticas

### 6.4 Estornos e Chargebacks
- Chargebacks abertos pelo cliente junto à operadora do cartão impactam diretamente a conta do estabelecimento no Mercado Pago
- A MarkaAI **não é parte** do processo de chargeback — o processo ocorre entre Cliente, Operadora do Cartão, e Mercado Pago
- Taxa administrativa por chargeback indevido (conforme apuração): R\$ 30,00 cobrada do estabelecimento
- Disputas devem ser respondidas pelo estabelecimento no painel do Mercado Pago em até 7 dias

## 7. RESPONSABILIDADES ESPECÍFICAS POR PERFIL

### 7.0 Para o Cliente (usuário final)

Ao realizar um agendamento e efetuar um pagamento pela plataforma, o Cliente compreende e aceita que:

- O **contrato de serviço** é firmado com o **Estabelecimento**, não com a MarkaAI
- A MarkaAI **não garante** a qualidade, pontualidade ou execução do serviço — essa responsabilidade é integral do Estabelecimento
- Eventuais reclamações sobre o serviço em si devem ser direcionadas **ao Estabelecimento** em primeiro lugar
- O pagamento é processado pelo **Mercado Pago** — dúvidas sobre a transação financeira podem ser tratadas diretamente com o Mercado Pago
- A MarkaAI pode atuar como facilitadora de comunicação em disputas, mas **não tem obrigação legal de mediar** conflitos entre Cliente e Estabelecimento
- A **nota fiscal do serviço** deve ser emitida pelo Estabelecimento, não pela MarkaAI

### 7.0B Para o Estabelecimento (loja/profissional)

Ao cadastrar seu negócio e receber pagamentos pela plataforma, o Estabelecimento compreende e aceita que:

- É o **único responsável** pela prestação do serviço ofertado
- É o **único responsável** pela emissão de nota fiscal dos serviços prestados aos clientes
- A MarkaAI atua apenas como **tecnologia de intermediação** — não assume solidariamente a responsabilidade pelos serviços
- O processamento dos pagamentos recebidos é gerenciado pelo **Mercado Pago**; a MarkaAI não possui acesso ao saldo da conta Mercado Pago do Estabelecimento
- O Estabelecimento deve manter sua conta no Mercado Pago regular e em conformidade com os termos daquele serviço
- Chargebacks e disputas financeiras são gerenciados diretamente pelo Mercado Pago, e o Estabelecimento deve responder às contestações nos prazos exigidos
- É vedado solicitar ao cliente que realize pagamentos por canais externos à plataforma para evadir as taxas acordadas (direcionamento indevido)

## 8. OBRIGAÇÕES DO USUÁRIO

### 8.1 Obrigações Gerais
Você concorda em:
- Não violar leis ou regulamentos aplicáveis
- Não infringir direitos de propriedade intelectual
- Não transmitir malware, vírus ou código malicioso
- Não tentar acessar áreas restritas da plataforma
- Não realizar engenharia reversa do aplicativo
- Não usar a plataforma para spam ou phishing
- Não criar contas falsas ou robôs

### 8.2 Obrigações Específicas de Donos
- Manter CNPJ ou CPF em situação regular
- Honrar agendamentos aceitos
- Informar política de cancelamento claramente
- Respeitar a privacidade dos clientes
- Não solicitar pagamentos fora da plataforma (direcionamento indevido)

### 8.3 Conteúdo do Usuário
Você concede à MarkaAI licença não exclusiva, gratuita e mundial para:
- Usar, reproduzir e exibir seu conteúdo na plataforma
- Modificar conteúdo apenas para adequação técnica
- Promover seu estabelecimento (com seu consentimento)

Você declara ter todos os direitos sobre o conteúdo postado.

## 9. PROPRIEDADE INTELECTUAL

### 9.1 Nossa Propriedade
Todo o software, código, design, logotipos, marcas e funcionalidades são propriedade exclusiva da MarkaAI, protegidos por:
- Lei de Direitos Autorais (Lei 9.610/98)
- Lei de Propriedade Industrial (Lei 9.279/96)
- Lei de Software (Lei 9.609/98)

### 9.2 Restrições
É expressamente proibido:
- Copiar, modificar ou criar obras derivadas
- Realizar engenharia reversa ou descompilar
- Remover avisos de direitos autorais
- Usar nossas marcas sem autorização
- Frame ou mirror do conteúdo da plataforma

### 9.3 Feedback
Sugestões enviadas podem ser usadas sem obrigação de compensação.

## 10. MODERAÇÃO E SUSPENSÃO

### 10.1 Violações
Podemos suspender ou encerrar contas que:
- Violar estes Termos
- Receberem múltiplas reclamações
- Forem usadas de forma fraudulenta
- Engajarem em comportamento abusivo

### 10.2 Notificação
Quando possível, notificaremos antes da suspensão, salvo quando:
- Há risco iminente de dano
- Violação grave da lei
- Ordem judicial ou requisição governamental

### 10.3 Efeitos da Suspensão
- Perda de acesso aos dados (salvo backup conforme LGPD)
- Cancelamento de agendamentos futuros
- Bloqueio de saques pendentes até resolução

## 11. LIMITAÇÃO DE RESPONSABILIDADE

### 11.1 Limitação Geral
NA MÁXIMA EXTENSÃO PERMITIDA POR LEI, A MARKAAI NÃO SERÁ RESPONSÁVEL POR:
- DANOS INDIRETOS, INCIDENTAIS, ESPECIAIS OU CONSEQUENCIAIS
- LUCROS CESSANTES OU PERDA DE RECEITA
- PERDA DE DADOS OU DANOS A REPUTAÇÃO
- CUSTOS DE AQUISIÇÃO DE SERVIÇOS ALTERNATIVOS

### 11.2 Limitação de Valor
Nossa responsabilidade total limita-se ao maior entre:
- Valor pago por você nos últimos 12 meses
- R\$ 1.000,00 (mil reais)

### 11.3 Exceções
As limitações acima não se aplicam a:
- Dolo ou fraude da MarkaAI
- Lesão corporal ou morte
- Obrigações que não podem ser limitadas por lei aplicável

### 11.4 Responsabilidade sobre Serviços Terceiros
Não nos responsabilizamos por:
- Qualidade dos serviços prestados pelos estabelecimentos
- Cumprimento de agendamentos pelos profissionais
- Produtos vendidos pelos estabelecimentos
- Conduta de usuários na plataforma

## 12. INDENIZAÇÃO

Você concorda em indenizar e isentar a MarkaAI de reclamações decorrentes de:
- Violação destes Termos
- Violação de direitos de terceiros
- Conduta negligente ou ilícita
- Informações falsas fornecidas

## 13. RESOLUÇÃO DE DISPUTAS

### 13.1 Negociação Direta
Tentaremos resolver disputas de forma amigável. Contate: suporte@markaai.com.br

### 13.2 Mediação
Se não houver acordo, as partes podem recorrer à mediação conforme Código de Defesa do Consumidor.

### 13.3 Foro
Qualquer litígio será dirimido no foro da comarca de Belo Horizonte/MG, salvo competência legal diversa para consumidores.

## 14. DISPOSIÇÕES GERAIS

### 14.1 Acordo Integral
Estes Termos, juntamente com a Política de Privacidade, constituem o acordo integral entre as partes.

### 14.2 Severabilidade
Se qualquer disposição for considerada inválida, as demais permanecem em vigor.

### 14.3 Cessão
Não é permitida cessão destes Termos sem consentimento prévio por escrito.

### 14.4 Força Maior
Não seremos responsáveis por falhas decorrentes de eventos de força maior.

### 14.5 Comunicações
Comunicações oficiais serão enviadas para o e-mail cadastrado.

### 14.6 Lei Aplicável
Estes Termos são regidos pelas leis da República Federativa do Brasil.

## 15. ALTERAÇÕES DOS TERMOS

Podemos modificar estes Termos a qualquer momento. Alterações significativas serão notificadas:
- Por e-mail com 30 dias de antecedência
- Aviso no aplicativo
- Requereremos aceitação explícita de mudanças materiais

O uso continuado após alterações constitui aceitação.

## 16. APPLE APP STORE - DISPOSIÇÕES ADICIONAIS

Reconhece que:
- Estes Termos são entre você e a MarkaAI, não com a Apple
- A Apple não tem obrigação de fornecer manutenção ou suporte
- A Apple não é responsável por reclamações sobre o aplicativo
- Você deve cumprir os App Store Terms of Service
- A Apple pode rastrear seu uso para fins de segurança

## 17. GOOGLE PLAY - DISPOSIÇÕES ADICIONAIS

Reconhece que:
- Estes Termos são entre você e a MarkaAI, não com o Google
- O Google Play pass-through não constitui autorização de uso indevido
- Você deve cumprir os Google Play Terms of Service
- O Google pode rastrear seu uso para fins de segurança

## 18. CONTATO

Dúvidas sobre estes Termos:
- **E-mail:** legal@markaai.com.br
- **Suporte:** Configurações > Ajuda no aplicativo
- **Endereço:** [Inserir endereço completo]

**Dúvidas sobre pagamentos processados pelo Mercado Pago:**
- Central de Ajuda Mercado Pago: mercadopago.com.br/ajuda
- Telefone Mercado Pago: 0800 637 7246

---

*Ao clicar em "Aceito" ou utilizar o aplicativo, você confirma que leu, entendeu e concorda com estes Termos de Uso.*
''';

  static const String refundPolicy = '''
# POLÍTICA DE CANCELAMENTO, REEMBOLSO E ARREPENDIMENTO

**Data de vigência:** 04 de Maio de 2026  
**Última atualização:** 04 de Maio de 2026

## 1. DIREITO DE ARREPENDIMENTO (CÓDIGO DE DEFESA DO CONSUMIDOR)

Em conformidade com o Art. 49 do Código de Defesa do Consumidor (Lei 8.078/1990), você tem direito ao **arrependimento em até 7 (sete) dias corridos** a contar da assinatura de qualquer plano pago.

Durante este período, você pode solicitar o cancelamento e receberá **reembolso integral** de todos os valores pagos, sem qualquer penalidade ou questionamento.

### Como exercer o direito de arrependimento:
1. Acesse **Configurações > Assinatura** no aplicativo
2. Clique em "Cancelar e Reembolsar" (dentro de 7 dias)
3. Ou envie e-mail para: faturamento@markaai.com.br

**Prazo de estorno:** Até 10 dias úteis na forma de pagamento original.

## 2. CANCELAMENTO APÓS O PERÍODO DE ARREPENDIMENTO

### 2.1 Planos MarkaAI (Pagamento Direto)
Após os 7 dias iniciais:
- Cancelamento pode ser feito a qualquer momento, sem burocracia
- Acesso aos recursos premium permanece ativo até o final do período já pago
- Renovação automática é cancelada imediatamente, sem cobrança adicional
- **Plano Mensal:** Não há reembolso proporcional do ciclo vigente (o acesso continua até o final do período)
- **Plano Anual:** Em casos de cancelamento antecipado após o período de arrependimento, avaliamos reembolso proporcional dos meses não utilizados mediante solicitação ao suporte

### 2.2 Ciclo de Faturamento
- Mensal: Acesso até o último dia do mês pago
- Anual: Acesso até o aniversário da contratação

## 3. REEMBOLSO POR DESCUMPRIMENTO

Se a MarkaAI não cumprir obrigações essenciais (indisponibilidade prolongada, perda de dados por falha nossa), você pode ter direito a:
- Créditos para uso futuro
- Reembolso proporcional do período não utilizado
- Análise caso a caso pelo time de suporte

## 4. POLÍTICA ESPECÍFICA POR PLATAFORMA

### 4.1 Apple App Store (In-App Purchases)

**Importante:** Para assinaturas feitas via iTunes/App Store:

- A MarkaAI **não controla** o processo de reembolso
- Solicitações devem ser feitas diretamente à Apple em: **reportaproblem.apple.com**
- Ou através do aplicativo da App Store: Conta > Compras > Reportar Problema

**Prazo da Apple:** Geralmente até 90 dias após a compra (avaliação caso a caso).

**Cancelamento:** Pode ser feito em: Configurações iPhone > [Seu Nome] > Assinaturas

### 4.2 Google Play Store (In-App Purchases)

Para assinaturas via Google Play:

- Reembolsos são avaliados pela política do Google
- Link direto: **play.google.com/store/account/subscriptions**
- Ou através do aplicativo Google Play > Perfil > Pagamentos e Assinaturas

**Dentro de 48 horas:** Podemos auxiliar no processo de estorno em casos excepcionais.

**Após 48 horas:** Solicitação deve ser feita diretamente ao Google.

### 4.3 Pagamento via Mercado Pago (Direto)

Para assinaturas processadas diretamente pela MarkaAI:

- Reembolso processado em até 10 dias úteis
- Estorno na forma original (cartão de crédito = estorno na fatura; PIX = devolução via PIX)
- Consultar status em: Configurações > Assinatura > Histórico de Pagamentos

## 5. AGENDAMENTOS E SERVIÇOS DE TERCEIROS

### 5.1 Natureza da Intermediação — Separação Clara de Responsabilidades

A MarkaAI atua **exclusivamente como intermediador tecnológico** entre Clientes e Estabelecimentos, nos termos do modelo de marketplace.

**O que isso significa na prática:**
- O serviço (corte, manicure, estética etc.) é contratado **diretamente com o Estabelecimento** — a MarkaAI não é fornecedora do serviço
- O pagamento pelo serviço é **processado pelo Mercado Pago** (API integrada) — a MarkaAI não movimenta nem custódia esses valores
- A MarkaAI **não é responsável** por: qualidade do serviço, não comparecimento do profissional, produtos utilizados, higiene do local, ou qualquer aspecto da prestação do serviço em si
- O Estabelecimento é o **único devedor** da prestação do serviço ao cliente
- O reembolso de valores pagos pelo serviço **depende da política do Estabelecimento** e do Mercado Pago — não da MarkaAI

### 5.2 Políticas de Cancelamento por Estabelecimento
Cada estabelecimento define suas próprias regras:
- Tolerância para cancelamento com reembolso total
- Política de "no-show" (não comparecimento)
- Prazos mínimos para cancelamento

**Essas regras são exibidas no momento do agendamento** e devem ser consultadas antes da reserva.

### 5.3 Sinais e Pagamentos Antecipados
Quando você paga sinal ou valor integral antecipado:
- O reembolso segue a política do estabelecimento escolhido
- A MarkaAI repassa o valor apenas após confirmação de cancelamento aceito pelo estabelecimento
- Chargebacks indevidos resultam em suspensão da conta

### 5.4 Disputas entre Clientes e Estabelecimentos

Por ser intermediadora, a MarkaAI **não é parte nas disputas** entre Clientes e Estabelecimentos sobre a prestação do serviço.

**Caminho recomendado para disputas:**
1. Tente resolver diretamente com o Estabelecimento (contato disponível no app)
2. Se não resolvido, abra uma contestação no Mercado Pago (para reembolso do valor pago)
3. Se o Estabelecimento violar repetidamente os Termos de Uso da plataforma, reporte pelo app para avaliação de suspensão

**A MarkaAI pode:**
- Facilitar a comunicação entre as partes
- Suspender ou banir estabelecimentos com múltiplas reclamações verificadas
- Informar ao Mercado Pago sobre fraudes identificadas na plataforma

**A MarkaAI NÃO pode:**
- Forçar o Estabelecimento a reembolsar (não é parte do contrato de serviço)
- Liberar valores retidos pelo Mercado Pago (não gerencia o gateway)
- Intervir em decisões do Mercado Pago sobre chargebacks

## 6. CHARGEBACKS E ESTORNOS BANCÁRIOS

### 6.1 O que é Chargeback
É quando você solicita o estorno diretamente na operadora do cartão, sem passar pelo processo normal de cancelamento.

### 6.2 Chargebacks Indevidos
Se você abrir uma contestação no cartão sem antes tentar resolver pelo nosso suporte, entraremos em contato para entender o caso. Chargebacks reconhecidos como indevidos (após análise) podem resultar em:
- Suspensão temporária da conta até resolução
- Taxa administrativa de R\$ 30,00 (cobrada do estabelecimento, quando aplicável)

**Recomendamos sempre contatar nosso suporte primeiro** — resolvemos a grande maioria dos casos em até 2 dias úteis, sem necessidade de chargeback.

### 6.3 Quando o Chargeback é Apropriado
Apenas em casos de:
- Fraude no cartão (transação não reconhecida)
- Cobrança duplicada não corrigida
- Serviço não entregue após aprovação do reembolso

## 7. CRÉDITOS E VOUCHERS

### 7.1 Concessão de Créditos
A MarkaAI pode conceder créditos em casos de:
- Indisponibilidade do serviço por falha nossa
- Resolução de conflitos
- Campanhas promocionais

### 7.2 Regras de Uso
- Créditos não são convertíveis em dinheiro
- Válidos por 12 meses após concessão
- Podem ser usados para pagamento de assinaturas ou serviços
- Não acumuláveis com outras promoções (salvo indicado)

## 8. PROCESSO DE SOLICITAÇÃO DE REEMBOLSO

### Passo a Passo:
1. **Via Aplicativo:** Configurações > Assinatura > Solicitar Reembolso
2. **Via E-mail:** faturamento@markaai.com.br (incluir: nome, e-mail, motivo, comprovante)
3. **Prazo de Resposta:** 5 dias úteis
4. **Análise:** Avaliaremos conforme políticas acima
5. **Decisão:** Aprovação com prazo de estorno OU negação com justificativa

### Casos em que o reembolso é aprovado:
- Cobrança indevida ou duplicada
- Falha técnica crítica que impossibilitou o uso da plataforma
- Descumprimento de funcionalidade essencial garantida
- Erro no processamento de pagamento
- Arrependimento dentro do prazo legal de 7 dias
- Plano anual: solicitação fundamentada de reembolso proporcional

**Nossa política é resolver sempre a favor do usuário** quando há dúvida razoável. Entre em contato — analisamos cada caso individualmente.

## 9. ESTORNOS EM CARTÃO DE CRÉDITO

### Prazos de Processamento
- **Solicitação à MarkaAI:** Até 10 dias úteis para processamento
- **Operadora de cartão:** 1 a 2 ciclos de faturamento para aparecer na fatura
- **Total:** Até 45 dias para crédito completo

### Visualização na Fatura
O estorno aparecerá como:
- "Estorno MarkaAI" ou
- "CRÉDITO MarkaAI Tecnologia"

## 10. DEVOLUÇÕES EM PIX

Para pagamentos via PIX:
- Devolução feita para a chave PIX original
- Ou para chave PIX informada pelo solicitante
- Prazo: Até 10 dias úteis após aprovação
- Status acompanhável em Configurações > Assinatura

## 11. CANCELAMENTO POR INADIMPLÊNCIA

Se houver falha no pagamento da assinatura:
1. **Tentativa 1:** Notificação de falha + nova tentativa em 24h
2. **Tentativa 2:** Segunda tentativa em 72h + aviso de suspensão
3. **Tentativa 3:** Cancelamento da assinatura + downgrade para plano Gratuito

**Recuperação:** Pode reativar a qualquer momento quitando pendências.

## 12. DISPOSIÇÕES FINAIS

- Esta política está em conformidade com o CDC e legislação brasileira
- Casos omissos serão avaliados conforme boa-fé e práticas de mercado
- Para compras internacionais, aplicam-se também regras do país de origem do cartão

## 13. CONTATO

Dúvidas sobre reembolsos:
- **E-mail:** faturamento@markaai.com.br
- **Suporte:** Configurações > Ajuda > Faturamento
- **Horário:** Segunda a Sexta, 9h às 18h (Brasília)

---

*Esta política é parte integrante dos Termos de Uso da MarkaAI.*
''';

  static const String dataProcessingAgreement = '''
# ACORDO DE PROCESSAMENTO DE DADOS (DPA)

Para estabelecimentos comerciais (Controladores) que utilizam a MarkaAI.

## 1. NATUREZA DA RELAÇÃO

A MarkaAI atua como **Operador de Dados** conforme LGPD, processando dados pessoais em nome do Estabelecimento (Controlador).

## 2. OBRIGAÇÕES DA MARKAAI COMO OPERADOR

- Processar dados apenas conforme instruções documentadas
- Garantir sigilo e segurança
- Notificar violações de segurança em 24 horas
- Auxiliar na resposta a solicitações de titulares
- Disponibilizar dados para portabilidade
- Eliminar ou devolver dados ao término do contrato
- Não subcontratar sem autorização (salvo provedores listados na Política de Privacidade)

## 3. SUBPROCESSADORES AUTORIZADOS

Listados na seção 6 da Política de Privacidade.

## 4. SEGURANÇA

Medidas conforme seção 9 da Política de Privacidade.

## 5. AUDITORIA

Estabelecimento pode solicitar relatórios de conformidade anualmente.

---

*Este DPA é incorporado por referência aos Termos de Uso.*
''';
}
