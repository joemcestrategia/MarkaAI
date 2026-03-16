const { onCall } = require("firebase-functions/v2/https");
const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { recalculatePendingHolidaysForShop } = require("../utils/feriadosHelper");

/**
 * Permite ao dono do salão (plano Pro) gerenciar feriados personalizados.
 */
exports.salvarFeriadoPersonalizado = onCall(async (request) => {
  // 1. Verificar autenticação
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Usuário não autenticado.");
  }

  const { shopId, action, date, name } = request.data;

  if (!shopId || !action || !date) {
    throw new HttpsError("invalid-argument", "Campos shopId, action e date são obrigatórios.");
  }

  const db = admin.firestore();
  const shopRef = db.collection("shops").doc(shopId);
  const shopDoc = await shopRef.get();

  if (!shopDoc.exists) {
    throw new HttpsError("not-found", "Salão não encontrado.");
  }

  const shopData = shopDoc.data();

  // 2. Verificar se o usuário é o dono do salão
  const ownerId = shopData.owner_uid || shopData.ownerId || shopData.userId || 
                  shopData.dono_id || shopData.uid || shopData.dono_uid || shopData.shopId;
  const isOwner = (ownerId === request.auth.uid) || (shopDoc.id === request.auth.uid);

  if (!isOwner) {
    throw new HttpsError("permission-denied", "Apenas o dono do salão pode gerenciar feriados.");
  }

  // 3. Verificar permissão de plano (Somente Pro)
  if (shopData.plan !== "pro") {
    throw new HttpsError("permission-denied", "Feriados personalizados estão disponíveis apenas no plano Pro.");
  }

  try {
    const feriadoCustom = { date, name: name || "Feriado Local", type: "custom" };

    if (action === "add") {
      // 4. Adicionar feriado personalizado
      await shopRef.update({
        feriados_personalizados: admin.firestore.FieldValue.arrayUnion(feriadoCustom)
      });
    } else if (action === "remove") {
      // 5. Remover feriado personalizado
      // Buscamos o item exato para remover (arrayRemove precisa do objeto idêntico)
      const list = shopData.feriados_personalizados || [];
      const itemParaRemover = list.find((f) => f.date === date);

      if (itemParaRemover) {
        await shopRef.update({
          feriados_personalizados: admin.firestore.FieldValue.arrayRemove(itemParaRemover)
        });
      } else {
        // Se não achar o item exato, tentamos remover um objeto genérico com a data (fallback)
        await shopRef.update({
          feriados_personalizados: admin.firestore.FieldValue.arrayRemove({ date, name: name || "Feriado Local", type: "custom" })
        });
      }
    } else {
      throw new HttpsError("invalid-argument", "Ação inválida. Use 'add' ou 'remove'.");
    }

    // 6. Recalcular feriados pendentes imediatamente após a mudança
    // Recarregamos o dado atualizado para garantir o cálculo correto
    const updatedShopDoc = await shopRef.get();
    const updatedPendentes = await recalculatePendingHolidaysForShop(shopId, updatedShopDoc.data());

    return { 
      success: true,
      feriados_pendentes: updatedPendentes
    };
  } catch (error) {
    console.error(`[feriados] Erro ao gerenciar feriado personalizado para ${shopId}:`, error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", "Erro ao processar feriado personalizado.");
  }
});
