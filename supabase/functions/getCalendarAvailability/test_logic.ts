import { generateSmartSlots, BusyInterval } from './index.ts';

// Mock data for AfroED
const shopConfig = {
  evitar_buracos_agenda: true,
  limite_minimo_agendamento_horas: 48,
  intervalo_agenda_min: 60,
};

const serviceDuration = 360; // 6 hours

// May 26, 2026: Tuesday (Weekday 2)
const selectedDate = new Date(Date.UTC(2026, 4, 26)); 

// Dionathan busy intervals on May 26 (08:00 to 14:00)
const dionathanBusy: BusyInterval[] = [{ start: 8 * 60, end: 14 * 60 }];

// Edmara busy intervals on May 26 (Empty)
const edmaraBusy: BusyInterval[] = [];

console.log("--- Testando Lógica para 26 de Maio (Boxbraids 6h) ---");

const dionathanSlots = generateSmartSlots({
  startStr: '08:00',
  endStr: '17:00',
  interval: 60,
  serviceDuration,
  busyIntervals: dionathanBusy,
  preventGaps: true,
  minAdvanceHours: 48,
  selectedDate,
});

console.log(`Dionathan slots: [${dionathanSlots}] (Esperado: vazio, pois 14h-17h < 6h)`);

const edmaraSlots = generateSmartSlots({
  startStr: '08:00',
  endStr: '17:00',
  interval: 60,
  serviceDuration,
  busyIntervals: edmaraBusy,
  preventGaps: true,
  minAdvanceHours: 48,
  selectedDate,
});

console.log(`Edmara slots: [${edmaraSlots}] (Esperado: 08:00, pois ela está livre e trabalha 9h)`);

const dayHasSlot = dionathanSlots.length > 0 || edmaraSlots.length > 0;
console.log(`Resultado do Dia: ${dayHasSlot ? "DISPONÍVEL" : "INDISPONÍVEL"} (Esperado: DISPONÍVEL)`);

if (dayHasSlot === true) {
  console.log("✅ SUCESSO: A lógica da Edge Function resolve o problema do calendário!");
} else {
  console.log("❌ FALHA: A lógica ainda não está correta.");
}
