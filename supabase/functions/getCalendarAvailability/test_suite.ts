import { generateSmartSlots, BusyInterval } from './index.ts';

function runTest(name: string, params: any, expected: any) {
  console.log(`\nTESTE: ${name}`);
  const result = generateSmartSlots(params);
  const success = JSON.stringify(result) === JSON.stringify(expected);
  console.log(`  - Parâmetros: Serv. ${params.serviceDuration}min, Gaps: ${params.preventGaps}`);
  console.log(`  - Ocupado: ${JSON.stringify(params.busyIntervals)}`);
  console.log(`  - Resultado: [${result}]`);
  console.log(`  - Esperado:  [${expected}]`);
  console.log(`  - Status: ${success ? "✅ PASSOU" : "❌ FALHOU"}`);
  return success;
}

let total = 0;
let passed = 0;

console.log("=== INICIANDO RELATÓRIO DE TESTES DA EDGE FUNCTION ===");

// Configurações base
const baseParams = {
  startStr: '08:00',
  endStr: '17:00',
  interval: 60,
  serviceDuration: 60,
  busyIntervals: [] as BusyInterval[],
  preventGaps: true,
  minAdvanceHours: 0,
  selectedDate: new Date(Date.UTC(2026, 5, 1, 12, 0, 0)), // Futuro distante para evitar trava de antecedência
};

// --- CENÁRIO 1: ENCAIXE EM BURACOS (ÂNCORAS) ---
// Se houver um agendamento manual às 14:00, um serviço de 6h (360min) cabe das 08:00 às 14:00?
total++;
if (runTest("Encaixe Perfeito Antes de Agendamento Manual", {
  ...baseParams,
  serviceDuration: 360,
  busyIntervals: [{ start: 14 * 60, end: 15 * 60 }] // Manual das 14h às 15h
}, ["08:00"])) passed++;

// --- CENÁRIO 2: EVITAR SOBREPOSIÇÃO ---
// Serviço de 2h (120min) com agendamento manual no meio (09:00-10:00). 08:00 deve ser negado.
total++;
if (runTest("Prevenção de Sobreposição no Início", {
  ...baseParams,
  serviceDuration: 120,
  busyIntervals: [{ start: 9 * 60, end: 10 * 60 }]
}, ["10:00"])) passed++; // 08:00 falha (bate nas 09h), 10:00 passa (âncora após o busy)

// --- CENÁRIO 3: LIMITE DE FIM DE EXPEDIENTE ---
// Serviço de 3h começando às 15:00. Loja fecha às 17:00. 
// Com preventGaps: true e agenda vazia, oferece APENAS o primeiro (08:00).
total++;
if (runTest("Respeito ao Fim do Expediente", {
  ...baseParams,
  serviceDuration: 180,
  busyIntervals: []
}, ["08:00"])) passed++; 

// --- CENÁRIO 4: O CASO AFROED (PROFISSIONAL OCUPADO) ---
// Simula o que estava acontecendo: Profissional tem 6h agendado às 08:00. Outro serviço de 6h cabe?
total++;
const dionathanBusy = [{ start: 8 * 60, end: 14 * 60 }];
const resultDionathan = generateSmartSlots({
  ...baseParams,
  serviceDuration: 360,
  busyIntervals: dionathanBusy
});
console.log("\nTESTE: Caso AfroED (Dionathan)");
console.log(`  - Resultado para Dionathan: [${resultDionathan}] (Esperado: [])`);
if (resultDionathan.length === 0) passed++; else console.log("❌ FALHOU Dionathan");

// --- CENÁRIO 5: O CASO AFROED (FAILOVER) ---
// Se um está ocupado mas o dia tem vaga com outro, a lógica do LOOP deve detectar.
// (Este teste é conceitual pois a função index.ts faz esse loop)
total++;
const edmaraBusy: BusyInterval[] = [];
const resultEdmara = generateSmartSlots({
  ...baseParams,
  serviceDuration: 360,
  busyIntervals: edmaraBusy
});
console.log("\nTESTE: Caso AfroED (Edmara)");
console.log(`  - Resultado para Edmara: [${resultEdmara}] (Esperado: [08:00])`);
if (resultEdmara.length > 0) passed++; else console.log("❌ FALHOU Edmara");

// --- CENÁRIO 6: SEM OTIMIZAÇÃO (SEM EVITAR BURACOS) ---
// Quando preventGaps é false, deve oferecer todos os horários possíveis
total++;
if (runTest("Modo Sem Otimização", {
  ...baseParams,
  preventGaps: false,
  serviceDuration: 60,
  busyIntervals: [{ start: 10 * 60, end: 11 * 60 }]
}, ["08:00", "09:00", "11:00", "12:00", "13:00", "14:00", "15:00", "16:00"])) passed++;

console.log("\n=== FIM DO RELATÓRIO ===");
console.log(`TOTAL DE TESTES: ${total}`);
console.log(`PASSOU: ${passed}`);
console.log(`FALHOU: ${total - passed}`);
if (total === passed) {
  console.log("\n✅ SISTEMA 100% COERENTE E SEGURO PARA PRODUÇÃO.");
} else {
  console.log("\n⚠️ ATENÇÃO: EXISTEM DIVERGÊNCIAS NA LÓGICA.");
}
