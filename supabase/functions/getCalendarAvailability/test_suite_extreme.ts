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

console.log("=== INICIANDO SUÍTE DE TESTES EXTREMOS (EXPERT SCENARIOS) ===");

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

// --- CENÁRIO 7: O QUEBRA-CABEÇA (FRAGMENTAÇÃO) ---
// Agenda: 09:00-10:00 e 12:00-13:00. 
// Com preventGaps: true, só deve oferecer 08:00, 10:00 e 13:00.
// 11:00 deve ser negado pois criaria um buraco entre 10h e 11h e outro entre 12h e 13h.
total++;
if (runTest("Fragmentação (Âncoras Estritas)", {
  ...baseParams,
  serviceDuration: 60,
  busyIntervals: [
    { start: 9 * 60, end: 10 * 60 },
    { start: 12 * 60, end: 13 * 60 }
  ]
}, ["08:00", "10:00", "13:00"])) passed++;

// --- CENÁRIO 8: LIMITE MATEMÁTICO (60 vs 61 minutos) ---
// Buraco exato das 10h às 11h.
total++;
const busyLimited = [
  { start: 8 * 60, end: 10 * 60 },
  { start: 11 * 60, end: 13 * 60 }
];
console.log("\nTESTE: Limite Matemático (61min num buraco de 60min)");
const res61 = generateSmartSlots({ ...baseParams, serviceDuration: 61, busyIntervals: busyLimited });
const res60 = generateSmartSlots({ ...baseParams, serviceDuration: 60, busyIntervals: busyLimited });
console.log(`  - 61min: [${res61}] (Esperado: [13:00])`);
console.log(`  - 60min: [${res60}] (Esperado: [10:00, 13:00])`);
if (res61.length === 1 && res61[0] === "13:00" && res60.includes("10:00")) passed++; else console.log("❌ FALHOU Limite Matemático");

// --- CENÁRIO 9: ANTECEDÊNCIA MÍNIMA (O CORTE DAS 48H) ---
// Se "hoje" é 08 de Maio, "amanhã" (09 de Maio) deve estar bloqueado se a trava for 48h.
total++;
const tomorrowReal = new Date();
tomorrowReal.setDate(tomorrowReal.getDate() + 1); // Amanhã
if (runTest("Trava de Antecedência (48h)", {
  ...baseParams,
  selectedDate: tomorrowReal,
  minAdvanceHours: 48, 
  busyIntervals: []
}, [])) passed++; 

// --- CENÁRIO 10: OTIMIZAÇÃO COM SERVIÇO LONGO ---
// Loja fecha às 17h. Se houver um manual das 10h às 11h.
// Um serviço de 6h (360min) cabe? 
// 08:00 -> 14:00 (NÃO, bate nas 10:00)
// 11:00 -> 17:00 (SIM, termina exatamente às 17:00)
total++;
if (runTest("Serviço Longo após Agendamento Manual", {
  ...baseParams,
  serviceDuration: 360,
  busyIntervals: [{ start: 10 * 60, end: 11 * 60 }]
}, ["11:00"])) passed++;

console.log("\n=== FIM DA SUÍTE DE TESTES EXTREMOS ===");
console.log(`TOTAL: ${total} | PASSOU: ${passed} | FALHOU: ${total - passed}`);
if (total === passed) console.log("\n✅ A LÓGICA É INDESTRUTÍVEL.");
else console.log("\n⚠️ AJUSTES NECESSÁRIOS DETECTADOS.");
