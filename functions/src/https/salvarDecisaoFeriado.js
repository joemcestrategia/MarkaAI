const { onCall } = require("firebase-functions/v2/https");
const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

/**
 * Salva a decisão do gestor sobre o funcionamento do salão em um feriado específico.
 */
exports.salvarDecisaoFeriado = onCall(async (request) => {
  // 1. Verificar autenticação
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuário não autenticado.");
  }

  const { shopId, data, decisao } = request.data;
  // A decisao pode ser uma string ("fechado", "sem_impacto") 
  // ou um objeto { escala: [...] } vindo do Flutter no decisaoPayload.

  if (!shopId || !data || !decisao) {
    throw new HttpsError("invalid-argument", "Campos shopId, data e decisao são obrigatórios.");
  }

  const db = admin.firestore();
  const shopRef = db.collection("shops").doc(shopId);
  const shopDoc = await shopRef.get();

  if (!shopDoc.exists) {
    throw new HttpsError("not-found", "Salão não encontrado.");
  }

  const shopData = shopDoc.data();

  // 2. Verificar se o usuário é o dono do salão
  // Nota: Verificando múltiplos campos possíveis para dono (padrão do projeto)
  const ownerId = shopData.owner_uid || shopData.ownerId || shopData.userId || 
                  shopData.dono_id || shopData.uid || shopData.dono_uid || shopData.shopId;
  const isOwner = (ownerId === request.auth.uid) || (shopDoc.id === request.auth.uid);

  if (!isOwner) {
    throw new HttpsError("permission-denied", "Apenas o dono do salão pode salvar decisões de feriados.");
  }

  // 3. Verificar permissão de plano (Plus ou Pro)
  if (!["plus", "pro"].includes(shopData.plan)) {
    throw new HttpsError("permission-denied", "Recurso disponível apenas nos planos Plus e Pro.");
  }

  try {
    // Montar o valor da decisão
    // O Flutter envia 'decisao' como o payload completo (ja pronto)
    const decisaoValor = decisao;

    // 4. Gravar decisão e remover dos pendentes atomicamente
    await shopRef.update({
      [`feriados_configurados.${data}`]: decisaoValor,
      feriados_pendentes: admin.firestore.FieldValue.arrayRemove(data)
    });

    return { success: true };
  } catch (error) {
    console.error(`[feriados] Erro ao salvar decisão para ${shopId} na data ${data}:`, error);
    throw new HttpsError("internal", "Erro ao salvar decisão no servidor.");
  }
});
