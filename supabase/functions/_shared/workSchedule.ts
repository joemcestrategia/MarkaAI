// Helper compartilhado para resolver a jornada por dia da semana de um employee.
// Padrão Dart: 1=Seg ... 7=Dom. Lê work_schedule (novo) com fallback legado.

export interface DayBreak {
  start: string; // HH:mm
  end: string;   // HH:mm
}

export interface DaySchedule {
  start: string;
  end: string;
  break: DayBreak | null;
}

export type WorkSchedule = Map<number, DaySchedule>;

export function parseWorkSchedule(empRow: Record<string, unknown>): WorkSchedule {
  const out: WorkSchedule = new Map();

  const ws = (empRow as any).work_schedule;
  if (ws && typeof ws === 'object' && !Array.isArray(ws)) {
    let anyEnabled = false;
    for (let d = 1; d <= 7; d++) {
      const day = ws[String(d)] ?? ws[d];
      if (!day || typeof day !== 'object') continue;
      if (day.enabled !== true) continue;
      anyEnabled = true;
      const start = String(day.start ?? '').trim();
      const end = String(day.end ?? '').trim();
      if (!start || !end) continue;
      let br: DayBreak | null = null;
      if (day.break && typeof day.break === 'object') {
        const bs = String(day.break.start ?? '').trim();
        const be = String(day.break.end ?? '').trim();
        if (bs && be) br = { start: bs, end: be };
      }
      out.set(d, { start, end, break: br });
    }
    // Se há work_schedule explícito, respeitar (mesmo vazio = sem dias).
    if (anyEnabled || Object.keys(ws as object).length > 0) return out;
  }

  // Fallback legado.
  const wdRaw = (empRow as any).work_days;
  const wd: number[] = Array.isArray(wdRaw)
    ? wdRaw.map((v: unknown) => Number(v)).filter((v: number) => v >= 1 && v <= 7)
    : [];
  const start = String(
    (empRow as any).work_start || (empRow as any).start_time || '08:00',
  );
  const end = String(
    (empRow as any).work_end || (empRow as any).end_time || '18:00',
  );
  for (const d of wd) {
    out.set(d, { start, end, break: null });
  }
  return out;
}

/** Converte weekday do JS Date.getDay() (0=Dom..6=Sáb) para padrão Dart (1=Seg..7=Dom). */
export function jsDowToDartWeekday(jsDow: number): number {
  return jsDow === 0 ? 7 : jsDow;
}

/** "HH:mm" -> minutos do dia. */
export function hhmmToMin(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return (h || 0) * 60 + (m || 0);
}
