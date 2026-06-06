
export interface BusyInterval {
  start: number;
  end: number;
}

export function generateSmartSlots({
  startStr,
  endStr,
  interval,
  serviceDuration,
  busyIntervals,
  preventGaps,
  minAdvanceHours,
  selectedDate,
}: {
  startStr: string;
  endStr: string;
  interval: number;
  serviceDuration: number;
  busyIntervals: BusyInterval[];
  preventGaps: boolean;
  minAdvanceHours: number;
  selectedDate: Date;
}): string[] {
  const validSlots: string[] = [];

  const [startH, startM] = startStr.split(':').map(Number);
  const [endH, endM] = endStr.split(':').map(Number);
  const startDayMin = startH * 60 + startM;
  const endDayMin = endH * 60 + endM;

  if (interval <= 0) return [];

  const sortedBusy = [...busyIntervals].sort((a, b) => a.start - b.start);

  const now = new Date();
  const brazilNow = new Date(now.getTime() - (3 * 60 * 60 * 1000));
  const minAllowedTime = new Date(brazilNow.getTime() + minAdvanceHours * 60 * 60 * 1000);

  if (preventGaps) {
    if (sortedBusy.length === 0) {
      let current = startDayMin;
      while (current + serviceDuration <= endDayMin) {
        const slotDt = new Date(selectedDate);
        slotDt.setUTCHours(Math.floor(current / 60), current % 60, 0, 0);
        
        if (slotDt >= minAllowedTime) {
          const h = Math.floor(current / 60).toString().padStart(2, '0');
          const m = (current % 60).toString().padStart(2, '0');
          validSlots.push(`${h}:${m}`);
          break; 
        }
        current += interval;
      }
    } else {
      const anchorPoints = new Set<number>();

      const startSlotEnd = startDayMin + serviceDuration;
      const startIsFree = sortedBusy.every(b => !(startDayMin < b.end && startSlotEnd > b.start));
      if (startIsFree) anchorPoints.add(startDayMin);

      for (const busy of sortedBusy) {
        if (busy.end < endDayMin) anchorPoints.add(busy.end);
      }

      const sortedAnchors = Array.from(anchorPoints).sort((a, b) => a - b);

      for (const anchor of sortedAnchors) {
        const anchorSlotEnd = anchor + serviceDuration;
        const hasCollision = sortedBusy.some(b => anchor < b.end && anchorSlotEnd > b.start);
        if (hasCollision) continue;
        if (anchorSlotEnd > endDayMin) continue;

        const slotDt = new Date(selectedDate);
        slotDt.setUTCHours(Math.floor(anchor / 60), anchor % 60, 0, 0);
        if (slotDt < minAllowedTime) continue;

        const h = Math.floor(anchor / 60).toString().padStart(2, '0');
        const m = (anchor % 60).toString().padStart(2, '0');
        const timeString = `${h}:${m}`;
        if (!validSlots.includes(timeString)) validSlots.push(timeString);
      }
    }
  } else {
    let current = startDayMin;
    while (current + serviceDuration <= endDayMin) {
      const slotEnd = current + serviceDuration;
      let hasCollision = false;
      let jumpTo = current + interval;

      for (const busy of sortedBusy) {
        if (current < busy.end && slotEnd > busy.start) {
          hasCollision = true;
          jumpTo = busy.end;
          break;
        }
      }

      if (hasCollision) {
        current = jumpTo;
        continue;
      }

      const slotDt = new Date(selectedDate);
      slotDt.setUTCHours(Math.floor(current / 60), current % 60, 0, 0);
      if (slotDt < minAllowedTime) {
        current += interval;
        continue;
      }

      const h = Math.floor(current / 60).toString().padStart(2, '0');
      const m = (current % 60).toString().padStart(2, '0');
      validSlots.push(`${h}:${m}`);
      current += interval;
    }
  }

  return validSlots;
}

// TEST CASE
const busy = [
    { start: 480, end: 840 }, // 08:00 - 14:00 UTC
    { start: 660, end: 1020 } // 11:00 - 17:00 UTC
];

const result = generateSmartSlots({
    startStr: "08:00",
    endStr: "17:00",
    interval: 60,
    serviceDuration: 360,
    busyIntervals: busy,
    preventGaps: false, // CHANGED TO FALSE
    minAdvanceHours: 0,
    selectedDate: new Date("2026-07-04")
});

console.log("Slots encontrados (preventGaps: false):", result);
