# MarkaAI — Guia de Configuração: Notificações WhatsApp + Email

---

## Passo 1 — Configurar Meta Cloud API (WhatsApp)

### 1.1 Criar o App na Meta
1. Acesse [developers.facebook.com](https://developers.facebook.com)
2. Clique em **"Meus Apps" → "Criar App"**
3. Selecione **"Empresa"** e clique em Avançar
4. Dê o nome **"MarkaAI Notifications"** e crie o app
5. Na tela de produtos, clique em **"Configurar"** no card do WhatsApp

### 1.2 Registrar seu número
1. Em **WhatsApp → Configuração da API**, adicione seu número de telefone do MarkaAI
2. Verifique o número via SMS
3. Anote o **Phone Number ID** (ex: `123456789012345`)
4. Anote o **WhatsApp Business Account ID**

### 1.3 Gerar Token permanente
1. Vá em **Configurações → Básico** do seu App
2. Em **Usuários do Sistema**, crie um usuário admin
3. Gere um token com permissões: `whatsapp_business_messaging`, `whatsapp_business_management`
4. Guarde o token — ele não aparece novamente

### 1.4 Criar os Templates de Mensagem
Acesse [business.facebook.com](https://business.facebook.com) → **WhatsApp Manager → Modelos de Mensagem**

Crie os 4 templates abaixo (categoria UTILITY para confirmação/lembrete/cancelamento, AUTHENTICATION para OTP):

**markaai_confirmation** (Utilidade):
```
Olá {{1}}, seu agendamento foi confirmado! 🎉
Salão: {{2}}
Serviço: {{3}}
Data: {{4}} às {{5}}
Profissional: {{6}}
— MarkaAI
```

**markaai_reminder** (Utilidade):
```
Olá {{1}}! Lembrete: seu agendamento no {{2}} é amanhã.
Serviço: {{3}} — {{4}} às {{5}}
Até lá! ✂️ — MarkaAI
```

**markaai_cancellation** (Utilidade):
```
Olá {{1}}, seu agendamento no {{2}} do dia {{3}} às {{4}} foi cancelado.
Para reagendar acesse o app MarkaAI.
```

**markaai_otp** (Autenticação):
```
Seu código de verificação MarkaAI é: {{1}}
Válido por 10 minutos. Não compartilhe com ninguém.
```

---

## Passo 2 — Configurar Resend (Email)

### 2.1 Criar conta
1. Acesse [resend.com](https://resend.com) e crie sua conta gratuita

### 2.2 Verificar domínio
1. Vá em **Domains → Add Domain**
2. Digite `markaai.com.br`
3. Adicione os registros DNS fornecidos no seu provedor de domínio
4. Aguarde verificação (até 24h, geralmente minutos)

### 2.3 Gerar API Key
1. Vá em **API Keys → Create API Key**
2. Dê o nome **"MarkaAI Production"**
3. Permissão: **"Sending access"**
4. Copie a chave gerada (começa com `re_`)

---

## Passo 3 — Configurar Firebase Secrets

Execute estes comandos na raiz do seu projeto Firebase:

```bash
# Configure cada secret individualmente
# O Firebase vai pedir que você digite o valor

firebase functions:secrets:set WHATSAPP_TOKEN
# Cole: seu token permanente da Meta

firebase functions:secrets:set WHATSAPP_PHONE_ID
# Cole: seu Phone Number ID (só números)

firebase functions:secrets:set WHATSAPP_BUSINESS_ID
# Cole: seu WhatsApp Business Account ID

firebase functions:secrets:set RESEND_API_KEY
# Cole: sua API Key do Resend (re_xxx...)

firebase functions:secrets:set EMAIL_FROM
# Cole: noreply@markaai.com.br
```

---

## Passo 4 — Instalar dependências e fazer deploy

```bash
cd functions
npm install
npm run build
cd ..
firebase deploy --only functions
```

---

## Passo 5 — Testar

### Testar WhatsApp (via Firebase Console)
Vá em **Firebase Console → Functions → sendOTPCode** e chame com:
```json
{ "phone": "5531999999999" }
```

### Testar Email (via Firebase Console)
Vá em **Firebase Console → Functions → sendReminderManual** e chame com:
```json
{ "appointmentId": "ID_DE_UM_AGENDAMENTO_REAL" }
```

---

## Estrutura dos arquivos criados

```
functions/src/
├── index.ts                          ← Exporta todas as functions
├── types.ts                          ← Interfaces TypeScript
├── services/
│   ├── whatsappService.ts            ← Meta Cloud API
│   └── emailService.ts               ← Resend
├── templates/
│   └── emailTemplates.ts             ← HTML dos emails
└── notifications/
    ├── appointmentTriggers.ts        ← Triggers Firestore
    └── otpFunctions.ts               ← OTP send + verify
```

---

## Fluxo automático após deploy

| Evento no Firestore | Ação automática |
|---|---|
| `appointments/{id}` criado | Envia confirmação via WhatsApp + Email |
| `appointments/{id}` status → `cancelled` | Envia cancelamento via WhatsApp + Email |
| Chamada `sendOTPCode` | Gera código e envia via WhatsApp |
| Chamada `verifyOTPCode` | Valida código e marca como verificado |
| Chamada `sendReminderManual` | Envia lembrete via WhatsApp + Email |

---

*MarkaAI — markaai.com.br*
