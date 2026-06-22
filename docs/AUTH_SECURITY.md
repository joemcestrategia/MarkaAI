# AUTH_SECURITY.md — Documentação de Segurança da Autenticação
## MarkaAI — Auditoria Completa (Março 2026)

---

## 1. Stack de Autenticação

| Componente | Tecnologia |
|---|---|
| Backend Auth | Supabase (GoTrue) — JWT automático, refresh token rotation nativa |
| Frontend | Flutter (supabase_flutter ^2.12.0) |
| OAuth Provider | Google (via Supabase OAuth redirect flow) |
| Armazenamento de tokens JWT | supabase_flutter (usa flutter_secure_storage internamente) |
| Armazenamento de sessão cache | flutter_secure_storage ^9.2.4 (userId, shopId, userType) |
| Funções de backend custom | Supabase Edge Functions (Deno/TypeScript) |
| Envio de e-mail | Resend API (via Edge Function `sendPasswordReset`) |

---

## 2. Fluxo de Autenticação

### 2.1 Login com E-mail/Senha
```
Flutter UI → AuthService.signIn() → supabase.auth.signInWithPassword()
         → Supabase GoTrue valida credenciais + retorna access_token (JWT, 1h) + refresh_token
         → SDK armazena tokens em flutter_secure_storage automaticamente
         → SessionService.saveLogin() armazena userId, userType, shopId em secure storage
         → AppRouter redireciona para BusinessHomePage ou ClientHomePage conforme role
```

### 2.2 Login com Google OAuth
```
Flutter UI → AuthService.signInWithGoogleOAuth() → supabase.auth.signInWithOAuth(google)
         → Redireciona para consent screen do Google
         → Google retorna para callback URL do Supabase
         → Supabase troca code por tokens e redireciona para /login-callback (mobile) ou origine (web)
         → AuthGate (StreamBuilder on onAuthStateChange) detecta sessão e roteia
```

### 2.3 Recuperação de Senha
```
ForgotPasswordPage → AuthService.sendPasswordReset(email)
         → Edge Function `sendPasswordReset` (Supabase Admin API + Resend)
         → supabase.auth.admin.generateLink({ type: 'recovery' })
         → E-mail enviado via Resend com link de recovery (expira em 1h)
         → Usuário clica no link → /reset-password com #access_token=...&type=recovery
         → _PasswordRecoveryGate processa o fragment → emite evento PASSWORD_RECOVERY
         → ResetPasswordPage → supabase.auth.updateUser({ password: nova })
         → Redireciona para /login
```

### 2.4 Logout
```
AuthService.signOut() → ShopDataCacheService.invalidateAll()
                      → SessionService.logout() (apaga secure storage + SharedPreferences)
                      → supabase.auth.signOut() (invalida refresh token no servidor)
```

---

## 3. Decisões de Segurança Implementadas

### 3.1 Gerenciamento de JWT
- **Access Token**: gerado pelo Supabase GoTrue, expiração padrão de 1 hora
- **Refresh Token**: rotacionado a cada uso (Supabase padrão — Refresh Token Rotation ativado)
- **Algoritmo**: RS256 (Supabase usa RS256 por padrão; não configurável pelo app)
- **Payload**: contém apenas `sub` (UUID), `role`, `aud`, `exp`, `iat`. Nenhum dado sensível
- **Verificação**: toda chamada ao Supabase valida o JWT automaticamente via RLS

### 3.2 Senhas
- **Hashing**: gerenciado pelo Supabase GoTrue com bcrypt (custo adaptativo)
- **Mínimo de caracteres**: 8 (reforçado no frontend Flutter)
- **Sem trim**: senhas NÃO são modificadas antes de enviar ao Supabase
- **Sem log**: nenhum `print()` ou `debugPrint()` expõe senhas em nenhuma parte do código

### 3.3 Proteção contra Enumeração de Usuários
- **Login**: erro genérico "E-mail ou senha inválidos" para qualquer falha de credenciais
- **Esqueci minha senha**: retorna HTTP 200 com `{ success: true }` independente do e-mail existir
- **Cadastro com e-mail duplicado**: Supabase retorna erro que é mapeado para "Este e-mail já está em uso"

### 3.4 Armazenamento de Tokens no Flutter
| Dado | Armazenamento |
|---|---|
| access_token / refresh_token | flutter_secure_storage (via supabase_flutter SDK) |
| userId, shopId, userType | flutter_secure_storage (SessionService) |
| Localização último acesso | SharedPreferences (não sensível) |

- **Android**: `encryptedSharedPreferences: true` (EncryptedSharedPreferences da AndroidX)
- **iOS**: `KeychainAccessibility.first_unlock` (Keychain)
- **Web**: Supabase SDK usa localStorage (limitação de plataforma aceita — sem acesso nativo ao Keychain)

### 3.5 Autorização em Edge Functions
- **deleteUserAccount**: verifica JWT via `createSupabaseClient(req)`, valida que `callerUser.id === userId` ou que o caller tem role `admin`. Retorna 403 caso contrário
- **sendPasswordReset**: não requer autenticação (usuário não tem sessão ao solicitar reset). Requer anon key via cabeçalho `apikey`
- **Funções de pagamento**: listadas em `config.toml` com `verify_jwt = false` (necessário para webhooks de provedores externos)

---

## 4. Variáveis de Ambiente Necessárias

### Supabase (configuradas no dashboard)
| Variável | Descrição |
|---|---|
| `SUPABASE_URL` | URL da instância Supabase |
| `SUPABASE_ANON_KEY` | Chave pública (safe para expor no Flutter) |
| `SUPABASE_SERVICE_ROLE_KEY` | Chave de admin (NUNCA expor no Flutter) |

### Edge Functions (Supabase Secrets)
| Variável | Descrição |
|---|---|
| `RESEND_API_KEY` | Chave da API Resend para envio de e-mails |
| `EMAIL_FROM` | Remetente dos e-mails (ex: `MarkaAI <no-reply@markaai.com.br>`) |
| `APP_URL` | URL base do app (ex: `https://markaai.com.br`) |

---

## 5. Vulnerabilidades Encontradas e Corrigidas

### ❌ CRÍTICAS (corrigidas)

| # | Vulnerabilidade | Arquivo | Correção |
|---|---|---|---|
| 1 | **Email enumeration via login**: `_handleLoginClick` consultava `public.users` antes do signIn. Se e-mail não existia, mostrava "E-mail não encontrado. Crie sua conta!" | `login_page.dart` | Removida a pré-consulta. Vai direto ao `signIn()`; qualquer falha exibe mensagem genérica |
| 2 | **Email enumeration via reset de senha**: `sendPasswordReset` retornava HTTP 404 com mensagem explícita quando e-mail não cadastrado | `sendPasswordReset/index.ts` | Retorna HTTP 200 `{ success: true }` para qualquer e-mail — sem revelar existência |
| 3 | **Account Takeover via deleteUserAccount**: `userId` vinha apenas do body da requisição sem verificar se o chamador era o dono da conta | `deleteUserAccount/index.ts` | Adicionada verificação de JWT: extrai `callerUser` do token Bearer, compara com `userId`. Retorna 403 se não autorizado |

### ⚠️ IMPORTANTES (corrigidas)

| # | Problema | Arquivo | Correção |
|---|---|---|---|
| 4 | Mensagem "Senha incorreta." confirmava que o e-mail era válido | `login_page.dart` | Substituída por "E-mail ou senha inválidos." |
| 5 | `_handleAuthError` em `auth_service.dart` tinha handler separado para `user not found` | `auth_service.dart` | Fundido com o handler de `invalid login credentials` em mensagem genérica |
| 6 | `password.trim()` em `signIn` e `signUp` modificava senhas silenciosamente | `auth_service.dart` | Removido `password.trim()` de ambos |
| 7 | Mínimo de senha era 6 caracteres (abaixo do recomendado) | `login_page.dart`, `reset_password_page.dart` | Alterado para 8 caracteres |
| 8 | `_routeUser` expunha stack trace: `_showError("Erro de conexão: $e")` | `login_page.dart` | Substituído por mensagem genérica sem `$e` |
| 9 | `userId`, `shopId`, `userType` armazenados em `SharedPreferences` (não criptografado) | `session_service.dart` | Migrados para `flutter_secure_storage` com `encryptedSharedPreferences` no Android e Keychain no iOS |
| 10 | Código morto Firebase no router (`/__/` path e `?mode=resetPassword&oobCode=`) | `app_router.dart` | Removido — a autenticação é 100% Supabase |

---

## 6. Itens Verificados (sem vulnerabilidade)

| Item | Status | Observação |
|---|---|---|
| JWT_SECRET/algoritmo | ✅ OK | Gerenciado pelo Supabase (RS256, rotação automática) |
| Access token expiration | ✅ OK | 1 hora (padrão Supabase) |
| Refresh token rotation | ✅ OK | Ativado por padrão no Supabase |
| Refresh token invalidado no logout | ✅ OK | `supabase.auth.signOut()` invalida o token no servidor |
| Bcrypt + salt único | ✅ OK | Gerenciado pelo GoTrue (bcrypt, salt por usuário) |
| Senhas não logadas | ✅ OK | Nenhum `print(password)` encontrado no codebase |
| Google client_secret no servidor | ✅ OK | Gerenciado pelo Supabase (nunca exposto no Flutter) |
| Google `state` parameter CSRF | ✅ OK | Gerenciado pelo Supabase OAuth redirect flow |
| Token de reset de uso único | ✅ OK | Supabase invalida o token após primeiro uso |
| Token de reset criptograficamente seguro | ✅ OK | Gerado pelo Supabase Admin API (`generateLink`) |
| Token de reset expiração curta | ✅ OK | 1 hora (configurável no dashboard Supabase) |
| Botão submit desabilitado durante loading | ✅ OK | `_isLoading` desabilita botões em todos os formulários |
| Campos de senha com toggle mostrar/ocultar | ✅ OK | Implementado em login, cadastro e reset |
| Validação de e-mail no frontend | ✅ OK | Verifica `contains('@')` antes de enviar |
| RLS (Row Level Security) no Supabase | ✅ OK | Proteção server-side em todas as tabelas |

---

## 7. Itens Pendentes / Risco Aceito

| Item | Risco | Justificativa / Ação Recomendada |
|---|---|---|
| **Rate limiting** nos endpoints de auth | Médio | Supabase não tem rate limiting nativo nas Edge Functions. Recomendado: adicionar Cloudflare ou configurar rate limiting via `supabase.toml` em produção |
| **CORS `Access-Control-Allow-Origin: '*'`** nas Edge Functions | Baixo-Médio | Necessário para o app Flutter Web (PWA) funcionar. Mitigado pelo requisito obrigatório do `apikey` header. Ação futura: restringir para `https://markaai.com.br` em produção |
| **Sem certificate pinning** no Flutter | Baixo | Protegeria contra MITM em redes não confiáveis. Aceito pois o app usa HTTPS + Supabase SDK gerencia conexões. Documentado como risco aceito |
| **`verified: true` sem verificação de e-mail** | Baixo | Campo de metadados interno. Não bloqueia funcionalidades críticas. Supabase pode ser configurado para exigir verificação de e-mail no dashboard |
| **2FA (Two-Factor Authentication)** | Melhoria | Supabase suporta TOTP nativo. Campos `twoFactorEnabled` e `twoFactorSecret` podem ser adicionados ao schema para implementação futura |
| **Auditoria de logins** | Melhoria | Tabela de log de tentativas de login (IP, timestamp, resultado) não existe. Recomendado criar `auth_logs` table com trigger SQL |
| **Notificação de novo dispositivo** | Melhoria | E-mail ao usuário em novo login não implementado. Pode ser adicionado como Edge Function via webhook de `auth.users` |
| **Limpeza de tokens expirados** | Melhoria | Supabase gerencia automaticamente. Nenhuma ação necessária |

---

## 8. Resumo Executivo da Auditoria

| Categoria | Encontrados | Corrigidos |
|---|---|---|
| Vulnerabilidades Críticas | **3** | **3** ✅ |
| Problemas Importantes | **7** | **7** ✅ |
| Melhorias Futuras | 5 | — |
| **Total de issues resolvidos** | **10** | **10** ✅ |

---

*Documento gerado automaticamente em 30/03/2026 — Revisão necessária após qualquer mudança significativa na arquitetura de autenticação.*
