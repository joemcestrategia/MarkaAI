# Auditoria de Segurança de Dados — MarkaAI
**Stack:** Flutter + Supabase (PostgreSQL + Auth + Edge Functions + Storage)
**Objetivo:** identificar e corrigir vetores de vazamento de dados de usuário, com saída pronta para evidência de auditoria LGPD/compliance.

---

## Como usar este documento

Este não é um checklist de "boas práticas" — é um roteiro de verificação. Cada item tem:
- **O que verificar** — o vetor de risco real nesse tipo de stack.
- **Como verificar** — query SQL, comando ou local exato no painel/código.
- **Critério de classificação** — 🟢 OK / 🟡 Atenção / 🔴 Crítico.
- **Campo de registro** — o que anotar no relatório final (seção 9).

Execute as seções na ordem. Seções 1 a 4 são as que mais geram vazamento real em apps Supabase. Não pule para o final.

Ao terminar cada item, preencha a tabela da Seção 9 com: item, status, evidência (print/query/output) e ação corretiva.

---

## 1. Row Level Security (RLS) — a causa #1 de vazamento em Supabase

RLS desabilitada ou mal escrita é o vetor mais comum de exposição de dados entre tenants/usuários no Supabase. Verifique tabela por tabela, não confie em "lembro que ativei".

### 1.1 Tabelas sem RLS habilitada

Rode no SQL Editor do Supabase:

```sql
select schemaname, tablename, rowsecurity
from pg_tables
where schemaname = 'public'
order by rowsecurity asc, tablename;
```

- 🔴 **Crítico:** qualquer tabela com `rowsecurity = false` que contenha dados de usuário (agendamentos, clientes, pagamentos, telefones).
- 🟡 **Atenção:** tabelas de configuração/lookup sem RLS (aceitável se realmente não têm dado sensível e não são graváveis publicamente).

### 1.2 Policies existentes mas com lógica permissiva demais

Liste todas as policies ativas:

```sql
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
order by tablename, cmd;
```

Para cada policy, pergunte:
- Ela usa `auth.uid()` ou compara contra `true`/`1=1`/uma constante? Policy do tipo `using (true)` em tabela com dado de usuário é vazamento garantido.
- Em apps multi-tenant (salões diferentes), a policy filtra por `salon_id` / `tenant_id` corretamente, ou só por `user_id`? Funcionários do mesmo salão devem ver dados do salão, mas **nunca** de outro salão.
- Existe policy de `SELECT` mas falta de `UPDATE`/`DELETE`? Às vezes a leitura está protegida mas a escrita não, permitindo que um usuário sobrescreva dado de outro.

- 🔴 **Crítico:** policy com `using (true)` ou sem filtro de tenant em tabela multi-salão.
- 🟡 **Atenção:** policy existe e filtra corretamente, mas falta cobertura para algum comando (`INSERT`/`UPDATE`/`DELETE`).
- 🟢 **OK:** policy filtra por `auth.uid()` + `tenant_id`/`salon_id` em todos os comandos relevantes.

### 1.3 Teste prático de RLS (não confie só na leitura do SQL)

Faça login como dois usuários de tenants/salões diferentes (ou crie dois usuários de teste) e, autenticado como o Usuário A, tente:

```sql
-- Rodar isso autenticado via client (não como service_role!)
select * from appointments where salon_id = '<id_do_salao_B>';
select * from clients;
select * from payments;
```

- 🔴 **Crítico:** Usuário A consegue ler/listar dados do salão B.
- 🟢 **OK:** retorno vazio ou erro de permissão.

> **Atenção:** rodar essa query usando a `service_role` key sempre retorna tudo — isso é esperado e não significa que RLS está quebrada. O teste só é válido com o **JWT do usuário autenticado**, não com a service key.

---

## 2. Funções `SECURITY DEFINER` — bypass silencioso de RLS

Funções `SECURITY DEFINER` rodam com os privilégios de quem criou a função (geralmente superuser), ignorando RLS. É um padrão necessário em alguns casos (ex: trigger de criação de usuário), mas é também o jeito mais comum de uma policy bem escrita ser completamente ignorada.

### 2.1 Listar todas as funções `SECURITY DEFINER`

```sql
select n.nspname as schema, p.proname as function_name, p.prosecdef as is_security_definer
from pg_proc p
join pg_namespace n on p.pronamespace = n.oid
where p.prosecdef = true
and n.nspname not in ('pg_catalog', 'information_schema');
```

Para cada função encontrada, leia o código-fonte (`\df+ nome_funcao` ou no painel) e verifique:
- Ela recebe algum parâmetro do usuário (ex: `user_id`, `salon_id`) sem validar que esse valor corresponde ao `auth.uid()` de quem está chamando?
- Ela faz `select *` ou `update` numa tabela sem filtro nenhum, assumindo que quem chamou já tem permissão?

- 🔴 **Crítico:** função aceita um ID arbitrário do client e retorna/altera dados sem verificar se esse ID pertence ao usuário autenticado. Isso permite que qualquer usuário autenticado peça dados de qualquer outro só trocando o parâmetro.
- 🟢 **OK:** a função valida `auth.uid()` internamente antes de qualquer leitura/escrita, mesmo correndo como definer.

### 2.2 Caso conhecido neste histórico: trigger sobrescrevendo `role`

Você já identificou e corrigiu um bug em que um trigger de OAuth sobrescrevia o campo `role` em conflito (ON CONFLICT). Vale revalidar que a correção está realmente em produção e não foi revertida em algum merge:

```sql
select tgname, tgrelid::regclass, pg_get_triggerdef(oid)
from pg_trigger
where tgrelid = 'public.users'::regclass; -- ajuste o nome da tabela se necessário
```

Confirme que a lógica de `ON CONFLICT` não tem `role = excluded.role` ou equivalente que reseta permissões de admin/staff para o valor padrão.

---

## 3. Edge Functions e validação de JWT

Você já passou por um caso real disso (toggle de validação no gateway vs. `getUser()` no código). Esse é exatamente o tipo de inconsistência que vaza dado: a função "parece" protegida no código, mas o gateway está configurado para não exigir JWT.

### 3.1 Configuração de cada Edge Function

No painel Supabase → Edge Functions → cada função → verificar:
- **"Verify JWT" está habilitado?** Se desabilitado, a função aceita chamadas sem token nenhum, e qualquer validação dentro do código só roda *depois* de já ter processado a requisição.
- Liste todas as functions e marque o status:

| Function | Verify JWT (gateway) | Valida `auth.getUser()` no código | Usa `service_role` internamente? |
|---|---|---|---|
| | | | |

- 🔴 **Crítico:** `Verify JWT = false` em função que manipula dado de usuário, especialmente se ela também usa `service_role` key internamente (combinação = bypass total de RLS sem autenticação nenhuma).
- 🟡 **Atenção:** `Verify JWT = true` mas o código não revalida o `user_id` do token contra o recurso solicitado (ex: a function confia em um `user_id` enviado no body em vez de extrair do token).

### 3.2 Exposição de `service_role` key

```bash
# Procure no código fonte (Flutter + qualquer Edge Function) por uso indevido da service key
grep -r "service_role" --include="*.dart" --include="*.ts" --include="*.js" .
grep -r "SUPABASE_SERVICE_ROLE_KEY" .
```

- 🔴 **Crítico:** `service_role` key referenciada em qualquer código que rode no client (Flutter, JS de frontend). Essa chave **nunca** pode estar no app — só em Edge Functions ou backend server-side.
- 🟢 **OK:** service key usada apenas em Edge Functions, vinda de variável de ambiente do servidor, nunca commitada em texto plano no repositório.

### 3.3 Segredos commitados no repositório

```bash
git log --all --full-history -- "*.env" "*secret*" "*key*"
grep -r "eyJ" --include="*.dart" . # JWTs geralmente começam com eyJ
```

- 🔴 **Crítico:** qualquer chave (anon, service_role, API key de terceiro como Meta/Mercado Pago) commitada no histórico do git, mesmo que removida depois (continua no histórico).

---

## 4. Dados sensíveis em trânsito e em repouso

### 4.1 Dados de pagamento (Mercado Pago / Stripe Connect)

Você integrou Mercado Pago via webhook e está construindo Stripe Connect. Verifique:
- Algum dado de cartão (número, CVV) é armazenado em alguma tabela própria, em vez de delegado inteiramente ao provedor de pagamento (Mercado Pago/Stripe)? Armazenar PAN/CVV é proibido por PCI-DSS e configura violação grave de LGPD.
- O webhook do Mercado Pago valida a assinatura/origem da requisição, ou apenas confia em qualquer POST recebido na URL?

```bash
grep -ri "card_number\|cvv\|numero_cartao" --include="*.sql" --include="*.dart" .
```

- 🔴 **Crítico:** qualquer coluna armazenando PAN, CVV, ou dado completo de cartão.
- 🟡 **Atenção:** webhook sem validação de assinatura (permite que qualquer terceiro envie payloads falsos de "pagamento aprovado").

### 4.2 Dados de contato (telefone via WhatsApp/Meta Cloud API)

Você já trabalha com números de telefone via Meta Cloud API. Verifique:
- Telefones e nomes de clientes estão em tabela com RLS ativa (já coberto na Seção 1), mas também: existe algum log (Edge Function logs, console.log, print() do Flutter) que imprime o número de telefone completo em texto plano?

```bash
grep -rn "print(" --include="*.dart" . | grep -i "phone\|telefone\|whatsapp"
```

- 🟡 **Atenção:** logs em produção exibindo PII (telefone, nome completo, email) sem mascaramento. Logs do Supabase ficam acessíveis a quem tem acesso ao painel — se a equipe crescer, isso vira superfície de exposição.

### 4.3 Storage (Supabase Storage / buckets)

```sql
select id, name, public from storage.buckets;
```

- 🔴 **Crítico:** bucket marcado `public = true` contendo qualquer arquivo com dado de usuário (ex: comprovantes, fotos de documento, anexos de cliente).
- Verifique também as policies de Storage (`storage.objects`) da mesma forma que a Seção 1 — bucket privado com policy `using (true)` é tão vazado quanto um bucket público.

### 4.4 Backups e exports

Você já fez migração de dados (Setmore → Supabase) e tem backup de app de igreja via Google Drive em outro projeto. Para o MarkaAI, verifique:
- Existe rotina de backup do banco? Onde fica armazenada (pasta pessoal, Drive compartilhado, bucket)? Quem tem acesso a esse backup?
- 🟡 **Atenção:** backups contendo dado de produção completo armazenados sem controle de acesso equivalente ao banco principal (ex: numa pasta de Drive pessoal sem expiração de link).

---

## 5. Autenticação e gestão de sessão

### 5.1 Configuração de Auth no painel Supabase

Authentication → Settings, verificar:
- **Email confirmations** habilitado (evita account takeover por email não verificado).
- **Rate limiting** de login/signup ativo (evita brute force e enumeration de emails cadastrados).
- Redirect URLs do OAuth restritas exatamente aos domínios de produção/staging — wildcard (`*`) em redirect URL é vetor de phishing/token theft.

### 5.2 Expiração e refresh de token

- JWT expiry configurado (padrão Supabase é 1h) — confirme que não foi estendido para um valor muito longo (ex: 7 dias) sem necessidade, o que aumenta a janela de uso de um token roubado.
- Refresh tokens são revogados no logout? Teste: faça logout no app, depois tente reusar o `access_token` antigo capturado antes do logout numa chamada à API. Se ainda funcionar até expirar naturalmente, está dentro do esperado do Supabase (JWT é stateless), mas vale documentar isso como comportamento conhecido para o relatório de compliance.

### 5.3 Multi-fator e papéis administrativos (staff do salão)

- Contas com papel de admin/dono de salão (que veem dados financeiros e de todos os clientes daquele salão) têm alguma proteção adicional, ou usam o mesmo fluxo de senha simples que um cliente final?
- 🟡 **Atenção:** ausência de MFA para contas com acesso amplo a dados de múltiplos clientes (mesmo que MFA completo seja um item de melhoria futura, documente como gap conhecido).

---

## 6. Cliente Flutter — exposição local

### 6.1 Armazenamento local sensível

```bash
grep -rn "SharedPreferences\|sqflite" --include="*.dart" . | grep -i "token\|senha\|password\|cpf"
```

- 🔴 **Crítico:** token de sessão, senha ou CPF salvos em `SharedPreferences` sem criptografia (SharedPreferences é texto plano em disco, recuperável em dispositivo rooteado/com backup ADB).
- 🟢 **OK:** uso de `flutter_secure_storage` (Keychain/Keystore) para qualquer credencial ou token.

### 6.2 Chaves expostas no bundle do app

```bash
grep -rn "anon_key\|SUPABASE_URL\|apiKey" --include="*.dart" lib/
```

- 🟢 **Esperado, não é falha:** a `anon_key` do Supabase **pode** estar no client — ela é pública por design e depende inteiramente da RLS (Seção 1) para proteção. O risco real não é a chave estar exposta, é a RLS estar fraca atrás dela. Documente isso no relatório para não ser confundido com um falso positivo numa auditoria externa.
- 🔴 **Crítico:** qualquer chave que **não** seja a `anon_key` (service_role, chave de API de terceiro com permissão de escrita) hardcoded no código Dart.

### 6.3 Certificate pinning / proteção de rede

- O app valida o certificado do servidor (pinning) ou aceita qualquer certificado, abrindo brecha para MITM em rede Wi-Fi pública (cenário comum: salão de beleza usando Wi-Fi do estabelecimento)?
- 🟡 **Atenção:** ausência de certificate pinning é aceitável como risco residual documentado, mas deve constar no relatório.

---

## 7. Logs, monitoramento e resposta a incidente

### 7.1 Quem tem acesso ao painel Supabase

- Liste todos os membros da organização Supabase com acesso ao projeto. Times com mais de uma pessoa devem usar papéis (`Owner`/`Developer`/`Read-only`) em vez de todos como Owner.
- 🟡 **Atenção:** colaboradores externos/freelancers com acesso `Owner` em vez de papel restrito.

### 7.2 Logs de auditoria de acesso a dados sensíveis

- Existe algum log (mesmo simples, em tabela própria) registrando quando um admin/staff acessa dados financeiros de um cliente fora do fluxo normal de atendimento? Para LGPD, capacidade de auditoria ("quem acessou o quê e quando") é frequentemente exigida em caso de incidente.
- 🟡 **Atenção:** ausência total de log de acesso a dados sensíveis (não bloqueia a operação, mas é um gap a documentar para compliance).

### 7.3 Plano de resposta a incidente

- Existe um documento (mesmo que simples) descrevendo o que fazer se um vazamento for identificado: quem notificar, em quanto tempo, como comunicar aos usuários afetados? A LGPD (Art. 48) exige comunicação à ANPD e aos titulares em caso de incidente com risco relevante.
- 🔴 **Crítico para fins de compliance** (não é falha técnica, é gap documental): ausência completa de plano de resposta a incidente é frequentemente o primeiro item cobrado numa auditoria externa, independente da robustez técnica.

---

## 8. Checklist específico LGPD (além da segurança técnica)

Estes itens não são vulnerabilidades de código, mas são exigidos para "compliance" no sentido formal e geralmente aparecem em auditoria externa:

- [ ] Política de Privacidade publicada e acessível no app (você já desenvolveu uma — confirmar que está linkada e atualizada com a arquitetura atual).
- [ ] Termos de Uso publicados (idem).
- [ ] Existe mecanismo para o titular (cliente do salão) solicitar exclusão dos seus dados (direito ao esquecimento, Art. 18 LGPD)? Hoje isso é manual (você como desenvolvedor apaga via SQL) ou existe um fluxo no app?
- [ ] Existe mecanismo de exportação de dados do titular (portabilidade, Art. 18 LGPD)?
- [ ] Base legal de tratamento de dados está identificada para cada finalidade (ex: dados de agendamento = execução de contrato; WhatsApp marketing = consentimento)?
- [ ] Dados de menores de idade (se algum salão atender menores) têm tratamento diferenciado, conforme Art. 14 LGPD?
- [ ] Existe Encarregado de Dados (DPO) nomeado, mesmo que informalmente, para fins de contato em caso de solicitação de titular?

---

## 9. Tabela de registro de achados (preencher durante a execução)

| # | Item | Seção | Status | Evidência | Ação corretiva | Prioridade |
|---|------|--------|--------|-----------|-----------------|------------|
| 1 | | | 🟢/🟡/🔴 | | | Alta/Média/Baixa |
| 2 | | | | | | |

---

## 10. Síntese final do relatório (preencher ao concluir)

**Resumo executivo:**
_(2-3 frases: estado geral encontrado, principal risco identificado, se há indício de vazamento já ocorrido)_

**Achados críticos (🔴):**
_(lista numerada, cada um referenciando o # da tabela da Seção 9)_

**Achados de atenção (🟡):**
_(idem)_

**Gaps de compliance LGPD (não-técnicos):**
_(lista dos itens da Seção 8 não atendidos)_

**Plano de remediação sugerido (ordem de prioridade):**
1.
2.
3.

---

*Documento gerado como roteiro de auditoria interna. Para fins de auditoria externa formal ou avaliação de conformidade legal com a LGPD, recomenda-se complementar esta verificação técnica com parecer de profissional jurídico especializado em proteção de dados — este documento cobre a camada técnica de segurança, não substitui avaliação jurídica de compliance.*
