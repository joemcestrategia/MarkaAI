const { initializeApp, cert } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");

// ✅ Inicialização obrigatória do Admin SDK
// Certifique-se de que o arquivo service-account-key.json existe no diretório scripts/
const serviceAccount = require("./service-account-key.json");

initializeApp({
  credential: cert(serviceAccount),
  projectId: "markaai-prod" // ⚠️ SUBSTITUIR PELO ID REAL DO PROJETO SE NECESSÁRIO
});

/**
 * Script de Migração: clients -> clientsSummary
 * Processa em lotes de 499 com logs de progresso e tratamento de erro.
 */
async function migrateClientsToSummary() {
  const db = getFirestore();
  
  try {
    const shopsSnapshot = await db.collection("shops").get();
    
    let totalProcessed = 0;
    let totalSuccess = 0;
    let totalError = 0;

    for (const shopDoc of shopsSnapshot.docs) {
      const shopId = shopDoc.id;
      const clientsRef = db.collection(`shops/${shopId}/clients`);
      const clientsSnapshot = await clientsRef.get();
      
      if (clientsSnapshot.empty) continue;

      const docs = clientsSnapshot.docs;
      const totalShopClients = docs.length;
      console.log(`\n📦 Iniciando Loja: ${shopId} (${totalShopClients} clientes)`);

      const BATCH_LIMIT = 499;

      for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
        const batch = db.batch();
        const chunk = docs.slice(i, i + BATCH_LIMIT);

        chunk.forEach((clientDoc) => {
          const data = clientDoc.data();
          const summaryRef = db.doc(`shops/${shopId}/clientsSummary/${clientDoc.id}`);
          
          batch.set(summaryRef, {
            name: data.name || "Sem Nome",
            phone: data.phone || "",
            phoneNormalized: data.phoneNormalized || "",
            lastVisitAt: data.lastVisitAt || null,
            migratedAt: Timestamp.now()
          }, { merge: true });
        });

        try {
          await batch.commit();
          totalSuccess += chunk.length;
          console.log(`  ✅ Processados ${i + chunk.length} de ${totalShopClients}...`);
        } catch (error) {
          console.error(`  ❌ Erro no lote da loja ${shopId}. Tentando um por um...`);
          for (const docSnapshot of chunk) {
             try {
               const data = docSnapshot.data();
               await db.doc(`shops/${shopId}/clientsSummary/${docSnapshot.id}`).set({
                 name: data.name || "Sem Nome",
                 phone: data.phone || "",
                 phoneNormalized: data.phoneNormalized || "",
                 lastVisitAt: data.lastVisitAt || null,
                 migratedAt: Timestamp.now()
               }, { merge: true });
               totalSuccess++;
             } catch (e) { 
               console.error(`    - Falha crítica no doc ${docSnapshot.id}`); 
               totalError++;
             }
          }
        }
        totalProcessed += chunk.length;
      }
    }

    console.log(`\n✨ MIGRACÃO CONCLUÍDA ✨`);
    console.log(`------------------------`);
    console.log(`Total Sucesso: ${totalSuccess}`);
    console.log(`Total Erro:    ${totalError}`);
    console.log(`Total Geral:   ${totalProcessed}`);

  } catch (error) {
    console.error("❌ Erro fatal durante a migração:", error);
    throw error;
  }
}

migrateClientsToSummary()
  .then(() => {
    console.log("🚀 Processo finalizado com sucesso.");
    process.exit(0);
  })
  .catch((err) => {
    console.error("❌ Erro não capturado no nível superior:", err);
    process.exit(1);
  });
