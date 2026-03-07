const admin = require('firebase-admin');
const { onRequest } = require("firebase-functions/v2/https");

admin.initializeApp();

exports.debugAppointments = onRequest(async (req, res) => {
    try {
        const snaps = await admin.firestore().collection('appointments')
            .orderBy('criado_em', 'desc').limit(10).get();

        const result = [];
        for (const doc of snaps.docs) {
            const d = doc.data();
            let shopExists = false;
            let profExists = false;
            let servExists = false;

            if (d.shopId) {
                const sSnap = await admin.firestore().collection('shops').doc(d.shopId).get();
                shopExists = sSnap.exists;
                if (d.servicoId) {
                    const srvSnap = await admin.firestore().collection('shops').doc(d.shopId).collection('services').doc(d.servicoId).get();
                    servExists = srvSnap.exists;
                }
            }
            if (d.profissionalId) {
                const pSnap = await admin.firestore().collection('employees').doc(d.profissionalId).get();
                profExists = pSnap.exists;
            }
            result.push({
                id: doc.id,
                service: d.servico_nome,
                shopId: d.shopId,
                profissionalId: d.profissionalId,
                servicoId: d.servicoId,
                client_nome: d.client_nome,
                shopExists,
                profExists,
                servExists
            });
        }
        res.json(result);
    } catch (error) {
        res.status(500).send(error.toString());
    }
});
