const admin = require('firebase-admin');
admin.initializeApp({
    projectId: 'wismart-118c3'
});

const db = admin.firestore();

async function check() {
    const snaps = await db.collection('appointments')
        .where('servico_nome', '==', 'Boxbraids Masculina')
        .get();

    console.log(`Encontrados ${snaps.size} agendamentos de Boxbraids Masculina`);

    for (const doc of snaps.docs) {
        const data = doc.data();
        console.log(`\nAgendamento ID: ${doc.id}`);
        console.log(`- Shop ID: ${data.shopId}`);
        console.log(`- Profissional ID: ${data.profissionalId}`);
        console.log(`- Serviço ID: ${data.servicoId}`);

        if (data.shopId) {
            const shopSnap = await db.collection('shops').doc(data.shopId).get();
            console.log(`  Shop Existe? ${shopSnap.exists}`);

            if (data.servicoId) {
                const sSnap = await db.collection('shops').doc(data.shopId).collection('services').doc(data.servicoId).get();
                console.log(`  Serviço Existe? ${sSnap.exists}`);
            }
        }
        if (data.profissionalId) {
            const pSnap = await db.collection('employees').doc(data.profissionalId).get();
            console.log(`  Profissional Existe? ${pSnap.exists}`);
        }
    }
}

check().catch(console.error).finally(() => process.exit(0));
