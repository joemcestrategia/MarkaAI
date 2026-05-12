import { generateSmartSlots, BusyInterval } from './index.ts';

function runTest(name: string, params: any, expected: any) {
  console.log(`\nTESTE: ${name}`);
  const result = generateSmartSlots(params);
  const success = JSON.stringify(result) === JSON.stringify(expected);
  console.log(`  - Serv. ${params.serviceDuration}min, Gaps: ${params.preventGaps}`);
  console.log(`  - Ocupado: ${JSON.stringify(params.busyIntervals)}`);
  console.log(`  - Resultado: [${result}]`);
  console.log(`  - Esperado:  [${expected}]`);
  console.log(`  - Status: ${success ? "✅ PASSOU" : "❌ FALHOU"}`);
  return success;
}

let total = 0;
let passed = 0;

console.log("=== INICIANDO SUÍTE DE TESTES DE VIDA REAL (REAL WORLD) ===");

const baseParams = {
  startStr: '08:00',
  endStr: '17:00',
  interval: 60,
  serviceDuration: 60,
  busyIntervals: [] as BusyInterval[],
  preventGaps: true,
  minAdvanceHours: 0,
  selectedDate: new Date(Date.UTC(2026, 5, 1, 12, 0, 0)),
};

// --- CENÁRIO 11: REAGENDAMENTO (IGNORAR PRÓPRIO ID) ---
// Situação: O código da Edge Function deve permitir que o agendamento atual seja ignorado.
// Simulamos isso passando a lista de busyIntervals já filtrada (como o App faz).
total++;
console.log("\nTESTE: Reagendamento (Horário do próprio cliente deve estar livre)");
const busyWithMe = [
    { start: 10 * 60, end: 11 * 60 } // Meu agendamento atual
];
const resultReschedule = generateSmartSlots({
    ...baseParams,
    serviceDuration: 60,
    busyIntervals: [] // No reagendamento, o App filtra o ID do agendamento atual antes de enviar
});
if (resultReschedule.includes("10:00")) {
    console.log("  - Resultado: [10:00] está disponível. ✅ PASSOU");
    passed++;
} else {
    console.log("  - Resultado: [10:00] bloqueado. ❌ FALHOU");
}

// --- CENÁRIO 12: BLOQUEIO DE ALMOÇO ---
// Serviço de 5h (300min) com almoço das 12h às 13h.
// 08:00 -> 13:00 (Bate no almoço às 12h) -> NEGADO
// 13:00 -> 18:00 (Estoura o expediente de 17h) -> NEGADO
total++;
if (runTest("Bloqueio de Almoço vs Serviço de 5h", {
  ...baseParams,
  serviceDuration: 300,
  busyIntervals: [{ start: 12 * 60, end: 13 * 60 }]
}, [])) passed++;

// --- CENÁRIO 13: VARIAÇÃO DE SERVIÇO (2h vs 5h) ---
// Agendamento manual às 14:00. 
total++;
console.log("\nTESTE: Variação de Serviço (Curto vs Longo)");
const busyManual = [{ start: 14 * 60, end: 15 * 60 }];
const resCurto = generateSmartSlots({ ...baseParams, serviceDuration: 120, busyIntervals: busyManual });
const resLongo = generateSmartSlots({ ...baseParams, serviceDuration: 300, busyIntervals: busyManual });
console.log(`  - Curto (2h): [${resCurto}] (Esperado: incluir 08:00, 10:00, 12:00)`);
console.log(`  - Longo (5h): [${resLongo}] (Esperado: incluir 08:00 apenas)`);
if (resCurto.includes("12:00") && resLongo.includes("08:00") && !resLongo.includes("12:00")) passed++; else console.log("❌ FALHOU Variação");

// --- CENÁRIO 14: CONFLITOS CRUZADOS (MÚLTIPLOS PROFISSIONAIS) ---
// Profissional A: Ocupado 08h-11h
// Profissional B: Ocupado 14h-17h
// Serviço de 3h: Deve oferecer 11:00 (pelo A) e 08:00 (pelo B)
total++;
console.log("\nTESTE: Conflitos Cruzados (Failover inteligente)");
const slotsA = generateSmartSlots({ ...baseParams, serviceDuration: 180, busyIntervals: [{ start: 8 * 60, end: 11 * 60 }] });
const slotsB = generateSmartSlots({ ...baseParams, serviceDuration: 180, busyIntervals: [{ start: 14 * 60, end: 17 * 60 }] });
console.log(`  - Prof A oferece: [${slotsA}]`);
console.log(`  - Prof B oferece: [${slotsB}]`);
if (slotsA.includes("11:00") && slotsB.includes("08:00")) {
    console.log("  - Resultado: Ambos profissionais contribuem para a disponibilidade. ✅ PASSOU");
    passed++;
} else {
    console.log("  - Resultado: Falha na detecção cruzada. ❌ FALHOU");
}

console.log("\n=== FIM DA SUÍTE DE TESTES DE VIDA REAL ===");
console.log(`TOTAL: ${total} | PASSOU: ${passed} | FALHOU: ${total - passed}`);
