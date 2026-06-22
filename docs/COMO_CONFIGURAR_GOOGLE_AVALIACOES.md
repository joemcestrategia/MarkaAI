# 📝 Como Configurar as Avaliações do Google no seu App

## ⚠️ IMPORTANTE: Você precisa configurar a API Key primeiro!

Siga estes passos **ANTES** de usar a funcionalidade no app:

---

## 🔑 Passo 1: Criar a Google Places API Key

1. **Acesse**: https://console.cloud.google.com/
2. **Crie ou selecione** um projeto
3. **Ative a Places API**:
   - Menu lateral → "APIs e Serviços" → "Biblioteca"
   - Pesquise "Places API"
   - Clique em "ATIVAR"

4. **Crie a chave**:
   - Menu "APIs e Serviços" → "Credenciais"
   - Botão "Criar credenciais" → "Chave de API"
   - **COPIE a chave gerada** (ex: `AIzaSyBCd...xyz123`)

---

## 🔧 Passo 2: Configurar no Firebase

Abra o terminal/PowerShell **NESTA PASTA** (`c:\src\MarkaAI`) e execute:

```bash
firebase functions:config:set google.places_api_key="SUA_CHAVE_AQUI"
```

**Substitua `SUA_CHAVE_AQUI` pela chave que você copiou!**

Exemplo:
```bash
firebase functions:config:set google.places_api_key="AIzaSyBCd1234567890abcdefXYZ"
```

---

## 🚀 Passo 3: Deploy das Configurações

Ainda no terminal, execute:

```bash
firebase deploy --only functions
```

**Aguarde** o deploy terminar (pode demorar 2-3 minutos).

---

## ✅ Pronto! Agora você pode usar no app:

### Como vincular seu Google Meu Negócio:

1. **Entre no app** como dono da loja
2. **Vá em**: Configurações (ícone de engrenagem)
3. **Procure a seção**: "Integrações"
4. **Clique em**: "CONECTAR" no card "Google Meu Negócio"
5. **Digite o nome** do seu negócio e clique em "BUSCAR"
6. **Selecione seu estabelecimento** e clique em "VINCULAR"

### O que acontece depois:

✨ **Automaticamente**, suas avaliações do Google aparecerão na página da sua loja para os clientes!

Eles verão:
- ⭐ Média de estrelas
- 💬 Primeiras 3 avaliações completas
- 🔽 Botão "VER TODAS" para expandir

---

## 💰 Custos

- **GRATUITO** até 150.000 buscas/mês
- Seu app faz cache para economizar
- Após o limite: ~R$0,085 por busca (muito barato!)

---

## ❓ Problemas Comuns

### "Google Places API não está configurada"
→ Você pulou o **Passo 2**. Execute o comando!

### "Nenhum resultado encontrado"
→ Tente pesquisar com endereço completo:
   Exemplo: `AfroED Studio Itabirito MG`

### Avaliações não aparecem
→ Verifique se:
   - O estabelecimento foi vinculado
   - Tem avaliações no Google Maps
   - Aguarde 1-2 minutos e recarregue

---

## 📞 Precisa de Ajuda?

Se tiver dúvidas, me chame que eu te ajudo! 😊
