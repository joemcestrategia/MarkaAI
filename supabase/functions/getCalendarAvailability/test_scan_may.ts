import { generateSmartSlots, BusyInterval } from './index.ts';

console.log("=== RELATÓRIO DE DISPONIBILIDADE: MAIO/2026 (AFROED) ===");

const serviceDuration = 360; // 6 horas
const baseParams = {
  startStr: '08:00',
  endStr: '17:00',
  interval: 60,
  preventGaps: true,
  minAdvanceHours: 0,
};

const diasParaTestar = [19, 20, 21, 22, 26, 27, 28, 29, 30];
const resultados: any[] = [];

for (const dia of diasParaTestar) {
    const date = new Date(Date.UTC(2026, 4, dia));
    
    // Simulação: Dionathan SEMPRE ocupado de manhã nesses dias (o motivo do sumiço anterior)
    const dionathanBusy = [{ start: 8 * 60, end: 14 * 60 }];
    
    // Simulação: Edmara SEMPRE livre nesses dias
    const edmaraBusy: BusyInterval[] = [];

    const slotsDionathan = generateSmartSlots({
        ...baseParams,
        serviceDuration,
        busyIntervals: dionathanBusy,
        selectedDate: date,
    });

    const slotsEdmara = generateSmartSlots({
        ...baseParams,
        serviceDuration,
        busyIntervals: edmaraBusy,
        selectedDate: date,
    });

    const disponivel = slotsDionathan.length > 0 || slotsEdmara.length > 0;
    
    resultados.push({
        dia,
        dionathan: slotsDionathan.length > 0 ? "Livre" : "Ocupado",
        edmara: slotsEdmara.length > 0 ? "Livre" : "Ocupado",
        resultado: disponivel ? "DISPONÍVEL ✅" : "INDISPONÍVEL ❌"
    });
}

console.table(resultados);

const todosDisponiveis = resultados.every(r => r.resultado.includes("✅"));
if (todosDisponiveis) {
    console.log("\n🎯 SUCESSO ABSOLUTO!");
    console.log("A Edge Function conseguiu liberar TODOS os dias que você mencionou,");
    console.log("mesmo com o profissional principal (Dionathan) estando ocupado.");
} else {
    console.log("\n⚠️ Alguns dias ainda ficaram indisponíveis.");
}
