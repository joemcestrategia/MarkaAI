# Configuração do Google Meu Negócio

Este documento explica como configurar a integração com o Google Meu Negócio para exibir avaliações na página da loja.

## Passo 1: Obter a Google Places API Key

1. Acesse o [Google Cloud Console](https://console.cloud.google.com/)
2. Crie um novo projeto ou selecione um existente
3. Ative a **Places API**:
   - No menu lateral, vá em "APIs e Serviços" > "Biblioteca"
   - Pesquise por "Places API"
   - Clique em "Places API" e depois em "Ativar"
4. Crie uma API Key:
   - Vá em "APIs e Serviços" > "Credenciais"
   - Clique em "Criar credenciais" > "Chave de API"
   - Copie a chave gerada

## Passo 2: Configurar a API Key no Firebase Functions

Execute o seguinte comando no terminal (substitua `SUA_API_KEY_AQUI` pela chave copiada):

```bash
firebase functions:config:set google.places_api_key="SUA_API_KEY_AQUI"
```

## Passo 3: Deploy das Functions

Após configurar a API Key, faça o deploy das functions:

```bash
firebase deploy --only functions
```

## Passo 4: Como usar no App

### Para Donos de Loja:

1. Entre no app como dono da loja
2. Vá em **Configurações** > **Integrações**
3. Clique em **CONECTAR** no card "Google Meu Negócio"
4. Pesquise pelo nome do seu negócio
5. Selecione o estabelecimento correto e clique em **VINCULAR**

### Resultado:

Após vincular, as avaliações do Google aparecerão automaticamente na página da loja para os clientes, mostrando:
- Média de estrelas
- Número total de avaliações
- As 3 primeiras avaliações com foto, nome, data e comentário
- Botão "VER TODAS" para expandir e ver todas as avaliações

## Limitações

A Google Places API tem algumas limitações:
- Mostra no máximo 5 avaliações mais recentes por estabelecimento
- É gratuita até 150.000 requisições por mês
- Após esse limite, há cobrança por uso adicional

## Custos

Consulte a [Tabela de Preços do Google Maps Platform](https://cloud.google.com/maps-platform/pricing) para mais informações sobre custos.

A função **Place Details** (usada para buscar avaliações) custa:
- **$0,017 por requisição** após o limite gratuito de $200/mês
- O app faz cache das avaliações para minimizar custos

## Solução de Problemas

### "Google Places API não está configurada"

Execute o comando do Passo 2 para configurar a API Key.

### "Nenhum resultado encontrado"

- Verifique se o nome do negócio está correto
- Confirme que o estabelecimento existe no Google Maps
- Tente pesquisar com endereço completo: "Nome do Negócio, Cidade"

### Avaliações não aparecem

- Confirme que o estabelecimento foi vinculado corretamente
- Verifique se o estabelecimento tem avaliações no Google
- Aguarde alguns minutos e recarregue a página
