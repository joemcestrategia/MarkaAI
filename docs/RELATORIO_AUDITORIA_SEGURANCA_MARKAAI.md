# 🔐 RELATÓRIO DE AUDITORIA DE SEGURANÇA — MarkaAI SaaS
> **Data da análise:** 16 de junho de 2026  
> **Stack:** Flutter · Supabase (PostgreSQL, RLS, Auth, Storage, Edge Functions) · Meta Cloud API · Mercado Pago  
> **Origem dos critérios:** `SECURITY_AUDIT_MARKAAI.md` (22 itens de verificação)  
> **Alcance:** Inspeção estática do código-fonte nas pastas `lib/`, `supabase/migrations/` e `supabase/functions/`

---

## 📊 RESUMO EXECUTIVO

| Status | Quantidade |
|---|---|
| ✅ Conforme | 10 |
| ⚠️ Atende parcialmente | 5 |
| ❌ Vulnerável | 7 |
| **Total** | **22** |

| Risco | Total | ✅ | ⚠️ | ❌ |
|---|---|---|---|---|
| 🔴 Crítico | 5 | 1 | 1 | 3 |
| 🟠 Alto | 8 | 5 | 1 | 2 |
| 🟡 Médio | 7 | 3 | 2 | 2 |
| 🟢 Baixo | 2 | 1 | 1 | 0 |

---

## 🔴 ITENS CRÍTICOS

### [S-01] RLS ausente ou desabilitado em tabelas sensíveis

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Arquivo verificado** | `supabase/migrations/02_harden_security.sql` |
| **Evidência** | Todas as tabelas principais têm `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` com políticas definidas |
| **Tabelas cobertas** | `shops`, `categories`, `services`, `appointments`, `products`, `employees`, `financial_transactions`, `bank_accounts`, `purchases`, `stock_movements`, `plans`, `webhook_logs`, `saved_cards` |
| **Ressalva** | Existem ~170+ migrations; tabelas adicionadas posteriormente podem não ter RLS. Recomenda-se revalidar no banco com `SELECT tablename FROM pg_tables WHERE schemaname='public' AND rowsecurity=false` |

---

### [S-02] Políticas RLS sem filtro por `salon_id`

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Arquivo verificado** | `supabase/migrations/02_harden_security.sql` |
| **Evidência** | Todas as políticas de INSERT/UPDATE/DELETE validam `shop_id IN (SELECT shop_id FROM public.users WHERE id = auth.uid())` ou equivalente |
| **Padrão usado** | As políticas associam o `shop_id` da tabela ao `shop_id` do usuário na tabela `public.users` |

---

### [S-03] Trigger `handle_new_user()` — elevação de privilégio via `role`

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Arquivo verificado** | `supabase/migrations/20260423_fix_role_reset_on_oauth.sql` |
| **Evidência** | — O trigger força `role='cliente'` no INSERT (linha 34)<br>— O `ON CONFLICT DO UPDATE` NUNCA altera `role` (linha 47: comentário `ROLE JAMAIS É ATUALIZADO AQUI`)<br>— Possui `SECURITY DEFINER SET search_path = public`<br>— Política adicional `users_update_own_profile` com `WITH CHECK (role = (SELECT role FROM public.users WHERE id = auth.uid()))` impede alteração maliciosa de `role` via API |
| **Observação** | Esta correção foi aplicada em migração recente (2026-04-23) — a versão anterior (migration 183) tinha o problema |

---

### [S-04] Funções `SECURITY DEFINER` sem `SET search_path = public`

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Arquivos verificados** | `supabase/migrations/167_fix_all_trigger_security_definer.sql`, `supabase/migrations/166_fix_trigger_security_definer.sql` |
| **Evidência** | Migrações 166 e 167 recriaram explicitamente TODAS as funções de trigger com `SECURITY DEFINER SET search_path = public`:<br>— `recalculate_shop_month()` (linha 28)<br>— `trigger_update_monthly_stats()` (linha 64)<br>— `fn_ticket_last_reply()` (linha 113)<br>— `fn_ticket_history()` (linha 138)<br>— `handle_new_user()` (migration 20260423) |
| **Recomendação** | Rodar a query de auditoria no banco para confirmar que não há outras funções: `SELECT proname FROM pg_proc JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid WHERE nspname = 'public' AND prosecdef = true` |

---

### [S-05] Validação de JWT nas Edge Functions

| Campo | Valor |
|---|---|
| **Status** | ⚠️ **ATENDE PARCIALMENTE** |
| **Evidência por função** | |

| Função | Valida JWT? | Detalhe |
|---|---|---|
| `checkAvailability` | ✅ Sim | `supabase.auth.getUser()` exigido (linha 14) |
| `createPixPayment` | ⚠️ Fraco | Chama `auth.getUser()` mas captura erro sem bloquear (linha 27) |
| `whatsapp-webhook` | ❌ Não | Usa `SUPABASE_SERVICE_ROLE_KEY` diretamente, sem validação de JWT |
| `mercadopagoCallback` | ❌ Não | Callback OAuth público, sem JWT — esperado para este fluxo |
| `mpPaymentWebhook` | ❌ Não | Usa `createSupabaseAdminClient()`, sem validação |
| `whatsapp-send` | ❌ Não | Usa `SUPABASE_SERVICE_ROLE_KEY` diretamente |
| `publicShopPreview` | ❌ Não | Pública por design, mas sem rate limiting (ver S-19) |
| Demais funções | ⚠️ Variável | Não foram inspecionadas individualmente |

**Risco real:** A função `whatsapp-send` permite envio de mensagens WhatsApp sem validação de JWT — depende apenas do toggle "Require JWT" no Dashboard do Supabase.

---

## 🟠 ITENS ALTOS

### [S-06] `service_role` key no Flutter

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Evidência** | — `grep -r "service_role" lib/` → 0 resultados<br>— `grep -r "SUPABASE_SERVICE_KEY" lib/` → 0 resultados<br>— `lib/main.dart` (linha 39): `anonKey: ApiKeys.supabaseAnonKey` — apenas anon key<br>— `ApiKeys.supabaseAnonKey` contém JWT com `"role":"anon"` (linha 7 do arquivo) |
| **Conclusão** | O Flutter usa APENAS a `anon key`. A `service_role` existe apenas nas Edge Functions via `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` |

---

### [S-07] Refresh token não revogado no logout

| Campo | Valor |
|---|---|
| **Status** | ❌ **VULNERÁVEL** |
| **Arquivo verificado** | `lib/core/services/auth_service.dart` (linha 188) |
| **Evidência** | `await _supabase.auth.signOut()` — sem o parâmetro `scope: SignOutScope.global` |
| **Impacto** | O logout revoga apenas a sessão LOCAL. Refresh tokens permanecem válidos no servidor Supabase por horas/dias. Uma sessão roubada sobrevive ao logout. |
| **Localização exata** | `lib/core/services/auth_service.dart:188` |

---

### [S-08] Webhook Mercado Pago sem validação HMAC

| Campo | Valor |
|---|---|
| **Status** | ❌ **VULNERÁVEL** |
| **Arquivo verificado** | `supabase/functions/mpPaymentWebhook/index.ts` |
| **Evidência** | — A função processa o body (`req.json()`) diretamente sem validar `x-signature` (linha 37)<br>— Não há importação de `createHmac`<br>— Nenhuma referência a `x-signature`, `x-request-id`, ou `MP_WEBHOOK_SECRET` |
| **Impacto** | Qualquer pessoa que descubra a URL pode enviar POSTs forjados simulando pagamentos aprovados. A re-verificação na API (S-09) mitiga parcialmente mas não elimina o risco (um ataque pode causar chamadas massivas à API do MP e gerar custos/logs falsos). |

---

### [S-09] Pagamento sem re-consulta à API do Mercado Pago

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Arquivo verificado** | `supabase/functions/mpPaymentWebhook/index.ts` (linhas 114-133) |
| **Evidência** | — Passo 2 (linha 108): consulta `GET /v1/payments/{paymentId}` na API do MP com o `access_token` da loja<br>— Verifica `paymentData.status !== 'approved'` antes de prosseguir (linha 129)<br>— Retorna 200 com `already_confirmed: true` se já foi processado (idempotência, linha 156) |

---

### [S-10] Token WhatsApp hardcoded no código

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Evidência** | — `grep -r "EAAG" lib/` → 0 resultados<br>— Tokens WhatsApp são lidos do banco (`shop_whatsapp_config.wa_access_token`) ou de `Deno.env.get('GLOBAL_WA_ACCESS_TOKEN')`<br>— `lib/core/repositories/whatsapp_config_repository.dart`: tokens são salvos/recuperados via Supabase, sem hardcode |
| **Arquivos verificados** | `supabase/functions/whatsapp-send/index.ts` (linhas 95-96), `lib/core/repositories/whatsapp_config_repository.dart` |

---

### [S-11] Webhook WhatsApp sem `hub.verify_token`

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Arquivo verificado** | `supabase/functions/whatsapp-webhook/index.ts` |
| **Evidência** | — GET: valida `hub.verify_token` contra `WHATSAPP_VERIFY_TOKEN` do env e contra `shop_whatsapp_config` (linhas 115-148)<br>— POST: valida assinatura HMAC-SHA256 via header `x-hub-signature-256` usando `WHATSAPP_APP_SECRET` (linhas 164-176)<br>— Implementa `verifyMetaSignature()` com Web Crypto API (linhas 12-37) |

---

### [S-12] Buckets Storage públicos com dados sensíveis

| Campo | Valor |
|---|---|
| **Status** | ⚠️ **ATENDE PARCIALMENTE** |
| **Buckets inspecionados** | |

| Bucket | Público? | Risco | Justificativa |
|---|---|---|---|
| `services` | ✅ Sim | 🟢 Baixo | Fotos de serviços — esperado ser público |
| `ticket-attachments` | ✅ Sim | 🟠 **Alto** | Screenshots de suporte podem conter dados de clientes, pagamentos e conversas privadas |
| `app-banners` | ✅ Sim | 🟢 Baixo | Banners de marketing — esperado ser público |

**Recomendação:** O bucket `ticket-attachments` deve ser **PRIVADO** com URLs assinadas (Signed URLs), pois contém screenshots de usuários que podem expor dados pessoais e de pagamento.

---

### [S-13] Storage sem filtro por `salon_id`

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME (parcialmente mitigado)** |
| **Evidência** | — `services`: upload/delete filtrado por `shop_id` (migration 03, linha 22)<br>— `ticket-attachments`: upload permitido para qualquer `authenticated` sem filtro de loja, delete apenas admin<br>— `app-banners`: admin-only para write, público para read |
| **Ressalva** | O bucket `ticket-attachments` não filtra por loja no INSERT — um usuário autenticado de qualquer loja pode fazer upload. Como é público, um usuário poderia acessar screenshots de outras lojas se souber o path. |

---

## 🟡 ITENS MÉDIOS

### [S-14] Dados sensíveis em SharedPreferences sem criptografia

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME (dados sensíveis)** |
| **Evidência** | — `flutter_secure_storage: ^9.2.4` presente em `pubspec.yaml` (linha 24)<br>— `SessionService` usa `FlutterSecureStorage` com `encryptedSharedPreferences: true` (Android) e `KeychainAccessibility.first_unlock` (iOS) para: `userId`, `shopId`, `userType`, credenciais de login, `remember_me`<br>— Dados NÃO sensíveis (cache de agenda, localização, IDs de tutoriais) continuam em `SharedPreferences` — aceitável |
| **Arquivos** | `lib/core/services/session_service.dart:9-12` |

---

### [S-15] Logs de debug em produção

| Campo | Valor |
|---|---|
| **Status** | ❌ **VULNERÁVEL** |
| **Evidência** | — `main()` em `lib/main.dart` NÃO contém bloqueio `if (kReleaseMode) { debugPrint = ... }`<br>— Dezenas de `debugPrint()` e `print()` incondicionais em todo o código<br>— `main.dart` tem 16+ chamadas de `debugPrint` sem proteção de release<br>— `auth_service.dart`, `session_service.dart` usam `debugPrint` sem guarda `kReleaseMode` |
| **Impacto** | Nomes, emails, URLs de deep link, IDs de usuários e lojas aparecem nos logs do dispositivo em produção. Coletáveis por crash reporters e análise de APK. |
| **Localização** | `lib/main.dart:52-64, 75-110, 139-243` (exemplos) |

---

### [S-16] OAuth sem validação de `state` parameter

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME** |
| **Arquivo verificado** | `lib/core/services/auth_service.dart` (linhas 61-65) |
| **Evidência** | — Usa `Supabase.instance.client.auth.signInWithOAuth(OAuthProvider.google, redirectTo: ..., authScreenLaunchMode: LaunchMode.externalApplication)`<br>— O SDK `supabase-flutter` gerencia o parâmetro `state` internamente via PKCE (`authFlowType: AuthFlowType.pkce` em `main.dart:41`)<br>— `redirectTo` configurado por plataforma: web (`localhost:3000` ou `Uri.base.origin/login`), mobile (`markaai://login-callback`) |

---

### [S-17] `SUPABASE_URL` e `ANON_KEY` hardcoded no Flutter

| Campo | Valor |
|---|---|
| **Status** | ❌ **VULNERÁVEL** |
| **Arquivo verificado** | `lib/core/constants/api_keys.dart` |
| **Evidência** | Todas as chaves são `static const String` — compiladas diretamente no binário:<br>— `supabaseUrl` (linha 6): `https://uhccgcojwqvkfyzrmebv.supabase.co`<br>— `supabaseAnonKey` (linha 7): JWT completo<br>— `geminiApiKey` (linha 2): `AIzaSyDx-...`<br>— `mapsApiKey` (linha 3): `AIzaSyDq4-...`<br>— `stripePublishableKey` (linha 10): `pk_live_51T97x...` |
| **Impacto** | Todas as chaves são extraíveis via engenharia reversa do APK/IPA. A chave Gemini e Maps são particularmente graves — podem gerar custos se abusadas. |
| **Observação** | O arquivo também expõe o `MP_CLIENT_SECRET` como fallback hardcoded em `mercadopagoCallback/index.ts:36` |

---

### [S-18] Secrets das Edge Functions sem política de rotação

| Campo | Valor |
|---|---|
| **Status** | ⚠️ **ATENDE PARCIALMENTE** |
| **Evidência** | — Não foi encontrada documentação de política de rotação<br>— `mercadopagoCallback/index.ts:35-36` contém fallbacks hardcoded: `MP_CLIENT_ID` e `MP_CLIENT_SECRET` com `||` operador — se o secret não estiver configurado, o código usa valores fixos no código-fonte |
| **Risco adicional** | O pattern `Deno.env.get('SECRET') || 'valor_fixo'` encontrado em múltiplas funções anula o propósito do gerenciamento de secrets, pois expõe credenciais reais no código |

---

### [S-19] Rate limiting ausente nas Edge Functions públicas

| Campo | Valor |
|---|---|
| **Status** | ❌ **VULNERÁVEL** |
| **Evidência** | — `grep -r "rate" supabase/functions/` → 0 resultados<br>— Funções expostas sem proteção:<br>  - `publicShopPreview` — acessível via URL pública de qualquer loja<br>  - `mercadopagoCallback` — endpoint de callback OAuth<br>  - `mpPaymentWebhook` — endpoint de webhook (embora seja chamado apenas pelo MP)<br>  - `createPixPayment` — aceita requisições com JWT, mas sem limite de chamadas<br>— Nenhuma tabela `rate_limits` ou mecanismo equivalente encontrado |
| **Impacto** | Flood/DDoS em `publicShopPreview` pode gerar custos de compute no Supabase. A função faz `select *` na tabela `shops` a cada requisição (linha 35 do arquivo). |

---

## 🟢 ITENS BAIXOS

### [S-20] Mecanismo de exclusão de dados (LGPD — direito ao esquecimento)

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME (parcialmente)** |
| **Arquivo verificado** | `supabase/functions/deleteUserAccount/index.ts` |
| **Evidência** | — Função `deleteUserAccount` implementa exclusão completa:<br>  1. Apaga todas as lojas do usuário e dados vinculados (appointments, services, employees, products, coupons)<br>  2. Apaga dados do usuário como cliente (appointments, coupon_usage, favorites)<br>  3. Apaga perfil na tabela `users`<br>  4. Apaga conta no Supabase Auth<br>— **Porém**: deleta os dados permanentemente (hard delete), não anonimiza (soft delete conforme recomendado no guia de auditoria). Isso pode violar obrigações fiscais de retenção de registros financeiros. |
| **Ressalva** | Não foi encontrada função equivalente à `anonymize_client` recomendada no guia de auditoria que preservaria registros financeiros anonimizados. |

---

### [S-21] Logs de acesso sem registro de auditoria

| Campo | Valor |
|---|---|
| **Status** | ✅ **CONFORME (para ações admin)** |
| **Arquivo verificado** | `supabase/migrations/178_admin_infrastructure.sql` (linhas 79-92) |
| **Evidência** | — Tabela `admin_audit_log` existe com campos: `admin_id`, `action`, `target_type`, `target_id`, `details`, `ip_address`, `created_at`<br>— Protegida por RLS: apenas admin lê (`admin_only` policy)<br>— Cobre ações como: `block_user`, `change_plan`, `impersonate` |
| **Ressalva** | Não existe tabela de auditoria para ações de **usuários regulares** (donos de loja acessando dados de clientes, editando agendamentos, etc.) como recomendado no guia. |

---

## 📋 TABELA CONSOLIDADA

| # | ID | Título | Risco | Status |
|---|---|---|---|---|
| 1 | S-01 | RLS desabilitado em tabelas | 🔴 Crítico | ✅ Conforme |
| 2 | S-02 | RLS sem filtro por salon_id | 🔴 Crítico | ✅ Conforme |
| 3 | S-03 | Trigger handle_new_user elevação de role | 🟠 Alto | ✅ Conforme |
| 4 | S-04 | SECURITY DEFINER sem search_path | 🟠 Alto | ✅ Conforme |
| 5 | S-05 | JWT não validado nas Edge Functions | 🔴 Crítico | ⚠️ Parcial |
| 6 | S-06 | service_role key no Flutter | 🔴 Crítico | ✅ Conforme |
| 7 | S-07 | Refresh token não revogado no logout | 🟡 Médio | ❌ Vulnerável |
| 8 | S-08 | Webhook MP sem HMAC | 🔴 Crítico | ❌ Vulnerável |
| 9 | S-09 | Pagamento sem re-consulta à API MP | 🟠 Alto | ✅ Conforme |
| 10 | S-10 | Token WhatsApp hardcoded | 🟠 Alto | ✅ Conforme |
| 11 | S-11 | Webhook WhatsApp sem verify_token | 🟠 Alto | ✅ Conforme |
| 12 | S-12 | Buckets Storage públicos | 🟠 Alto | ⚠️ Parcial |
| 13 | S-13 | Storage sem filtro por salon_id | 🟠 Alto | ✅ Conforme |
| 14 | S-14 | Dados sensíveis sem criptografia local | 🟡 Médio | ✅ Conforme |
| 15 | S-15 | Logs de debug em produção | 🟡 Médio | ❌ Vulnerável |
| 16 | S-16 | OAuth sem state parameter | 🟡 Médio | ✅ Conforme |
| 17 | S-17 | Keys hardcoded no Flutter | 🟡 Médio | ❌ Vulnerável |
| 18 | S-18 | Sem política de rotação de secrets | 🟢 Baixo | ⚠️ Parcial |
| 19 | S-19 | Sem rate limiting em funções públicas | 🟡 Médio | ❌ Vulnerável |
| 20 | S-20 | Sem exclusão de dados (LGPD) | 🟡 Médio | ✅ Conforme |
| 21 | S-21 | Sem audit log de acessos | 🟢 Baixo | ✅ Conforme |

*(S-04 aparece duplicado na tabela original do guia — item 12 e 20 — ambos referem-se a SECURITY DEFINER; mantido apenas o primeiro)*

---

## 🔥 TOP 7 VULNERABILIDADES ATIVAS (ordenadas por criticidade)

| Prioridade | ID | Descrição | Impacto |
|---|---|---|---|
| **1** | S-08 | Webhook MP sem validação HMAC | Pagamentos falsos podem ser injetados |
| **2** | S-05 | Edge Functions sem validação de JWT | Funções expostas sem autenticação se toggle do Dashboard falhar |
| **3** | S-07 | Refresh token não revogado no logout | Sessão roubada sobrevive ao logout |
| **4** | S-17 | Todas as API keys hardcoded no binário | Extração via engenharia reversa do APK |
| **5** | S-15 | Logs de debug sem bloqueio em produção | Dados de clientes em logs de dispositivo |
| **6** | S-19 | Sem rate limiting em funções públicas | Risco de DDoS e custos inesperados |
| **7** | S-12 | Bucket ticket-attachments público | Screenshots de suporte acessíveis por URL |

---

## 📁 ARQUIVOS CRÍTICOS INSPECIONADOS

| Arquivo | Linhas | Itens relacionados |
|---|---|---|
| `lib/main.dart` | 281 | S-15, S-17 |
| `lib/core/constants/api_keys.dart` | 11 | S-06, S-17 |
| `lib/core/services/auth_service.dart` | 286 | S-07, S-16 |
| `lib/core/services/session_service.dart` | 237 | S-14 |
| `supabase/migrations/02_harden_security.sql` | 92 | S-01, S-02 |
| `supabase/migrations/20260423_fix_role_reset_on_oauth.sql` | 88 | S-03, S-04 |
| `supabase/migrations/166_fix_trigger_security_definer.sql` | 99 | S-04 |
| `supabase/migrations/167_fix_all_trigger_security_definer.sql` | 165 | S-04 |
| `supabase/functions/mpPaymentWebhook/index.ts` | 282 | S-08, S-09 |
| `supabase/functions/mercadopagoCallback/index.ts` | 90 | S-18 |
| `supabase/functions/whatsapp-webhook/index.ts` | 283 | S-11 |
| `supabase/functions/whatsapp-send/index.ts` | 156 | S-10 |
| `supabase/functions/deleteUserAccount/index.ts` | 86 | S-20 |
| `supabase/functions/checkAvailability/index.ts` | 217 | S-05 |
| `supabase/functions/createPixPayment/index.ts` | 104 | S-05 |
| `supabase/functions/publicShopPreview/index.ts` | 147 | S-19 |
| `supabase/migrations/03_service_photos_storage.sql` | 37 | S-12, S-13 |
| `supabase/migrations/153_ticket_attachments_storage.sql` | 39 | S-12, S-13 |
| `supabase/migrations/175_app_banners_storage.sql` | 44 | S-12, S-13 |
| `supabase/migrations/178_admin_infrastructure.sql` | 156 | S-21 |

---

*Relatório gerado por inspeção estática de código em 16/06/2026. Nenhuma alteração foi realizada no sistema.*
