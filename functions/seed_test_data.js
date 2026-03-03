/**
 * FASE 1 — Seed de Dados de Teste para o MarkaAI
 *
 * Endpoint HTTP: POST /seedTestData
 * Header obrigatório: x-seed-key: markaai-seed-dev
 *
 * Cria no Firestore:
 *   - users/test_cliente
 *   - shops/test_loja (com MP token TEST-*)
 *   - shops/test_loja/services/ (2 serviços)
 *   - shops/test_loja/employees/ (1 profissional)
 *   - config da loja com parcelamento habilitado
 *
 * SEGURANÇA: protegido por x-seed-key. Não usar em produção.
 * Para remover todos os dados: POST /seedTestData com { action: 'cleanup' }
 */

const { onRequest } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');

// Inicializa admin apenas se necessário (o index.js já inicializa)
if (!admin.apps.length) {
    admin.initializeApp();
}

const SEED_KEY = 'markaai-seed-dev';

// IDs fixos para facilitar testes repetíveis
const TEST_CLIENT_UID = 'test_cliente_uid_001';
const TEST_SHOP_ID = 'test_loja_001';
const TEST_EMPLOYEE_ID = 'test_prof_001';
const TEST_SERVICE_1_ID = 'test_servico_corte_001';
const TEST_SERVICE_2_ID = 'test_servico_barba_001';

exports.seedTestData = onRequest({ cors: true }, async (req, res) => {
    // Verificação de segurança
    const seedKey = req.headers['x-seed-key'];
    if (seedKey !== SEED_KEY) {
        return res.status(401).json({
            success: false,
            error: 'x-seed-key inválida. Endpoint restrito a ambiente de desenvolvimento.'
        });
    }

    if (req.method === 'OPTIONS') return res.status(204).send('');
    if (req.method !== 'POST') {
        return res.status(405).json({ success: false, error: 'Use POST' });
    }

    const action = req.body?.action || 'seed';

    // Ação de limpeza
    if (action === 'cleanup') {
        return await _cleanup(res);
    }

    // Ação: atualizar credenciais MP do shop de teste
    if (action === 'setMpKeys') {
        const { shopId, publicKey, accessToken } = req.body;
        if (!shopId || !publicKey) {
            return res.status(400).json({ success: false, error: 'shopId e publicKey são obrigatórios.' });
        }
        const db = admin.firestore();
        await db.collection('shops').doc(shopId).set({
            mercadopago: {
                connected: true,
                public_key: publicKey,
                access_token: accessToken || '',
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
            subscription: {
                plan_id: 'pro',
                plan_name: 'Pro',
                status: 'active',
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
            plan: 'pro',
            plan_id: 'pro',
        }, { merge: true });
        return res.status(200).json({ success: true, message: `MP keys updated for ${shopId}` });
    }

    try {
        const db = admin.firestore();
        const batch = db.batch();

        // ─── 1. Usuário de teste (cliente) ───
        // (apenas Firestore — Firebase Auth requer criação separada sobretudo em emulador)
        const clientRef = db.collection('users').doc(TEST_CLIENT_UID);
        batch.set(clientRef, {
            uid: TEST_CLIENT_UID,
            nome: 'Cliente Teste',
            email: 'teste@cliente.markaai.com',
            tipo: 'cliente',
            shopId: null,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            _isSeed: true,
        }, { merge: true });

        // ─── 2. Loja de teste ───
        const shopRef = db.collection('shops').doc(TEST_SHOP_ID);
        batch.set(shopRef, {
            nome: 'Barbearia de Teste MarkaAI',
            descricao: 'Loja criada automaticamente para testes.',
            slug: 'test-loja-markaai',
            telefone: '(11) 99999-8888',
            plan: 'plus', // Plano pago para habilitar pagamento online
            plan_id: 'plus',
            payment_configured: true,
            // MP de sandbox — substitua por um token TEST-* válido do seu app MP
            mercadopago: {
                connected: true,
                // IMPORTANTE: substitua pelo seu access_token de teste real antes de testar
                access_token: 'TEST-SUBSTITUA-PELO-SEU-TOKEN-AQUI',
                public_key: 'TEST-SUBSTITUA-PELA-SUA-PUBLIC-KEY-AQUI',
                updated_at: admin.firestore.FieldValue.serverTimestamp(),
            },
            config: {
                agendamento_online_ativo: true,
                permitir_reagendamento: true,
                permitir_multiplos: false,
                cliente_escolhe_prof: true,
                intervalo_agenda_min: 60,
                evitar_buracos_agenda: false,
                janela_agendamento_dias: 30,
                limite_minimo_agendamento_horas: 2,
                tempo_cancelamento_horas: 2,
                pagamento_pix: true,
                pagamento_cartao: true,
                pagamento_dinheiro: true,
                exigir_sinal: false,
                percentual_sinal: 30,
                tax_percent: 5.0, // 5% de taxa de crédito
                aceitar_parcelas: true,
                max_parcelas: 6,
                notificar_cliente_agendamento: true,
                notificar_dias_antes: 1,
                atualizado_em: admin.firestore.FieldValue.serverTimestamp(),
            },
            _isSeed: true,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        // ─── 3. Profissional (employee) ───
        const empRef = db.collection('shops').doc(TEST_SHOP_ID)
            .collection('employees').doc(TEST_EMPLOYEE_ID);
        batch.set(empRef, {
            nome: 'João Silva (Teste)',
            cargo: 'Barbeiro',
            ativo: true,
            // Horários: seg-sab, 09:00-18:00
            horarios: {
                segunda: { ativo: true, inicio: '09:00', fim: '18:00' },
                terca: { ativo: true, inicio: '09:00', fim: '18:00' },
                quarta: { ativo: true, inicio: '09:00', fim: '18:00' },
                quinta: { ativo: true, inicio: '09:00', fim: '18:00' },
                sexta: { ativo: true, inicio: '09:00', fim: '18:00' },
                sabado: { ativo: true, inicio: '09:00', fim: '14:00' },
                domingo: { ativo: false, inicio: '', fim: '' },
            },
            _isSeed: true,
        }, { merge: true });

        // ─── 4. Serviços ───
        const svc1Ref = db.collection('shops').doc(TEST_SHOP_ID)
            .collection('services').doc(TEST_SERVICE_1_ID);
        batch.set(svc1Ref, {
            nome: 'Corte de Cabelo',
            descricao: 'Corte masculino completo',
            preco: 50.00,
            duracao_minutos: 60,
            ativo: true,
            categoria: 'Cabelo',
            _isSeed: true,
        }, { merge: true });

        const svc2Ref = db.collection('shops').doc(TEST_SHOP_ID)
            .collection('services').doc(TEST_SERVICE_2_ID);
        batch.set(svc2Ref, {
            nome: 'Barba',
            descricao: 'Aparar e modelar a barba',
            preco: 30.00,
            duracao_minutos: 30,
            ativo: true,
            categoria: 'Barba',
            _isSeed: true,
        }, { merge: true });

        // ─── 5. Usuário admin (dono da loja) ───
        const ownerRef = db.collection('users').doc('test_owner_001');
        batch.set(ownerRef, {
            uid: 'test_owner_001',
            nome: 'Dono da Barbearia (Teste)',
            email: 'dono@loja.markaai.com',
            tipo: 'dono',
            role: 'dono',
            shopId: TEST_SHOP_ID,
            _isSeed: true,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        await batch.commit();

        return res.status(200).json({
            success: true,
            message: 'Dados de teste criados com sucesso!',
            data: {
                shopId: TEST_SHOP_ID,
                clientUid: TEST_CLIENT_UID,
                ownerUid: 'test_owner_001',
                employeeId: TEST_EMPLOYEE_ID,
                services: [TEST_SERVICE_1_ID, TEST_SERVICE_2_ID],
                warning: '⚠️ Substitua os tokens TEST-* do Mercado Pago no shop antes de testar pagamentos.',
            }
        });

    } catch (error) {
        console.error('seedTestData error:', error);
        return res.status(500).json({
            success: false,
            error: 'Erro ao criar dados de teste: ' + error.message
        });
    }
});

async function _cleanup(res) {
    try {
        const db = admin.firestore();

        // Deletar subcoleções manualmente (batch delete)
        const toDelete = [
            db.collection('users').doc(TEST_CLIENT_UID),
            db.collection('users').doc('test_owner_001'),
            db.collection('shops').doc(TEST_SHOP_ID)
                .collection('employees').doc(TEST_EMPLOYEE_ID),
            db.collection('shops').doc(TEST_SHOP_ID)
                .collection('services').doc(TEST_SERVICE_1_ID),
            db.collection('shops').doc(TEST_SHOP_ID)
                .collection('services').doc(TEST_SERVICE_2_ID),
            db.collection('shops').doc(TEST_SHOP_ID),
        ];

        const batch = db.batch();
        toDelete.forEach(ref => batch.delete(ref));
        await batch.commit();

        return res.status(200).json({ success: true, message: 'Dados de teste removidos.' });
    } catch (error) {
        return res.status(500).json({ success: false, error: error.message });
    }
}
