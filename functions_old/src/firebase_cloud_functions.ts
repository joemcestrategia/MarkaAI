// 📁 ARQUIVO: functions/src/index.ts
// Este arquivo vai na sua pasta de Firebase Cloud Functions

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import axios from 'axios';

admin.initializeApp();
const db = admin.firestore();

// ===================== GERAR PIX =====================

export const gerarPix = functions.https.onCall(async (data, context) => {
  try {
    // Validar autenticação
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Usuário não autenticado'
      );
    }

    const { accessToken, amount, emailCliente, description } = data;

    // Validar dados
    if (!accessToken || !amount || !description) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Dados incompletos'
      );
    }

    console.log('🔵 [Cloud Function] Gerando PIX...');
    console.log('💰 Valor:', amount);
    console.log('📝 Descrição:', description);

    // Email padrão se vazio
    const emailFinal = emailCliente && emailCliente.includes('@') 
      ? emailCliente 
      : 'cliente_sem_email@markaai.com';

    // Montar requisição para Mercado Pago
    const payload = {
      transaction_amount: amount,
      description: description,
      payment_method_id: 'pix',
      payer: {
        email: emailFinal,
        first_name: 'Cliente',
        last_name: 'App',
      },
    };

    console.log('📤 Enviando para Mercado Pago...');

    // Chamar API do Mercado Pago
    const response = await axios.post(
      'https://api.mercadopago.com/v1/payments',
      payload,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'X-Idempotency-Key': Date.now().toString(),
        },
      }
    );

    console.log('✅ Resposta recebida do Mercado Pago');
    console.log('📦 Status:', response.status);

    if (response.status === 201) {
      const result = response.data;
      
      console.log('✅ PIX gerado com sucesso');
      console.log('🎫 Payment ID:', result.id);

      // Validar estrutura
      if (!result.point_of_interaction?.transaction_data?.qr_code_base64) {
        throw new Error('QR Code não encontrado na resposta');
      }

      return {
        success: true,
        data: result,
      };
    } else {
      throw new Error(`Erro Mercado Pago: ${response.status}`);
    }
  } catch (error: any) {
    console.error('❌ Erro:', error.message);
    
    let errorMessage = 'Erro ao gerar PIX';
    
    if (error.response?.data?.message) {
      errorMessage = error.response.data.message;
    } else if (error.message) {
      errorMessage = error.message;
    }

    throw new functions.https.HttpsError(
      'internal',
      errorMessage
    );
  }
});

// ===================== VERIFICAR STATUS PIX =====================

export const verificarStatusPix = functions.https.onCall(async (data, context) => {
  try {
    // Validar autenticação
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Usuário não autenticado'
      );
    }

    const { accessToken, paymentId } = data;

    // Validar dados
    if (!accessToken || !paymentId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Dados incompletos'
      );
    }

    console.log('🔵 [Cloud Function] Verificando status PIX...');
    console.log('🎫 Payment ID:', paymentId);

    // Chamar API do Mercado Pago
    const response = await axios.get(
      `https://api.mercadopago.com/v1/payments/${paymentId}`,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
        },
      }
    );

    if (response.status === 200) {
      const status = response.data.status;
      
      console.log('📊 Status:', status);

      return {
        success: true,
        status: status,
      };
    } else {
      throw new Error(`Erro ao verificar: ${response.status}`);
    }
  } catch (error: any) {
    console.error('❌ Erro:', error.message);
    
    throw new functions.https.HttpsError(
      'internal',
      'Erro ao verificar status'
    );
  }
});

// ===================== COBRAR CARTÃO =====================

export const cobrarCartao = functions.https.onCall(async (data, context) => {
  try {
    // Validar autenticação
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Usuário não autenticado'
      );
    }

    const {
      accessToken,
      cardNumber,
      cardHolder,
      expirationMonth,
      expirationYear,
      securityCode,
      amount,
      installments,
      description,
      emailCliente,
    } = data;

    // Validar dados
    if (!accessToken || !cardNumber || !cardHolder || !expirationMonth || 
        !expirationYear || !securityCode || !amount || !description) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Dados incompletos'
      );
    }

    console.log('🔵 [Cloud Function] Processando cartão...');
    console.log('💳 Cartão:', `****${cardNumber.substring(cardNumber.length - 4)}`);
    console.log('💰 Valor:', amount);

    // PASSO 1: Gerar token do cartão
    console.log('📝 Gerando token do cartão...');

    const tokenPayload = {
      card_number: cardNumber,
      cardholder: {
        name: cardHolder,
      },
      expiration_month: expirationMonth,
      expiration_year: expirationYear,
      security_code: securityCode,
    };

    const tokenResponse = await axios.post(
      'https://api.mercadopago.com/v1/card_tokens',
      tokenPayload,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
      }
    );

    if (tokenResponse.status !== 201 && tokenResponse.status !== 200) {
      throw new Error('Falha ao gerar token do cartão');
    }

    const token = tokenResponse.data.id;
    console.log('✅ Token gerado:', token.substring(0, 20) + '...');

    // PASSO 2: Processar pagamento com token
    console.log('💳 Processando pagamento...');

    const emailFinal = emailCliente && emailCliente.includes('@')
      ? emailCliente
      : 'cliente_sem_email@markaai.com';

    const paymentPayload = {
      token: token,
      amount: amount,
      installments: installments || 1,
      description: description,
      payment_method_id: 'credit_card',
      payer: {
        email: emailFinal,
      },
    };

    const paymentResponse = await axios.post(
      'https://api.mercadopago.com/v1/payments',
      paymentPayload,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'X-Idempotency-Key': Date.now().toString(),
        },
      }
    );

    if (paymentResponse.status === 201) {
      const result = paymentResponse.data;
      
      console.log('✅ Pagamento processado com sucesso');
      console.log('📊 Status:', result.status);
      console.log('🎫 Payment ID:', result.id);

      return {
        success: true,
        data: result,
      };
    } else {
      throw new Error(`Erro ao processar pagamento: ${paymentResponse.status}`);
    }
  } catch (error: any) {
    console.error('❌ Erro:', error.message);
    
    let errorMessage = 'Erro ao processar cartão';
    
    if (error.response?.data?.message) {
      errorMessage = error.response.data.message;
    } else if (error.message) {
      errorMessage = error.message;
    }

    throw new functions.https.HttpsError(
      'internal',
      errorMessage
    );
  }
});

// ===================== COBRAR CARTÃO SALVO =====================

export const cobrarCartaoSalvo = functions.https.onCall(async (data, context) => {
  try {
    // Validar autenticação
    if (!context.auth) {
      throw new functions.https.HttpsError(
        'unauthenticated',
        'Usuário não autenticado'
      );
    }

    const {
      accessToken,
      customerId,
      cardId,
      amount,
      installments,
      description,
      emailCliente,
    } = data;

    // Validar dados
    if (!accessToken || !customerId || !cardId || !amount || !description) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Dados incompletos'
      );
    }

    console.log('🔵 [Cloud Function] Cobrando cartão salvo...');
    console.log('💳 Card ID:', cardId);
    console.log('💰 Valor:', amount);

    const emailFinal = emailCliente && emailCliente.includes('@')
      ? emailCliente
      : 'cliente_sem_email@markaai.com';

    const payload = {
      customer_id: customerId,
      card_id: cardId,
      amount: amount,
      installments: installments || 1,
      payment_method_id: 'credit_card',
      description: description,
      payer: {
        email: emailFinal,
      },
    };

    const response = await axios.post(
      'https://api.mercadopago.com/v1/payments',
      payload,
      {
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
          'X-Idempotency-Key': Date.now().toString(),
        },
      }
    );

    if (response.status === 201) {
      const result = response.data;
      
      console.log('✅ Cartão salvo cobrado com sucesso');
      console.log('📊 Status:', result.status);

      return {
        success: true,
        data: result,
      };
    } else {
      throw new Error(`Erro: ${response.status}`);
    }
  } catch (error: any) {
    console.error('❌ Erro:', error.message);
    
    let errorMessage = 'Erro ao processar cartão';
    
    if (error.response?.data?.message) {
      errorMessage = error.response.data.message;
    }

    throw new functions.https.HttpsError(
      'internal',
      errorMessage
    );
  }
});

/**
 * Quando um agendamento é criado, notifica o(s) dono(s) da loja via FCM.
 * O app deve salvar tokens FCM em `users/{uid}.fcmTokens` (array).
 */
export const onAppointmentCreated = functions.firestore
  .document('appointments/{id}')
  .onCreate(async (snap, context) => {
    try {
      const data = snap.data() as any;
      const shopId = data.shopId;
      if (!shopId) return;

      // Buscar donos/administradores vinculados à loja (otimizado: busca por shopId primeiro)
      const ownersSnap = await db.collection('users').where('shopId', '==', shopId).get();
      const tokens: string[] = [];
      ownersSnap.forEach(doc => {
        const ud = doc.data() as any;
        const tipo = ud.tipo;
        if ((tipo === 'dono' || tipo === 'business') && Array.isArray(ud.fcmTokens)) {
          ud.fcmTokens.forEach((t: string) => tokens.push(t));
        }
      });

      if (tokens.length === 0) return;

      const title = 'Novo agendamento recebido';
      const body = `Novo agendamento para ${data.servico_nome ?? 'serviço'} em ${data.horario ?? ''}`;

      const message = {
        notification: { title, body },
        data: { appointmentId: snap.id, shopId: shopId.toString() },
      };

      // Enviar em lotes de 500 (limite do sendMulticast)
      const chunks: string[][] = [];
      for (let i = 0; i < tokens.length; i += 500) {
        chunks.push(tokens.slice(i, i + 500));
      }
      for (const chunk of chunks) {
        await admin.messaging().sendMulticast({ tokens: chunk, ...message });
      }
    } catch (err: any) {
      console.error('Erro onAppointmentCreated:', err.message || err);
    }
  });

/**
 * Função agendada (cron) que roda diariamente às 08:00 UTC para enviar lembretes de agendamento.
 * Lê configuração de cada loja (notificar_dias_antes) e envia notificações aos clientes.
 */
export const sendAppointmentReminders = functions.pubsub
  .schedule('0 8 * * *') // Diariamente às 08:00 UTC (05:00 BRT)
  .timeZone('America/Sao_Paulo')
  .onRun(async (context) => {
    try {
      const today = new Date();
      const shopsSnap = await db.collection('shops').get();
      
      for (const shopDoc of shopsSnap.docs) {
        const shopData = shopDoc.data() as any;
        const config = shopData.config || {};
        const notifyEnabled = config.notificar_cliente_agendamento !== false; // Default true
        const daysBefore = config.notificar_dias_antes || 1;
        
        if (!notifyEnabled) continue;
        
        const targetDate = new Date(today);
        targetDate.setDate(today.getDate() + daysBefore);
        targetDate.setHours(0, 0, 0, 0);
        const targetDateEnd = new Date(targetDate);
        targetDateEnd.setHours(23, 59, 59, 999);
        
        // Buscar agendamentos para a data alvo que ainda não foram notificados
        const appointmentsSnap = await db.collection('appointments')
          .where('shopId', '==', shopDoc.id)
          .where('data_agendamento', '>=', admin.firestore.Timestamp.fromDate(targetDate))
          .where('data_agendamento', '<=', admin.firestore.Timestamp.fromDate(targetDateEnd))
          .where('status', 'in', ['confirmado', 'agendado'])
          .get();
        
        for (const aptDoc of appointmentsSnap.docs) {
          const aptData = aptDoc.data() as any;
          // Se já foi notificado, pular
          if (aptData.lembrete_enviado) continue;
          
          // Se pagamento é "pessoalmente" e ainda não foi pago, enviar notificação de confirmação
          const metodoPagamento = aptData.metodo_pagamento || '';
          const valorPago = (aptData.valor_pago || 0) as number;
          const precisaConfirmacao = metodoPagamento.toLowerCase().includes('pessoalmente') || metodoPagamento.toLowerCase().includes('local') && valorPago === 0;
          
          // Buscar tokens FCM do cliente
          const clientDoc = await db.collection('users').doc(aptData.clientId).get();
          if (!clientDoc.exists) continue;
          
          const clientData = clientDoc.data() as any;
          const clientTokens = Array.isArray(clientData.fcmTokens) ? clientData.fcmTokens : [];
          if (clientTokens.length === 0) continue;
          
          const title = precisaConfirmacao 
            ? 'Confirme seu agendamento' 
            : 'Lembrete de agendamento';
          const body = precisaConfirmacao
            ? `Você tem um agendamento em ${daysBefore} ${daysBefore === 1 ? 'dia' : 'dias'}. Confirme sua presença?`
            : `Lembrete: Você tem um agendamento em ${daysBefore} ${daysBefore === 1 ? 'dia' : 'dias'} - ${aptData.servico_nome || 'Serviço'}`;
          
          const message = {
            notification: { title, body },
            data: {
              appointmentId: aptDoc.id,
              shopId: shopDoc.id,
              type: precisaConfirmacao ? 'confirmacao' : 'lembrete',
            },
          };
          
          // Enviar notificação
          await admin.messaging().sendMulticast({ tokens: clientTokens, ...message });
          
          // Marcar como notificado
          await aptDoc.ref.update({ lembrete_enviado: true, lembrete_enviado_em: admin.firestore.FieldValue.serverTimestamp() });
        }
      }
      
      console.log(`✅ Lembretes enviados para ${shopsSnap.docs.length} lojas`);
    } catch (err: any) {
      console.error('Erro sendAppointmentReminders:', err.message || err);
    }
  });

/**
 * Quando cliente confirma ou cancela presença (atualiza appointment com client_confirmed), notifica o dono.
 */
export const onClientConfirmation = functions.firestore
  .document('appointments/{id}')
  .onUpdate(async (change, context) => {
    try {
      const before = change.before.data() as any;
      const after = change.after.data() as any;
      
      // Só processa se client_confirmed mudou de undefined/null para true/false
      if (before.client_confirmed === after.client_confirmed) return;
      if (after.client_confirmed === undefined || after.client_confirmed === null) return;
      
      const shopId = after.shopId;
      if (!shopId) return;
      
      // Buscar donos
      const ownersSnap = await db.collection('users').where('shopId', '==', shopId).get();
      const tokens: string[] = [];
      ownersSnap.forEach(doc => {
        const ud = doc.data() as any;
        if ((ud.tipo === 'dono' || ud.tipo === 'business') && Array.isArray(ud.fcmTokens)) {
          ud.fcmTokens.forEach((t: string) => tokens.push(t));
        }
      });
      
      if (tokens.length === 0) return;
      
      const clienteNome = after.client_nome || 'Cliente';
      const confirmado = after.client_confirmed === true;
      const title = confirmado ? 'Cliente confirmou presença' : 'Cliente cancelou agendamento';
      const body = confirmado
        ? '$clienteNome confirmou presença para ${after.servico_nome || "serviço"}'
        : '$clienteNome cancelou o agendamento';
      
      const message = {
        notification: { title, body },
        data: { appointmentId: change.after.id, shopId: shopId.toString(), confirmed: confirmado.toString() },
      };
      
      await admin.messaging().sendMulticast({ tokens, ...message });
    } catch (err: any) {
      console.error('Erro onClientConfirmation:', err.message || err);
    }
  });
