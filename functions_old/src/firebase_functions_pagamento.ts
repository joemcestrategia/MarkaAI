import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import axios from 'axios';

admin.initializeApp();
const db = admin.firestore();

/// =====================================================
/// FIREBASE CLOUD FUNCTION - CRIAR PAGAMENTO
/// =====================================================
/// 
/// Fluxo:
/// 1. Recebe CardToken do frontend
/// 2. Cria pagamento via API Mercado Pago
/// 3. Retorna resultado
/// 4. Salva agendamento se aprovado
/// =====================================================

interface PagamentoRequest {
  cardToken: string;
  email: string;
  installments: number;
  valor: number;
  shopId: string;
  orderId: string;
  descricao: string;
}

interface PagamentoResponse {
  success: boolean;
  paymentId?: string;
  status?: string;
  error?: string;
}

/**
 * Criar pagamento com CardToken
 * 
 * POST /criarPagamento
 * Body:
 * {
 *   "cardToken": "token_xxxxx",
 *   "email": "usuario@email.com",
 *   "installments": 3,
 *   "valor": 500.00,
 *   "shopId": "shop_123",
 *   "orderId": "AGE-123456",
 *   "descricao": "Agendamento de serviço"
 * }
 */
export const criarPagamento = functions.https.onCall(
  async (data: PagamentoRequest, context): Promise<PagamentoResponse> => {
    try {
      // 1️⃣ Validações
      if (!context.auth) {
        throw new functions.https.HttpsError(
          'unauthenticated',
          'Usuário não autenticado'
        );
      }

      const { cardToken, email, installments, valor, shopId, orderId, descricao, paymentMethodId, issuerId } = data;

      if (!cardToken || !email || !shopId) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          'Dados incompletos'
        );
      }

      console.log('📝 Criando pagamento...');
      console.log(`   Token: ${cardToken.substring(0, 10)}...`);
      console.log(`   Email: ${email}`);
      console.log(`   Valor: R$ ${valor}`);
      console.log(`   Parcelas: ${installments}`);

      // 2️⃣ Obter Access Token da loja
      const shopDoc = await db.collection('shops').doc(shopId).get();
      if (!shopDoc.exists) {
        throw new functions.https.HttpsError('not-found', 'Loja não encontrada');
      }

      const shopData = shopDoc.data() as any;
      const accessToken = shopData.mercadopago?.access_token;

      if (!accessToken) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Access Token não configurado'
        );
      }

      // 3️⃣ Chamar API Mercado Pago
      const payload: any = {
        token: cardToken,
        transaction_amount: Number(valor),
        installments: Number(installments) || 1,
        payer: { email: email },
        description: descricao,
        capture: true,
        statement_descriptor: 'MarkaAI Service',
        external_reference: orderId,
      };
      if (paymentMethodId) payload.payment_method_id = paymentMethodId;
      if (issuerId) payload.issuer_id = issuerId;

      const response = await axios.post(
        'https://api.mercadopago.com/v1/payments',
        payload,
        {
          headers: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
        }
      );

      console.log('✅ Resposta Mercado Pago:');
      console.log(`   Status: ${response.data.status}`);
      console.log(`   ID: ${response.data.id}`);

      // 4️⃣ Processar resultado
      const { status, status_detail, id, transaction_details } = response.data;

      if (status === 'approved') {
        // ✅ Pagamento aprovado
        console.log('✅ Pagamento APROVADO');

        // Salvar no Firestore
        await db.collection('approved_payments').doc(orderId).set({
          paymentId: id,
          status: status,
          statusDetail: status_detail,
          amount: valor,
          installments: installments,
          email: email,
          shopId: shopId,
          userId: context.auth.uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          transactionDetails: transaction_details,
        });

        return {
          success: true,
          paymentId: id.toString(),
          status: status,
        };
      } else if (status === 'pending') {
        // ⏳ Pagamento pendente
        console.log('⏳ Pagamento PENDENTE');

        await db.collection('pending_payments').doc(orderId).set({
          paymentId: id,
          status: status,
          statusDetail: status_detail,
          amount: valor,
          installments: installments,
          email: email,
          shopId: shopId,
          userId: context.auth.uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
          success: true,
          paymentId: id.toString(),
          status: status,
        };
      } else {
        // ❌ Pagamento recusado
        console.log('❌ Pagamento RECUSADO');
        console.log(`   Razão: ${status_detail}`);

        return {
          success: false,
          status: status,
          error: traduzirErroMP(status_detail),
        };
      }
    } catch (error: any) {
      console.error('❌ Erro ao criar pagamento:', error.message);

      // Erro do Mercado Pago
      if (error.response?.data) {
        const mpError = error.response.data;
        console.error('   Detalhes:', mpError);

        return {
          success: false,
          error: mpError.message || 'Erro ao processar pagamento',
        };
      }

      // Erro geral
      if (error instanceof functions.https.HttpsError) {
        throw error;
      }

      throw new functions.https.HttpsError(
        'internal',
        error.message || 'Erro desconhecido'
      );
    }
  }
);

/**
 * Função auxiliar para traduzir erros do Mercado Pago
 */
function traduzirErroMP(statusDetail: string): string {
  const erros: { [key: string]: string } = {
    'cc_rejected_insufficient_amount': 'Saldo insuficiente',
    'cc_rejected_bad_filled_security_code': 'CVV incorreto',
    'cc_rejected_bad_filled_date': 'Data de validade incorreta',
    'cc_rejected_other_reason': 'Recusado pelo banco',
    'cc_rejected_call_for_authorize': 'Ligue para autorizar',
    'cc_rejected_card_error': 'Erro no cartão',
    'cc_rejected_duplicated_payment': 'Pagamento duplicado',
    'cc_rejected_fraud': 'Suspeitado de fraude',
    'cc_rejected_max_attempts': 'Muitas tentativas',
  };

  return erros[statusDetail] || 'Pagamento recusado';
}

/**
 * Webhook para receber notificações do Mercado Pago
 * Configurar em: Mercado Pago > Webhooks
 * URL: https://seu-projeto.cloudfunctions.net/mercadoPagoWebhook
 */
export const mercadoPagoWebhook = functions.https.onRequest(
  async (req, res) => {
    try {
      const { type, data } = req.body;

      console.log('📨 Webhook recebido:');
      console.log(`   Tipo: ${type}`);
      console.log(`   ID: ${data.id}`);

      if (type !== 'payment') {
        res.status(200).send({ ok: true });
        return;
      }

      const paymentId = data.id;

      // Obter detalhes do pagamento
      // Nota: Você precisaria usar um Access Token para isso
      // Por enquanto, apenas logamos

      console.log(`✅ Webhook processado para pagamento: ${paymentId}`);
      res.status(200).send({ ok: true });
    } catch (error: any) {
      console.error('❌ Erro no webhook:', error.message);
      res.status(500).send({ error: error.message });
    }
  }
);

/**
 * Obter status de pagamento
 * GET /obterStatusPagamento?paymentId=123456
 */
export const obterStatusPagamento = functions.https.onCall(
  async (data: { paymentId: string; shopId: string }, context) => {
    try {
      if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Não autenticado');
      }

      const { paymentId, shopId } = data;

      // Obter Access Token
      const shopDoc = await db.collection('shops').doc(shopId).get();
      const accessToken = (shopDoc.data() as any).mercadopago?.access_token;

      if (!accessToken) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Access Token não configurado'
        );
      }

      // Chamar API Mercado Pago
      const response = await axios.get(
        `https://api.sandbox.mercadopago.com/v1/payments/${paymentId}`,
        {
          headers: {
            'Authorization': `Bearer ${accessToken}`,
          },
        }
      );

      return {
        paymentId: response.data.id,
        status: response.data.status,
        statusDetail: response.data.status_detail,
        amount: response.data.transaction_details?.net_received_amount,
      };
    } catch (error: any) {
      throw new functions.https.HttpsError(
        'internal',
        error.message || 'Erro ao obter status'
      );
    }
  }
);
