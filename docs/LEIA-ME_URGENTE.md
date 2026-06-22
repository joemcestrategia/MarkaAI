# ⚠️ AÇÃO NECESSÁRIA - Configurar Google Places API

## 🔴 Erro que você recebeu: **500**

O erro ocorre porque a **Google Places API Key** não está configurada.

---

## ✅ SOLUÇÃO RÁPIDA (3 Passos):

### 📝 Passo 1: Obter sua API Key

1. Acesse: **https://console.cloud.google.com/**
2. Crie/selecione um projeto
3. Menu → **APIs e Serviços** → **Biblioteca**
4. Pesquise: **"Places API"** → Clique e **ATIVE**
5. Menu → **APIs e Serviços** → **Credenciais**
6. **+ Criar Credenciais** → **Chave de API**
7. **COPIE A CHAVE** (exemplo: `AIzaSyBCd1234567890...`)

---

### 🔑 Passo 2: Adicionar a Key no Arquivo

Abra o arquivo: **`c:\src\MarkaAI\functions\.env.local`**

Substitua:
```
GOOGLE_PLACES_API_KEY=ADICIONE_SUA_API_KEY_AQUI
```

Por (cole sua key):
```
GOOGLE_PLACES_API_KEY=AIzaSyBCd1234567890abcdefXYZ
```

**Salve o arquivo!**

---

### 🚀 Passo 3: Deploy

Abra o terminal nesta pasta e execute:

```bash
firebase deploy --only functions
```

Aguarde 2-3 minutos.

---

## ✨ Pronto!

Depois do deploy, teste novamente:

1. Entre no app como **dono**
2. **Configurações** → **Integrações**
3. **Google Meu Negócio** → **CONECTAR**
4. Pesquise seu estabelecimento

**Deve funcionar!** 🎉

---

## 💡 Dica

Se ainda der erro:
- Aguarde 2 minutos (API Key demora para ativar)
- Verifique se a **Places API** está ATIVADA no Google Cloud
- Tente em outro navegador

---

## 📞 Ajuda

Guia completo: **`CONFIGURAR_GOOGLE_API_KEY.md`**
