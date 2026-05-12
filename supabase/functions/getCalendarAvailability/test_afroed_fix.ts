import { generateSmartSlots, BusyInterval } from './index.ts';

console.log("=== SIMULANDO O ERRO HISTÓRICO DA AFROED (19 DE MAIO) ===");

const shopConfig = {
  evitar_buracos_agenda: true,
  limite_minimo_agendamento_horas: 48,
  intervalo_agenda_min: 60,
};

const serviceDuration = 360; // 6 horas (Boxbraids)
const selectedDate = new Date(Date.UTC(2026, 4, 19)); // 19 de Maio de 2026

// No dia 19, Dionathan está ocupado com Dudinha Oliveira às 08:00
const dionathanBusy: BusyInterval[] = [{ start: 8 * 60, end: 14 * 60 }];

// Edmara está totalmente livre no dia 19
const edmaraBusy: BusyInterval[] = [];

console.log("Passo 1: Verificando disponibilidade para Dionathan...");
const slotsDionathan = generateSmartSlots({
  startStr: '08:00',
  endStr: '17:00',
  interval: 60,
  serviceDuration,
  busyIntervals: dionathanBusy,
  preventGaps: true,
  minAdvanceHours: 0,
  selectedDate,
});
console.log(`  - Dionathan tem slots? ${slotsDionathan.length > 0 ? "SIM" : "NÃO"} [${slotsDionathan}]`);

console.log("\nPasso 2: Verificando disponibilidade para Edmara...");
const slotsEdmara = generateSmartSlots({
  startStr: '08:00',
  endStr: '17:00',
  interval: 60,
  serviceDuration,
  busyIntervals: edmaraBusy,
  preventGaps: true,
  minAdvanceHours: 0,
  selectedDate,
});
console.log(`  - Edmara tem slots? ${slotsEdmara.length > 0 ? "SIM" : "NÃO"} [${slotsEdmara}]`);

// A lógica da Edge Function faz o seguinte:
const dayAvailable = slotsDionathan.length > 0 || slotsEdmara.length > 0;

console.log("\n=== VEREDITO FINAL DA EDGE FUNCTION ===");
console.log(`O dia 19 de Maio deve aparecer como: ${dayAvailable ? "DISPONÍVEL ✅" : "INDISPONÍVEL ❌"}`);

if (dayAvailable && slotsDionathan.length === 0 && slotsEdmara.length > 0) {
    console.log("\n🔥 SUCESSO TOTAL! A Edge Function corrigiu o erro: ");
    console.log("Ela detectou que, embora o profissional prioritário estivesse ocupado,");
    console.log("a vaga existia com a segunda profissional. O dia NÃO será mais perdido.");
} else {
    console.log("\n⚠️ Algo falhou na simulação.");
}
