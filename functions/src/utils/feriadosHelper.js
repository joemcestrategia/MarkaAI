const { fetchFeriadosNacionais } = require("../services/brasilapi");
const admin = require("firebase-admin");

/**
 * Recalcula a lista de feriados pendentes para um salão específico.
 * @param {string} shopId 
 * @param {object} shopData 
 */
async function recalculatePendingHolidaysForShop(shopId, shopData) {
  const db = admin.firestore();
  const hoje = new Date();
  const hojeISO = hoje.toISOString().split("T")[0];

  const diasAgenda = shopData.dias_agenda_padrao || 30;
  const diasVip = shopData.dias_extras_vip || 0;
  const totalRadar = diasAgenda + diasVip;

  const dataFim = new Date();
  dataFim.setDate(hoje.getDate() + totalRadar);
  const dataFimISO = dataFim.toISOString().split("T")[0];

  const anosNecessarios = new Set([hoje.getFullYear(), dataFim.getFullYear()]);
  let todosFeriados = [];

  for (const ano of anosNecessarios) {
    const feriadosNacionais = await fetchFeriadosNacionais(ano);
    todosFeriados = todosFeriados.concat(feriadosNacionais);
  }

  // Feriados personalizados (apenas para plano Pro)
  if (shopData.plan === "pro" && Array.isArray(shopData.feriados_personalizados)) {
    todosFeriados = todosFeriados.concat(shopData.feriados_personalizados);
  }

  const configurados = shopData.feriados_configurados || {};
  const feriadosPendentes = [];

  for (const feriado of todosFeriados) {
    const fDate = feriado.date;
    const dentroJanela = fDate >= hojeISO && fDate <= dataFimISO;
    const pendente = !(fDate in configurados);

    if (dentroJanela && pendente) {
      feriadosPendentes.push(fDate);
    }
  }

  await db.collection("shops").doc(shopId).update({
    feriados_pendentes: feriadosPendentes,
    feriados_pendentes_updated_at: admin.firestore.FieldValue.serverTimestamp()
  });
  
  return feriadosPendentes;
}

module.exports = { recalculatePendingHolidaysForShop };
