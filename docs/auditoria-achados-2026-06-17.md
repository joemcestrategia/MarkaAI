# 🔐 RELATÓRIO DE AUDITORIA DE SEGURANÇA — MarkaAI

**Data:** 17 Jun 2026 | **Stack:** Flutter + Supabase
**Base:** `auditoria-seguranca-markaai.md` (10 seções)
**Método:** Inspeção estática do código-fonte (`lib/`, `supabase/functions/`, `supabase/migrations/`, `scripts/`, histórico git)
**Nota:** Queries SQL do Supabase (seções 1.1, 1.2, 1.3, 2.1, 2.2, 4.3, 5.1) exigem acesso ao painel Supabase — **não foram executadas** nesta auditoria.

---

## RESUMO EXECUTIVO

O código demonstra maturidade significativa em segurança, com múltiplas migrações de RLS e correções de SECURITY DEFINER. Foram encontrados **7 achados críticos**, **6 de atenção** e **2 itens OK mas com ressalva**. O principal risco é um vazamento de dados entre tenants via policy `SELECT USING (true)` na tabela `appointments` (migração 197).

---

## SEÇÃO 9 — TABELA DE ACHADOS

| # | Item | Seção | Status | Evidência | Ação corretiva | Prioridade |
|---|---|---|---|---|---|---|
| 1 | `appointments` SELECT `USING (true)` expõe dados entre tenants | 1.2 | 🔴 | `migrations/197_fix_appointments_rls_for_booking.sql:13-15` — policy `appointments_public_read` com `USING (true)` para todo `authenticated` | Restringir SELECT para `client_id = auth.uid()` OU `is_shop_owner(shop_id)` — o cálculo de disponibilidade pode usar uma RPC SECURITY DEFINER | Alta |
| 2 | `appointments` INSERT com `WITH CHECK (true)` (migração 193) | 1.2 | 🔴 | `migrations/193_enable_rls_phase2_to_4.sql:97-98` — qualquer usuário autenticado insere em qualquer loja | Adicionar validação de `shop_id` no `WITH CHECK` | Alta |
| 3 | Credenciais expostas em `scripts/import_supabase_users.js` | 3.2 | 🔴 | Linha 8: URL + key do Supabase; linhas 15-19: parâmetros Firebase Scrypt (signerKey, saltSeparator, rounds, memoryCost) | Remover do repositório, adicionar ao `.gitignore`, rotacionar Firebase signerKey | Alta |
| 4 | `api_keys.dart` no histórico git (4 commits) | 3.3 | 🔴 | Commits: `2fdae463`, `734f88c6`, `9e9f4a93`, `d72e9e27` — expõem Gemini, Maps, Stripe e Supabase keys | Rotacionar TODAS as chaves expostas no histórico (Gemini, Maps, Stripe publishable) e rodar `git filter-branch` / BFG para limpar histórico | Alta |
| 5 | `whatsapp-send` Edge Function sem validação de JWT | 3.1 | 🔴 | Usa `SUPABASE_SERVICE_ROLE_KEY` diretamente (linhas 34-35, 58-59), sem `auth.getUser()` | Se "Verify JWT" estiver desabilitado no dashboard, qualquer pessoa pode enviar WhatsApp. Habilitar JWT E adicionar validação no código | Alta |
| 6 | `mpPaymentWebhook` sem validação de assinatura HMAC | 4.1 | 🔴 | `supabase/functions/mpPaymentWebhook/index.ts:37` — processa `req.json()` direto, sem validar header `x-signature` | Implementar validação HMAC-SHA256 conforme documentação do Mercado Pago | Alta |
| 7 | JWT anon key hardcoded em `nfse_config_screen.dart` | 3.2/6.2 | 🔴 | `lib/modules/fiscal/nfse_config_screen.dart:391` — JWT Supabase em texto plano para chamada HTTP manual | Substituir `http.post()` por chamada via `Supabase.instance.client.functions.invoke()` que usa o token da sessão | Alta |
| 8 | `print()`/`debugPrint()` sem guarda `kReleaseMode` em produção | 4.2 | 🟡 | 40+ chamadas de `print()`/`debugPrint()` em `lib/` — `main.dart` (16+ chamadas), `auth_service.dart`, `session_service.dart`, `coupon_service.dart` | Adicionar `if (kDebugMode)` ou substituir por logger com níveis; bloquear `debugPrint` em release: `if (kReleaseMode) { debugPrint = (_, __) {} }` | Média |
| 9 | Firebase API keys hardcoded no binário Flutter | 6.2 | 🟡 | `lib/firebase_options.dart` — 5 chaves `apiKey` em texto plano (padrão Firebase, mas extraível do APK) | Restringir chaves Firebase por app ID + SHA-1 no console; documentar como risco aceito | Média |
| 10 | Refresh token sobrevive ao logout | 5.2 | 🟡 | `lib/core/services/auth_service.dart:188` — `_supabase.auth.signOut()` sem `scope` global | Usar `signOut(scope: SignOutScope.global)` ou documentar como limitação conhecida do Supabase (JWT stateless) | Média |
| 11 | Rate limiting ausente nas Edge Functions | — | 🟡 | Nenhuma referência a `rate` em `supabase/functions/` — funções como `publicShopPreview` e `whatsapp-send` expostas sem limite | Implementar rate limiting por IP/shop_id ou configurar no gateway Supabase se disponível | Média |
| 12 | `emitter-nfse` Edge Function chamada com `anon` key JWT em vez do token da sessão | 6.2 | 🟡 | `nfse_config_screen.dart:391` — usa JWT `anon` para função que emite NFS-e (operação administrativa) | A emissão de NFS-e deve usar token de usuário autenticado (admin/dono) | Média |
| 13 | `whatsapp-webhook` — sem JWT (esperado) mas usa `service_role` internamente | 3.1 | 🟡 | Usa HMAC + `verify_token` corretamente, mas internamente opera como admin | Documentar no relatório: risco controlado, desde que "Verify JWT" no dashboard esteja desabilitado (é webhook público) | Baixa |
| 14 | SessionService: credenciais em `FlutterSecureStorage` | 6.1 | 🟢 | `session_service.dart:9-12` — `encryptedSharedPreferences: true` (Android) + `KeychainAccessibility.first_unlock` (iOS) | — | — |
| 15 | `service_role` NÃO está no Flutter | 3.2 | 🟢 | `grep -r "service_role" lib/` → 0 resultados. Apenas `sb_publishable_` (anon key) no client | — | — |
| 16 | WhatsApp webhook: validação HMAC-SHA256 | 4.1 | 🟢 | `whatsapp-webhook/index.ts:12-37` — `verifyMetaSignature()` com Web Crypto API | — | — |
| 17 | Bug `role` sobrescrito no trigger OAuth — **corrigido** | 2.2 | 🟢 | `migrations/20260423_fix_role_reset_on_oauth.sql:38-48` — `ON CONFLICT DO UPDATE` não toca em `role` | — | — |
| 18 | SECURITY DEFINER functions com `SET search_path = public` | 2.1 | 🟢 | `migrations/167_fix_all_trigger_security_definer.sql` — 4 funções corrigidas | — | — |
| 19 | `api_keys.dart` no `.gitignore` | 3.3 | 🟢 | `.gitignore:57` — `lib/core/constants/api_keys.dart` | — (mas histórico git ainda contém as keys — ver item #4) | — |
| 20 | Mercado Pago: `card_number`/`cvv` fluem para API do MP sem armazenamento local | 4.1 | 🟢 | `mercado_pago_service.dart:147,312` — pass-through apenas | — | — |
| 21 | Tabela `shop_activity_log` existe para auditoria de ações de loja | 7.2 | 🟢 | `migrations/174_create_shop_activity_log.sql` | — | — |
| 22 | Plano de resposta a incidente | 7.3 | 🔴 C/I | Não encontrado no repositório | Criar documento formal (LGPD Art. 48 exige) | Alta |
| 23 | Política de Privacidade / Termos de Uso | 8 | ❓ | Não verificável via código-fonte | Confirmar se estão publicados e linkados no app | Média |
| 24 | Mecanismo de exclusão de dados do titular (LGPD Art. 18) | 8 | 🟡 | Função `deleteUserAccount` existe (hard delete) mas não anonimiza — pode violar retenção fiscal | Implementar `anonymize_client` que preserve registros financeiros anonimizados | Média |
| 25 | MFA para contas admin/dono de salão | 5.3 | 🟡 | Não encontrado — mesmo fluxo de senha para admin e cliente | Documentar como gap, planejar MFA para papéis com acesso a dados financeiros | Baixa |
| 26 | Bucket `ticket-attachments` potencialmente público | 4.3 | 🟡 | Snapshots de suporte podem conter dados de pagamento/clientes | Verificar no painel Supabase se `public = false` e políticas de Storage adequadas | Média |

---

## SEÇÃO 10 — SÍNTESE FINAL

### Achados críticos (🔴)

1. **(#1) RLS `appointments_public_read` com `USING (true)`** — `migrations/197:13-15` — Qualquer usuário autenticado consegue listar TODOS os agendamentos de TODAS as lojas. É o vetor de vazamento mais grave encontrado.
2. **(#2) INSERT em `appointments` com `WITH CHECK (true)`** — `migrations/193:97-98` — Usuário autenticado pode injetar agendamento em loja alheia.
3. **(#3) `import_supabase_users.js` com credenciais reais no repositório** — URL Supabase + chave + parâmetros Firebase Scrypt expostos.
4. **(#4) Histórico git contém `api_keys.dart` com 5 chaves reais** — Rotação de todas as chaves é necessária.
5. **(#5) `whatsapp-send` Edge Function sem validação de JWT** — Depende exclusivamente do toggle "Verify JWT" no dashboard.
6. **(#6) Webhook Mercado Pago sem validação HMAC** — Qualquer POST na URL `mpPaymentWebhook` é processado.
7. **(#7) JWT hardcoded em `nfse_config_screen.dart`** — Chamada HTTP manual à Edge Function com token fixo no código.

### Achados de atenção (🟡)

- Logs de debug sem guarda de produção (40+ ocorrências)
- Firebase API keys hardcoded no binário (risco inerente ao Flutter/Firebase)
- Refresh token sobrevive ao logout (limitação Supabase)
- Rate limiting ausente
- `emitter-nfse` chamada com token `anon` em vez do token do usuário
- `whatsapp-webhook` opera com `service_role` (risco controlado)
- Bucket `ticket-attachments` — verificar se é público
- Sem MFA para admins

### Gaps de compliance LGPD (não-técnicos)

- **Plano de resposta a incidente:** ausente (🔴)
- **Política de Privacidade / Termos de Uso:** não verificável via código
- **Mecanismo de exclusão (Art. 18):** existe via `deleteUserAccount` mas faz hard delete (sem anonimização)
- **Mecanismo de portabilidade (Art. 18):** não encontrado
- **Base legal por finalidade:** não documentada no código
- **DPO nomeado:** não encontrado

### Plano de remediação sugerido (ordem de prioridade)

1. **Restringir `appointments_public_read`** — trocar `USING (true)` por política segmentada por `client_id` + `shop_id`
2. **Adicionar `WITH CHECK` no INSERT de appointments** — validar `shop_id`
3. **Remover `import_supabase_users.js` do repositório** + rotacionar credenciais Firebase
4. **Rotacionar TODAS as chaves do `api_keys.dart`** que estão no histórico git
5. **Implementar validação HMAC no webhook Mercado Pago** (`mpPaymentWebhook`)
6. **Adicionar validação JWT no `whatsapp-send`** + verificar toggle "Verify JWT" no dashboard
7. **Substituir `http.post()` manual no `nfse_config_screen.dart`** por `supabase.functions.invoke()`
8. **Criar documento de plano de resposta a incidente** (LGPD Art. 48)
9. **Adicionar guarda `kReleaseMode` nos logs** de debug
10. **Publicar Política de Privacidade e Termos de Uso** se ainda não publicados

---

## Itens que exigem acesso ao painel Supabase (não verificados)

- Query RLS (`pg_tables`) — Seção 1.1
- Policies ativas (`pg_policies`) — Seção 1.2
- Teste prático de RLS cross-tenant — Seção 1.3
- Funções `SECURITY DEFINER` ativas no banco — Seção 2.1
- Configuração JWT por Edge Function no dashboard — Seção 3.1
- Buckets Storage (`storage.buckets`) — Seção 4.3
- Configuração de Auth (email confirmations, rate limiting) — Seção 5.1
- Membros da organização Supabase — Seção 7.1
