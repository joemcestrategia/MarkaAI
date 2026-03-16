const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
const { fetchFeriadosNacionais } = require("../services/brasilapi");

/**
 * Cloud Function agendada para rodar toda madrugada às 00:30 (Brasília).
 * Identifica feriados nacionais e personalizados pendentes de decisão na janela de agendamento.
 */
exports.calcularFeriadosPendentes = onSchedule({
  schedule: "30 0 * * *",
  timeZone: "America/Sao_Paulo",
  memory: "256MiB",
  region: "us-central1",
}, async (event) => {
  const db = admin.firestore();
  
  // Data de hoje em formato ISO (YYYY-MM-DD)
  const hoje = new Date();
  const hojeISO = hoje.toISOString().split("T")[0];

  try {
    // 1. Buscar salões elegíveis (Plus e Pro ativos)
    // Nota: Usando 'shops' e 'plan' conforme padrão do projeto identificado no index.js
    const shopsSnap = await db.collection("shops")
      .where("plan", "in", ["plus", "pro"])
      .get();

    if (shopsSnap.empty) {
      console.log("[feriados] Nenhum salão elegível encontrado.");
      return;
    }

    // Cache de feriados por ano para evitar chamadas redundantes à BrasilAPI no mesmo lote
    const yearlyHolidays = {};

    // 2. Processar salões em lotes de 10 para eficiência e controle de concorrência
    const shops = shopsSnap.docs;
    for (let i = 0; i < shops.length; i += 10) {
      const chunk = shops.slice(i, i + 10);
      
      await Promise.all(chunk.map(async (shopDoc) => {
        try {
          const shopData = shopDoc.data();
          const shopId = shopDoc.id;

          // Se o salão não estiver "ativo", pulamos (verificação de status flexível)
          if (shopData.status !== "ativo" && shopData.status !== "active") {
            return;
          }

          // Cálculo da janela de radar
          const diasAgenda = shopData.dias_agenda_padrao || 30;
          const diasVip = shopData.dias_extras_vip || 0;
          const totalRadar = diasAgenda + diasVip;

          const dataFim = new Date();
          dataFim.setDate(hoje.getDate() + totalRadar);
          const dataFimISO = dataFim.toISOString().split("T")[0];

          // 3. Montar lista de feriados (Nacionais + Personalizados)
          const anosNecessarios = new Set([hoje.getFullYear(), dataFim.getFullYear()]);
          let todosFeriados = [];

          for (const ano of anosNecessarios) {
            if (!yearlyHolidays[ano]) {
              yearlyHolidays[ano] = await fetchFeriadosNacionais(ano);
            }
            todosFeriados = todosFeriados.concat(yearlyHolidays[ano]);
          }

          // Feriados personalizados (apenas para plano Pro)
          if (shopData.plan === "pro" && Array.isArray(shopData.feriados_personalizados)) {
            todosFeriados = todosFeriados.concat(shopData.feriados_personalizados);
          }

          // 4. Filtrar pendentes (dentro da janela e sem decisão salva)
          const configurados = shopData.feriados_configurados || {};
          const feriadosPendentes = [];

          for (const feriado of todosFeriados) {
            const fDate = feriado.date;
            
            // Critério 1: Dentro da janela de radar
            const dentroJanela = fDate >= hojeISO && fDate <= dataFimISO;
            
            // Critério 2: Ainda não tem decisão salva pelo gestor
            const pendente = !(fDate in configurados);

            if (dentroJanela && pendente) {
              feriadosPendentes.push(fDate);
            }
          }

          // 5. Gravar no Firestore
          await shopDoc.ref.update({
            feriados_pendentes: feriadosPendentes,
            feriados_pendentes_updated_at: admin.firestore.FieldValue.serverTimestamp()
          });

        } catch (err) {
          console.error(`[feriados] Erro no salão ${shopDoc.id}:`, err);
        }
      }));
    }

    console.log(`[feriados] Processamento concluído para ${shops.length} salões.`);
  } catch (error) {
    console.error("[feriados] Erro geral na execução do CRON:", error);
  }
});
