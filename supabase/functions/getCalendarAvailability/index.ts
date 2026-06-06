import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'
import { parseWorkSchedule, hhmmToMin } from '../_shared/workSchedule.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

export interface BusyInterval {
  start: number;
  end: number;
}

/**
 * Ported from AvailabilityUtils.generateSmartSlots in Dart
 */
export function generateSmartSlots({
  startStr,
  endStr,
  interval,
  serviceDuration,
  busyIntervals,
  preventGaps,
  minAdvanceHours,
  selectedDate,
  breakInterval,
}: {
  startStr: string;
  endStr: string;
  interval: number;
  serviceDuration: number;
  busyIntervals: BusyInterval[];
  preventGaps: boolean;
  minAdvanceHours: number;
  selectedDate: Date;
  breakInterval?: BusyInterval;
}): string[] {
  const validSlots: string[] = [];

  const [startH, startM] = startStr.split(':').map(Number);
  const [endH, endM] = endStr.split(':').map(Number);
  const startDayMin = startH * 60 + startM;
  const endDayMin = endH * 60 + endM;

  if (interval <= 0) return [];

  // realBusy = agendamentos. allBusy = realBusy + pausa diária.
  const sortedBusy = [...busyIntervals].sort((a, b) => a.start - b.start);
  const allBusy: BusyInterval[] = breakInterval
    ? [...sortedBusy, breakInterval].sort((a, b) => a.start - b.start)
    : sortedBusy;
  const collidesAny = (s: number, e: number) =>
    allBusy.some(b => s < b.end && e > b.start);

  const now = new Date();
  const brazilNow = new Date(now.getTime() - (3 * 60 * 60 * 1000));
  const minAllowedTime = new Date(brazilNow.getTime() + minAdvanceHours * 60 * 60 * 1000);

  if (preventGaps) {
    const anchorPoints = new Set<number>();

    // Âncora: início do expediente (se livre, considerando pausa).
    if (!collidesAny(startDayMin, startDayMin + serviceDuration)) {
      anchorPoints.add(startDayMin);
    } else if (breakInterval &&
               startDayMin >= breakInterval.start &&
               startDayMin < breakInterval.end) {
      const after = breakInterval.end;
      if (!collidesAny(after, after + serviceDuration)) anchorPoints.add(after);
    }

    // Âncora: fim de cada agendamento real.
    for (const busy of sortedBusy) {
      if (busy.end < endDayMin) anchorPoints.add(busy.end);
    }

    // Âncora extra: fim da pausa só quando há agendamento antes dela.
    if (breakInterval && sortedBusy.length > 0 &&
        sortedBusy[0].start < breakInterval.start) {
      anchorPoints.add(breakInterval.end);
    }

    const sortedAnchors = Array.from(anchorPoints).sort((a, b) => a - b);
    for (const anchor of sortedAnchors) {
      const anchorEnd = anchor + serviceDuration;
      if (anchorEnd > endDayMin) continue;
      if (collidesAny(anchor, anchorEnd)) continue;

      const slotDt = new Date(selectedDate);
      slotDt.setUTCHours(Math.floor(anchor / 60), anchor % 60, 0, 0);
      if (slotDt < minAllowedTime) continue;

      const h = Math.floor(anchor / 60).toString().padStart(2, '0');
      const m = (anchor % 60).toString().padStart(2, '0');
      const timeString = `${h}:${m}`;
      if (!validSlots.includes(timeString)) validSlots.push(timeString);
    }
  } else {
    let current = startDayMin;
    while (current + serviceDuration <= endDayMin) {
      const slotEnd = current + serviceDuration;
      let hasCollision = false;
      let jumpTo = current + interval;

      for (const busy of allBusy) {
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

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { shop_id, service_id, month, professional_id, is_vip: is_vip_req } = await req.json()
    const is_vip = is_vip_req === true

    if (!shop_id || !service_id || !month) {
      return new Response(JSON.stringify({ error: 'Missing parameters' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 1. Fetch Shop and Service Data
    const [shopRes, serviceRes] = await Promise.all([
      supabaseClient.from('shops').select('config, configured_holidays, pending_holidays').eq('id', shop_id).single(),
      supabaseClient.from('services').select('duration_min').eq('id', service_id).single(),
    ])

    if (shopRes.error || serviceRes.error) {
      throw new Error('Failed to fetch shop or service data')
    }

    const shopConfig = shopRes.data.config || {}
    const serviceDuration = serviceRes.data.duration_min || 30
    const preventGaps = shopConfig.evitar_buracos_agenda ?? false
    const minAdvanceHours = shopConfig.limite_minimo_agendamento_horas ?? 0
    const intervalMinutes = shopConfig.intervalo_agenda_min ?? 30
    const autoBlockHolidays = shopConfig.auto_block_holidays ?? false
    const configuredHolidays = shopRes.data.configured_holidays || {}
    const pendingHolidays = shopRes.data.pending_holidays || []
    
    // Window logic (matching checkAvailability)
    const windowDays = shopConfig.janela_agendamento_dias || 30
    const vip_extra_days = is_vip ? (shopConfig.vip_extra_booking_days || 0) : 0
    
    const now = new Date()
    const brazilNow = new Date(now.getTime() - (3 * 60 * 60 * 1000))
    const maxDate = new Date(brazilNow.getTime() + (windowDays + vip_extra_days) * 24 * 60 * 60 * 1000)

    // 2. Fetch Professionals
    let profQuery = supabaseClient
      .from('employees')
      .select('id, name, work_start, work_end, start_time, end_time, work_days, work_schedule, services_ids')
      .eq('shop_id', shop_id)
    
    if (professional_id) {
      profQuery = profQuery.eq('id', professional_id)
    }

    const { data: professionals, error: profError } = await profQuery
    if (profError) throw profError

    const qualifiedProfs = professionals.filter(p => 
      (p.services_ids as string[])?.includes(service_id)
    )

    if (qualifiedProfs.length === 0) {
      return new Response(JSON.stringify({ availability: {} }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    // 3. Fetch Appointments for the month
    const [year, monthNum] = month.split('-').map(Number);
    const startOfMonth = new Date(Date.UTC(year, monthNum - 1, 1));
    const endOfMonth = new Date(Date.UTC(year, monthNum, 0, 23, 59, 59));

    const { data: appointments, error: apptError } = await supabaseClient
      .from('appointments')
      .select('professional_id, scheduled_at, duration_min, status')
      .eq('shop_id', shop_id)
      .gte('scheduled_at', startOfMonth.toISOString())
      .lte('scheduled_at', endOfMonth.toISOString())
      .not('status', 'in', '("cancelado","rejeitado","recusado","excluido")')

    if (apptError) throw apptError

    // Group appointments by professional and day
    const groupedByProfDay: Record<string, BusyInterval[]> = {}
    for (const appt of appointments) {
      const dt = new Date(appt.scheduled_at)
      const day = dt.getUTCDate()
      const profId = appt.professional_id
      const key = `${profId}_${day}`
      
      const startMin = dt.getUTCHours() * 60 + dt.getUTCMinutes()
      const dur = appt.duration_min || 30
      
      if (!groupedByProfDay[key]) groupedByProfDay[key] = []
      groupedByProfDay[key].push({ start: startMin, end: startMin + dur })
    }

    // 4. Calculate Daily Availability
    const availability: Record<string, boolean> = {}
    const numDays = endOfMonth.getUTCDate()

    for (let day = 1; day <= numDays; day++) {
      const date = new Date(Date.UTC(year, monthNum - 1, day))
      const isoDate = date.toISOString().split('T')[0]
      const weekday = date.getUTCDay() === 0 ? 7 : date.getUTCDay() // 1-7 (Mon-Sun)

      // Window check
      if (date > maxDate) {
        availability[isoDate] = false
        continue
      }

      // Global blocks
      if (configuredHolidays[isoDate] === 'fechado') {
        availability[isoDate] = false
        continue
      }
      if (autoBlockHolidays && pendingHolidays.includes(isoDate)) {
        availability[isoDate] = false
        continue
      }

      let dayHasSlot = false
      for (const prof of qualifiedProfs) {
        // Per-day schedule (com fallback legado)
        const schedule = parseWorkSchedule(prof as Record<string, unknown>)
        if (schedule.size === 0) continue
        const dayCfg = schedule.get(weekday)
        if (!dayCfg) continue

        // Custom scale
        if (configuredHolidays[isoDate] && typeof configuredHolidays[isoDate] === 'object') {
          const escala = configuredHolidays[isoDate].escala || []
          if (escala.length > 0 && !escala.includes(prof.id)) continue
        }

        const startStr = dayCfg.start
        const endStr = dayCfg.end
        const breakI = dayCfg.break
          ? { start: hhmmToMin(dayCfg.break.start), end: hhmmToMin(dayCfg.break.end) }
          : undefined
        const key = `${prof.id}_${day}`
        const busy = groupedByProfDay[key] || []

        const slots = generateSmartSlots({
          startStr,
          endStr,
          interval: intervalMinutes,
          serviceDuration,
          busyIntervals: busy,
          preventGaps,
          minAdvanceHours,
          selectedDate: date,
          breakInterval: breakI,
        })

        if (slots.length > 0) {
          dayHasSlot = true
          break
        }
      }

      availability[isoDate] = dayHasSlot
    }

    return new Response(JSON.stringify({ availability }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
