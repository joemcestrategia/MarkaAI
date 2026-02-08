# 🔧 Como Configurar a Google Places API Key

## ⚠️ IMPORTANTE: Passo Obrigatório!

O erro **500** que você recebeu ocorre porque a **Google Places API Key** ainda não foi configurada.

---

## 📋 Passo 1: Obter a API Key no Google Cloud

### 1.1. Acesse o Google Cloud Console
🔗 https://console.cloud.google.com/

### 1.2. Crie ou Selecione um Projeto
- Se não tiver projeto, clique em "Criar Projeto"
- Dê um nome: **"MarkaAI"** (ou qualquer nome)
- Clique em "Criar"

### 1.3. Ative a Places API
1. No menu lateral → **"APIs e Serviços"** → **"Biblioteca"**
2. Pesquise: **"Places API"**
3. Clique em **"Places API"**
4. Clique em **"ATIVAR"**

### 1.4. Crie uma API Key
1. No menu lateral → **"APIs e Serviços"** → **"Credenciais"**
2. Clique em **"+ Criar Credenciais"**
3. Selecione **"Chave de API"**
4. **COPIE A CHAVE GERADA** (ex: `AIzaSyBCd1234567890abcdefXYZ`)

---

## 🔑 Passo 2: Configurar a API Key Localmente

### 2.1. Crie o arquivo `.env.local`

Na pasta `functions`, crie um arquivo chamado `.env.local` com o seguinte conteúdo:

```
GOOGLE_PLACES_API_KEY=SUA_API_KEY_AQUI
```

**Substitua** `SUA_API_KEY_AQUI` pela chave que você copiou!

**Exemplo:**
```
GOOGLE_PLACES_API_KEY=AIzaSyBCd1234567890abcdefXYZ
```

### 2.2. Arquivo de Exemplo

Existe um arquivo `.env.local.example` na pasta `functions` como referência.

---

## 🚀 Passo 3: Deploy das Funções

Após configurar o `.env.local`, execute:

```bash
firebase deploy --only functions
```

**AGUARDE** o deploy completar (2-3 minutos).

---

## ✅ Passo 4: Testar

1. Entre no app como **dono da loja**
2. Vá em **Configurações** → **Integrações**
3. Clique em **"CONECTAR"** no Google Meu Negócio
4. Pesquise pelo nome do seu estabelecimento
5. **Deve funcionar agora!** ✨

---

## 💰 Custos da API

- **GRATUITO** até **150.000 requisições/mês**
- Seu app faz cache, então vai gastar muito pouco
- Após o limite: ~R$ 0,085 por requisição

---

## ❓ Problemas Comuns

### "Ainda dá erro 500"
✅ Verifique se o arquivo `.env.local` está na pasta `functions`
✅ Verifique se a API Key está correta (sem espaços)
✅ Aguarde 2-3 minutos após o deploy
✅ Execute `firebase deploy --only functions` novamente

### "API Key não funciona"
✅ Verifique se a **Places API** está ATIVADA no Google Cloud Console
✅ Pode demorar 1-2 minutos para a API Key ser propagada
✅ Teste com outro navegador/dispositivo

### "Permissão negada"
✅ No Google Cloud Console → APIs → Credenciais
✅ Clique na sua API Key
✅ Em "Restrições da API", remova qualquer restrição ou adicione "Places API"

---

## 📞 Precisa de Ajuda?

Se ainda tiver problemas depois de seguir TODOS os passos, me chame! 😊

---

## 🔒 Segurança

**IMPORTANTE:** 
- O arquivo `.env.local` NÃO é versionado (está no .gitignore)
- NUNCA compartilhe sua API Key publicamente
- Para produção, considere adicionar restrições de domínio na API Key
