# Functions - MarkaAI

Endpoint para buscar opções de parcelamento (Mercado Pago) usado pelo app WebView.

Instalação e deploy (Firebase Functions):

1. Instale dependências:
   cd functions
   npm install

2. Configure a Public Key do Mercado Pago (no projeto Firebase):
   firebase functions:config:set mercadopago.public_key="APP_USR-XXXXXXXXXXXXXXXX"

   Alternativamente, defina a variável de ambiente MP_PUBLIC_KEY antes do deploy/execution.

3. Deploy:
   firebase deploy --only functions:getInstallments

Uso:
 - POST /getInstallments
 - Body JSON: { "amount": 380.00, "bin": "123456", "shopId": "SHOP_DOC_ID" }
 - Retorna: { success: true, data: <MP installments response> }

Observações:
 - O endpoint lê a configuração da loja no Firestore (coleção `shops`) para aplicar `tax_percent` / `repasse_ao_cliente` caso o lojista tenha ativado o repasse.
 - Ajuste permissões de Firestore / regras conforme seu projeto.

