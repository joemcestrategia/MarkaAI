# 🔐 AUDITORIA DE SEGURANÇA — MarkaAI SaaS
> Stack: Flutter · Supabase (PostgreSQL, RLS, Auth, Storage, Edge Functions) · Meta Cloud API · Mercado Pago

---

## Como usar este documento com o Antygravity

Para cada item abaixo, informe ao agente:
> "Corrija o item **[ID]** conforme descrito na auditoria de segurança. Altere apenas o trecho indicado em `Arquivo / Trecho`. Não refatore nada além do escopo da correção. Me mostre o diff antes de aplicar."

---

## Legenda de classificação

| Campo | Opções |
|-------|--------|
| **Risco** | 🔴 Crítico · 🟠 Alto · 🟡 Médio · 🟢 Baixo |
| **Quebra o sistema?** | ❌ Não quebra · ⚠️ Pode quebrar · 💥 Quebra se errado |
| **Facilidade de correção** | ⚡ Fácil (< 30 min) · 🔧 Médio (< 2h) · 🏗️ Difícil (> 2h) |

---

## BLOCO 1 — Supabase: Row Level Security (RLS)

### [S-01] RLS ausente ou desabilitado em tabelas sensíveis

- **Risco:** 🔴 Crítico
- **Quebra o sistema?** ❌ Não quebra (só restringe acesso indevido)
- **Facilidade:** ⚡ Fácil
- **Impacto:** Qualquer usuário autenticado pode ler/editar dados de outros salões.
- **Como verificar:**
  ```sql
  SELECT tablename, rowsecurity
  FROM pg_tables
  WHERE schemaname = 'public' AND rowsecurity = false;
  ```
  Se retornar qualquer tabela que contenha dados de usuários (appointments, clients, profiles, salons, commissions, etc.), é uma falha crítica.

- **Correção — execute no SQL Editor do Supabase:**
  ```sql
  -- Habilite RLS em TODAS as tabelas de dados
  ALTER TABLE public.appointments ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.clients ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.salons ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.commissions ENABLE ROW LEVEL SECURITY;
  ALTER TABLE public.affiliates ENABLE ROW LEVEL SECURITY;
  -- Adicione aqui todas as tabelas que existirem no seu schema
  ```

- **Arquivo / Trecho:** Supabase Dashboard → SQL Editor → execute os comandos acima. Depois confirme via `pg_tables`.

---

### [S-02] Políticas RLS sem filtro por `salon_id` (vazamento entre salões)

- **Risco:** 🔴 Crítico
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** 🔧 Médio
- **Impacto:** Um dono de salão A pode ver agendamentos, clientes e comissões do salão B.
- **Padrão correto para políticas RLS:**
  ```sql
  -- Exemplo para tabela appointments
  -- Política de SELECT: só vê do próprio salão
  CREATE POLICY "select_own_salon_appointments"
  ON public.appointments
  FOR SELECT
  USING (
    salon_id IN (
      SELECT id FROM public.salons
      WHERE owner_id = auth.uid()
    )
  );

  -- Política de INSERT: só insere no próprio salão
  CREATE POLICY "insert_own_salon_appointments"
  ON public.appointments
  FOR INSERT
  WITH CHECK (
    salon_id IN (
      SELECT id FROM public.salons
      WHERE owner_id = auth.uid()
    )
  );

  -- Política de UPDATE: só atualiza do próprio salão
  CREATE POLICY "update_own_salon_appointments"
  ON public.appointments
  FOR UPDATE
  USING (
    salon_id IN (
      SELECT id FROM public.salons
      WHERE owner_id = auth.uid()
    )
  )
  WITH CHECK (
    salon_id IN (
      SELECT id FROM public.salons
      WHERE owner_id = auth.uid()
    )
  );

  -- Política de DELETE: só deleta do próprio salão
  CREATE POLICY "delete_own_salon_appointments"
  ON public.appointments
  FOR DELETE
  USING (
    salon_id IN (
      SELECT id FROM public.salons
      WHERE owner_id = auth.uid()
    )
  );
  ```

- **Instrução ao Antygravity:** "Gere políticas RLS equivalentes para todas as tabelas que possuem `salon_id`. Siga exatamente o padrão do item S-02 da auditoria."

---

### [S-03] Trigger `handle_new_user()` com SECURITY DEFINER sem proteção de `role`

- **Risco:** 🟠 Alto
- **Quebra o sistema?** ⚠️ Pode quebrar se alterado incorretamente
- **Facilidade:** 🔧 Médio
- **Impacto:** Um usuário pode manipular o campo `role` via metadados do OAuth e elevar seus próprios privilégios para `admin`.
- **Trecho atual a verificar (`supabase/migrations/` ou SQL Editor):**
  ```sql
  CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS trigger AS $$
  BEGIN
    INSERT INTO public.profiles (id, email, role, ...)
    VALUES (
      new.id,
      new.email,
      new.raw_user_meta_data->>'role',  -- ⚠️ PERIGOSO: campo vindo do client
      ...
    );
    RETURN new;
  END;
  $$ LANGUAGE plpgsql SECURITY DEFINER;
  ```

- **Correção — força role padrão, ignora o que vem do client:**
  ```sql
  CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS trigger AS $$
  BEGIN
    INSERT INTO public.profiles (id, email, role, created_at)
    VALUES (
      new.id,
      new.email,
      'owner',           -- ✅ SEMPRE força o papel padrão
      now()
    )
    ON CONFLICT (id) DO UPDATE
      SET email = EXCLUDED.email;
      -- NÃO atualiza role em conflito (protege contra re-login sobrescrever)
    RETURN new;
  END;
  $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
  ```

- **Arquivo / Trecho:** `supabase/migrations/[timestamp]_handle_new_user.sql` ou diretamente no SQL Editor. Procure pela função `handle_new_user`.

---

### [S-04] Funções `SECURITY DEFINER` sem `SET search_path = public`

- **Risco:** 🟠 Alto
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** ⚡ Fácil
- **Impacto:** Ataque de "search path injection" — um schema malicioso pode interceptar chamadas a funções do sistema.
- **Correção:** Todas as funções com `SECURITY DEFINER` devem ter:
  ```sql
  $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
  --                                     ^^^^^^^^^^^^^^^^^^^^^^^^
  --                                     Adicione isso em TODAS
  ```
- **Como encontrar todas as funções afetadas:**
  ```sql
  SELECT proname, prosecdef
  FROM pg_proc
  JOIN pg_namespace ON pg_proc.pronamespace = pg_namespace.oid
  WHERE nspname = 'public' AND prosecdef = true;
  ```

---

## BLOCO 2 — Supabase Auth & JWT

### [S-05] Validação de JWT nas Edge Functions feita apenas pelo gateway (não no código)

- **Risco:** 🔴 Crítico
- **Quebra o sistema?** ⚠️ Pode quebrar se desabilitado sem substituição
- **Facilidade:** 🔧 Médio
- **Impacto:** Se o toggle "Enforce JWT Verification" estiver desabilitado no Dashboard (para facilitar testes), qualquer pessoa pode chamar suas Edge Functions sem autenticação.
- **Verificação:** Supabase Dashboard → Edge Functions → selecione cada função → cheque se "Require JWT" está ativo.
- **Correção — valide o JWT dentro do código da função:**
  ```typescript
  // supabase/functions/[nome-da-funcao]/index.ts
  import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

  Deno.serve(async (req) => {
    // ✅ Validação explícita — não depende apenas do gateway
    const authHeader = req.headers.get('Authorization')
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } }
    )

    const { data: { user }, error } = await supabase.auth.getUser()
    if (error || !user) {
      return new Response(JSON.stringify({ error: 'Invalid token' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      })
    }

    // Prossiga com a lógica da função usando `user.id`
    // ...
  })
  ```

- **Arquivo / Trecho:** Cada arquivo `supabase/functions/*/index.ts`. Verifique se o padrão `supabase.auth.getUser()` está presente no início de cada função.

---

### [S-06] `service_role` key exposta no client Flutter

- **Risco:** 🔴 Crítico
- **Quebra o sistema?** ❌ Não quebra ao remover
- **Facilidade:** ⚡ Fácil
- **Impacto:** A `service_role` key bypassa completamente o RLS. Se estiver no app Flutter (mesmo em `.env`), qualquer pessoa com acesso ao APK pode extraí-la com engenharia reversa e ter acesso total ao banco.
- **Verificação — procure no projeto Flutter:**
  ```bash
  grep -r "service_role" lib/
  grep -r "SUPABASE_SERVICE_KEY" lib/
  grep -r "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" lib/  # prefixo comum de JWT
  ```
- **Regra:** O Flutter deve usar APENAS a `anon key`. A `service_role` deve ficar exclusivamente nas Edge Functions (via variável de ambiente Deno, nunca hardcoded).
- **Correção no Flutter:**
  ```dart
  // lib/main.dart ou lib/supabase_config.dart
  await Supabase.initialize(
    url: 'https://SEU_PROJECT.supabase.co',
    anonKey: 'eyJ...sua_anon_key...',  // ✅ Apenas anon key aqui
    // ❌ NUNCA: serviceRoleKey: '...'
  );
  ```

---

### [S-07] Refresh token não sendo revogado no logout

- **Risco:** 🟡 Médio
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** ⚡ Fácil
- **Impacto:** Se o usuário fizer logout mas o refresh token permanecer válido, uma sessão roubada pode continuar ativa por horas/dias.
- **Correção:**
  ```dart
  // Em qualquer ponto de logout no Flutter
  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut(
      scope: SignOutScope.global,  // ✅ Revoga TODAS as sessões, não só a atual
    );
  }
  ```

---

## BLOCO 3 — Webhooks (Mercado Pago)

### [S-08] Webhook do Mercado Pago sem validação de assinatura HMAC

- **Risco:** 🔴 Crítico
- **Quebra o sistema?** 💥 Quebra se implementado errado
- **Facilidade:** 🔧 Médio
- **Impacto:** Qualquer pessoa pode forjar uma requisição POST para sua Edge Function de pagamento, confirmando pagamentos falsos e liberando agendamentos sem cobrança real.
- **Como funciona a validação correta (Mercado Pago usa `x-signature` + `x-request-id`):**
  ```typescript
  // supabase/functions/mercadopago-webhook/index.ts
  import { createHmac } from 'https://deno.land/std@0.177.0/node/crypto.ts'

  Deno.serve(async (req) => {
    const secret = Deno.env.get('MP_WEBHOOK_SECRET')!  // Configure no Dashboard

    const xSignature = req.headers.get('x-signature') ?? ''
    const xRequestId = req.headers.get('x-request-id') ?? ''
    const url = new URL(req.url)
    const dataId = url.searchParams.get('data.id') ?? ''

    // Monta a string de validação conforme documentação MP
    const manifest = `id:${dataId};request-id:${xRequestId};ts:${xSignature.split(',').find(p => p.startsWith('ts='))?.split('=')[1] ?? ''};`

    const ts = xSignature.split(',').find(p => p.startsWith('ts='))?.split('=')[1] ?? ''
    const v1 = xSignature.split(',').find(p => p.startsWith('v1='))?.split('=')[1] ?? ''

    const signedManifest = `id:${dataId};request-id:${xRequestId};ts:${ts};`
    const expectedSignature = createHmac('sha256', secret)
      .update(signedManifest)
      .digest('hex')

    if (expectedSignature !== v1) {
      console.error('Webhook signature mismatch')
      return new Response('Unauthorized', { status: 401 })
    }

    // ✅ Assinatura válida — processe o evento
    const body = await req.json()
    // ...
  })
  ```

- **Arquivo / Trecho:** `supabase/functions/mercadopago-webhook/index.ts` (ou nome equivalente). Procure pelo handler do webhook de pagamento.

---

### [S-09] Confirmação de pagamento sem re-consulta à API do Mercado Pago

- **Risco:** 🟠 Alto
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** 🔧 Médio
- **Impacto:** O webhook informa que um pagamento foi aprovado, mas não prova que é verdade. A confirmação real deve ser feita consultando a API do MP com o ID recebido.
- **Correção — padrão "trust but verify":**
  ```typescript
  // Após validar a assinatura HMAC (S-08):
  const paymentId = body.data?.id
  if (!paymentId) return new Response('Bad Request', { status: 400 })

  // ✅ Re-consulta a API do MP para confirmar o status real
  const mpResponse = await fetch(
    `https://api.mercadopago.com/v1/payments/${paymentId}`,
    {
      headers: {
        Authorization: `Bearer ${Deno.env.get('MP_ACCESS_TOKEN')}`,
      },
    }
  )
  const payment = await mpResponse.json()

  if (payment.status !== 'approved') {
    console.log(`Payment ${paymentId} not approved: ${payment.status}`)
    return new Response('OK', { status: 200 })  // Responde 200 mas não processa
  }

  // Agora sim confirma o agendamento no banco
  ```

---

## BLOCO 4 — Meta Cloud API (WhatsApp)

### [S-10] Token de acesso WhatsApp hardcoded ou em variável não rotacionada

- **Risco:** 🟠 Alto
- **Quebra o sistema?** ❌ Não quebra ao corrigir
- **Facilidade:** ⚡ Fácil
- **Impacto:** Token exposto em código-fonte ou logs permite que terceiros enviem mensagens em nome dos salões dos seus clientes.
- **Verificação — procure no projeto:**
  ```bash
  grep -r "EAAG" lib/          # Prefixo comum de tokens Meta
  grep -r "whatsapp_token" lib/
  grep -r "Bearer EAA" supabase/
  ```
- **Regra:** O token Meta deve estar APENAS em variáveis de ambiente Deno nas Edge Functions. **Nunca** no Flutter.
- **Correção:**
  ```bash
  # Configure via CLI do Supabase
  supabase secrets set META_WHATSAPP_TOKEN="EAAG..."
  supabase secrets set META_PHONE_NUMBER_ID="123456789"
  supabase secrets set META_WABA_ID="987654321"
  ```
  ```typescript
  // Acesso correto dentro da Edge Function
  const token = Deno.env.get('META_WHATSAPP_TOKEN')!
  ```

---

### [S-11] Webhook do WhatsApp sem verificação do `hub.verify_token`

- **Risco:** 🟠 Alto
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** ⚡ Fácil
- **Impacto:** Sem verificação, qualquer origem pode enviar eventos falsos de WhatsApp para sua função (ex: confirmar agendamentos via mensagem forjada).
- **Correção:**
  ```typescript
  // supabase/functions/whatsapp-webhook/index.ts
  Deno.serve(async (req) => {
    const url = new URL(req.url)

    // Handshake de verificação Meta (GET)
    if (req.method === 'GET') {
      const mode = url.searchParams.get('hub.mode')
      const token = url.searchParams.get('hub.verify_token')
      const challenge = url.searchParams.get('hub.challenge')

      const verifyToken = Deno.env.get('META_VERIFY_TOKEN')!

      if (mode === 'subscribe' && token === verifyToken) {
        return new Response(challenge, { status: 200 })
      }
      return new Response('Forbidden', { status: 403 })
    }

    // Eventos reais (POST)
    if (req.method === 'POST') {
      // ✅ Opcionalmente valide também o X-Hub-Signature-256
      const signature = req.headers.get('X-Hub-Signature-256') ?? ''
      const body = await req.text()
      const secret = Deno.env.get('META_APP_SECRET')!

      const expectedSig = 'sha256=' + createHmac('sha256', secret)
        .update(body)
        .digest('hex')

      if (signature !== expectedSig) {
        return new Response('Unauthorized', { status: 401 })
      }

      const event = JSON.parse(body)
      // Processe o evento...
    }
  })
  ```

---

## BLOCO 5 — Supabase Storage

### [S-12] Buckets públicos expondo dados de clientes

- **Risco:** 🟠 Alto
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** ⚡ Fácil
- **Impacto:** Fotos de perfil, documentos, logotipos ou imagens de clientes armazenados em buckets públicos podem ser acessados por qualquer pessoa com a URL.
- **Verificação:** Supabase Dashboard → Storage → cheque quais buckets estão marcados como "Public".
- **Regra:**
  - Buckets com dados de clientes → **PRIVADO** + URLs assinadas (Signed URLs)
  - Apenas assets genéricos (logo do app, imagens padrão) → podem ser públicos
- **Correção no Flutter para gerar URL assinada:**
  ```dart
  // ✅ Gera URL temporária (ex: válida por 1 hora)
  final String signedUrl = await Supabase.instance.client
    .storage
    .from('clients-photos')  // bucket privado
    .createSignedUrl('path/to/photo.jpg', 3600);  // 3600 segundos = 1h
  ```

---

### [S-13] Políticas de Storage sem filtro por `salon_id`

- **Risco:** 🟠 Alto
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** 🔧 Médio
- **Impacto:** Um usuário autenticado pode acessar arquivos de outros salões se as políticas de Storage não restringirem por prefixo de path.
- **Padrão de organização de paths recomendado:**
  ```
  clients-photos/
  └── {salon_id}/
      └── {client_id}/
          └── foto.jpg
  ```
- **Política de Storage (SQL):**
  ```sql
  -- Apenas o dono do salão acessa os arquivos do próprio salão
  CREATE POLICY "salon_owner_storage_access"
  ON storage.objects
  FOR ALL
  USING (
    bucket_id = 'clients-photos'
    AND (storage.foldername(name))[1] IN (
      SELECT id::text FROM public.salons WHERE owner_id = auth.uid()
    )
  );
  ```

---

## BLOCO 6 — Flutter Client

### [S-14] Dados sensíveis em `SharedPreferences` / `hive` sem criptografia

- **Risco:** 🟡 Médio
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** 🔧 Médio
- **Impacto:** Em dispositivos com root ou via backup Android, dados como tokens, dados de clientes em cache e configurações podem ser extraídos.
- **Correção — use `flutter_secure_storage` para dados críticos:**
  ```yaml
  # pubspec.yaml
  dependencies:
    flutter_secure_storage: ^9.0.0
  ```
  ```dart
  // Para tokens e dados sensíveis
  const storage = FlutterSecureStorage();

  // Salvar
  await storage.write(key: 'session_token', value: token);

  // Ler
  final token = await storage.read(key: 'session_token');
  ```
- **O que guardar em secure storage:** tokens de sessão, phone number ID, qualquer chave de API que o usuário configure. Dados de cache não-sensíveis (lista de serviços, horários) podem continuar no Hive.

---

### [S-15] Logs de debug com dados de clientes chegando a produção

- **Risco:** 🟡 Médio
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** ⚡ Fácil
- **Impacto:** `print()` statements com nomes, telefones ou dados de agendamentos aparecem nos logs do dispositivo e podem ser coletados por crash reporters ou análise de APK.
- **Verificação:**
  ```bash
  grep -rn "print(" lib/
  grep -rn "debugPrint(" lib/
  grep -rn "log(" lib/
  ```
- **Correção — desabilite prints em produção:**
  ```dart
  // lib/main.dart
  void main() async {
    // ✅ Remove prints em release build
    if (kReleaseMode) {
      debugPrint = (String? message, {int? wrapWidth}) {};
    }
    // ...
    runApp(const MarkaAIApp());
  }
  ```

---

### [S-16] Deep links / OAuth redirect sem validação de `state` parameter

- **Risco:** 🟡 Médio
- **Quebra o sistema?** ⚠️ Pode quebrar se implementado errado
- **Facilidade:** 🔧 Médio
- **Impacto:** Login com Google sem parâmetro `state` é vulnerável a CSRF OAuth — um atacante pode vincular sua conta ao login de outra pessoa.
- **Verificação — procure o fluxo de Google OAuth:**
  ```bash
  grep -rn "signInWithOAuth" lib/
  grep -rn "google" lib/services/
  ```
- **Correção com `supabase-flutter` (já gerencia `state` internamente se configurado corretamente):**
  ```dart
  // ✅ Use o redirectTo correto e deixe o Supabase gerenciar o state
  await Supabase.instance.client.auth.signInWithOAuth(
    OAuthProvider.google,
    redirectTo: 'io.supabase.markaai://login-callback',
    authScreenLaunchMode: LaunchMode.externalApplication,
  );
  ```
  Confirme que o `redirectTo` está registrado nos Authorized Redirect URIs do Google Cloud Console E no Supabase Auth Settings.

---

## BLOCO 7 — Configuração e Infraestrutura

### [S-17] `SUPABASE_URL` e `ANON_KEY` hardcoded no código Flutter

- **Risco:** 🟡 Médio
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** ⚡ Fácil
- **Impacto:** A `anon key` exposta não é catastrófica (é pública por design), mas o URL exposto combinado com políticas RLS frouxas pode facilitar ataques direcionados.
- **Melhoria recomendada — use `--dart-define` em vez de hardcode:**
  ```bash
  # Build/run com variáveis externas
  flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
              --dart-define=SUPABASE_ANON_KEY=eyJ...
  ```
  ```dart
  // lib/config/supabase_config.dart
  class SupabaseConfig {
    static const String url = String.fromEnvironment('SUPABASE_URL');
    static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  }
  ```

---

### [S-18] Secrets das Edge Functions sem rotação definida

- **Risco:** 🟢 Baixo (mas importante para compliance LGPD)
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** ⚡ Fácil
- **Recomendação:** Defina uma política de rotação semestral para:
  - `MP_ACCESS_TOKEN` (Mercado Pago — pode ser configurado para expirar)
  - `META_WHATSAPP_TOKEN` (Meta — tokens de sistema não expiram mas devem ser rotacionados em caso de vazamento)
  - `META_APP_SECRET`
  - `META_VERIFY_TOKEN`
- **Crie um checklist no Notion/docs do projeto:** "Revisar e rotacionar secrets — todo semestre"

---

### [S-19] Rate limiting ausente nas Edge Functions públicas

- **Risco:** 🟡 Médio
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** 🔧 Médio
- **Impacto:** Funções sem autenticação (ex: verificação de disponibilidade pública, formulário de agendamento online) podem sofrer flood/DDoS, gerando custos inesperados no Supabase ou no Mercado Pago.
- **Correção — rate limiting simples com `upstash/ratelimit` ou via Supabase KV:**
  ```typescript
  // supabase/functions/public-booking/index.ts
  // Abordagem simples: cheque IP + timestamp no banco
  const clientIp = req.headers.get('x-forwarded-for') ?? 'unknown'
  const { count } = await supabase
    .from('rate_limits')
    .select('*', { count: 'exact', head: true })
    .eq('ip', clientIp)
    .gte('created_at', new Date(Date.now() - 60000).toISOString())  // últimos 60s

  if ((count ?? 0) > 10) {
    return new Response('Too Many Requests', { status: 429 })
  }
  ```

---

## BLOCO 8 — LGPD (Lei Geral de Proteção de Dados)

### [S-20] Sem mecanismo de exclusão de dados do cliente (direito ao esquecimento)

- **Risco:** 🟡 Médio (risco legal)
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** 🔧 Médio
- **Impacto:** A LGPD (Art. 18, IV) exige que o titular possa solicitar a exclusão de seus dados. Sem esse mecanismo, você está em não-conformidade.
- **Implementação mínima:**
  ```sql
  -- Função que anonimiza os dados (melhor que deletar — preserva histórico financeiro)
  CREATE OR REPLACE FUNCTION anonymize_client(client_uuid UUID)
  RETURNS void AS $$
  BEGIN
    UPDATE public.clients
    SET
      name = 'Cliente Removido',
      phone = NULL,
      email = NULL,
      notes = NULL,
      deleted_at = now()
    WHERE id = client_uuid;
  END;
  $$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
  ```
  ```dart
  // No Flutter, botão "Excluir minha conta" na tela de perfil
  await Supabase.instance.client.rpc('anonymize_client', params: {'client_uuid': clientId});
  ```

---

### [S-21] Logs de acesso sem registro (auditoria LGPD)

- **Risco:** 🟢 Baixo (mas recomendado)
- **Quebra o sistema?** ❌ Não quebra
- **Facilidade:** 🔧 Médio
- **Recomendação:** Para os 3 salões em produção, registre quem acessou quais dados de clientes e quando. Supabase tem logs nativos, mas uma tabela de auditoria simples ajuda em caso de incidentes:
  ```sql
  CREATE TABLE public.audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    action TEXT NOT NULL,           -- 'view_client', 'edit_appointment', etc.
    entity_type TEXT NOT NULL,      -- 'client', 'appointment'
    entity_id UUID,
    salon_id UUID,
    created_at TIMESTAMPTZ DEFAULT now()
  );
  ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
  -- Apenas admins leem, sistema insere
  ```

---

## RESUMO EXECUTIVO — Ordem de ataque para o Antygravity

| Ordem | ID | Título | Risco | Quebra? | Facilidade |
|-------|----|--------|-------|---------|------------|
| 1 | S-01 | RLS desabilitado em tabelas | 🔴 Crítico | ❌ | ⚡ |
| 2 | S-06 | `service_role` key no Flutter | 🔴 Crítico | ❌ | ⚡ |
| 3 | S-05 | JWT não validado nas Edge Functions | 🔴 Crítico | ⚠️ | 🔧 |
| 4 | S-08 | Webhook MP sem HMAC | 🔴 Crítico | 💥 | 🔧 |
| 5 | S-02 | RLS sem filtro por salon_id | 🔴 Crítico | ❌ | 🔧 |
| 6 | S-03 | Trigger handle_new_user elevação de role | 🟠 Alto | ⚠️ | 🔧 |
| 7 | S-09 | Pagamento sem re-consulta à API MP | 🟠 Alto | ❌ | 🔧 |
| 8 | S-10 | Token WhatsApp hardcoded | 🟠 Alto | ❌ | ⚡ |
| 9 | S-11 | Webhook WhatsApp sem verify_token | 🟠 Alto | ❌ | ⚡ |
| 10 | S-12 | Buckets Storage públicos | 🟠 Alto | ❌ | ⚡ |
| 11 | S-13 | Storage sem filtro por salon_id | 🟠 Alto | ❌ | 🔧 |
| 12 | S-04 | SECURITY DEFINER sem search_path | 🟠 Alto | ❌ | ⚡ |
| 13 | S-07 | Refresh token não revogado no logout | 🟡 Médio | ❌ | ⚡ |
| 14 | S-14 | Dados sensíveis sem criptografia local | 🟡 Médio | ❌ | 🔧 |
| 15 | S-15 | Logs de debug em produção | 🟡 Médio | ❌ | ⚡ |
| 16 | S-16 | OAuth sem state parameter | 🟡 Médio | ⚠️ | 🔧 |
| 17 | S-17 | Keys hardcoded no Flutter | 🟡 Médio | ❌ | ⚡ |
| 18 | S-19 | Sem rate limiting em funções públicas | 🟡 Médio | ❌ | 🔧 |
| 19 | S-20 | Sem exclusão de dados (LGPD) | 🟡 Médio (legal) | ❌ | 🔧 |
| 20 | S-04 | Sem audit log | 🟢 Baixo | ❌ | 🔧 |
| 21 | S-18 | Sem política de rotação de secrets | 🟢 Baixo | ❌ | ⚡ |
| 22 | S-21 | Sem audit log de acessos | 🟢 Baixo | ❌ | 🔧 |

---

## Prompt padrão para o Antygravity (copie e adapte)

```
Tarefa de segurança — MarkaAI SaaS

Corrija o item [S-XX] da auditoria de segurança conforme descrito abaixo.

Regras obrigatórias:
1. Altere APENAS o trecho indicado no campo "Arquivo / Trecho"
2. Não refatore nada além do escopo da correção
3. Me mostre o diff completo antes de aplicar qualquer mudança
4. Se precisar criar uma migration Supabase, use o padrão: supabase/migrations/[timestamp]_security_fix_sXX.sql
5. Não altere nenhuma política RLS existente sem listar primeiro quais serão afetadas

Descrição do item a corrigir:
[Cole aqui o bloco completo do item da auditoria]

Após a correção, gere um checklist de teste manual para validar que:
- A funcionalidade continua funcionando
- A vulnerabilidade foi fechada
```

---

*Gerado em: junho de 2026 — Revisar a cada 6 meses ou após mudanças significativas na arquitetura.*
