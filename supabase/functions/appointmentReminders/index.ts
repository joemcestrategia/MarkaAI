import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'
import { corsHeaders } from '../_shared/cors.ts'

// ==========================================
// Helpers
// ==========================================

const sendEmail = async (to: string, subject: string, html: string, attachments?: any[]) => {
  const apiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('EMAIL_FROM') || 'MarkaAI <onboarding@resend.dev>'
  if (!apiKey) {
    console.error('[sendEmail] RESEND_API_KEY ausente.')
    return
  }
  const body: any = { from, to: [to], subject, html }
  if (attachments && attachments.length > 0) body.attachments = attachments
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    const data = await res.json()
    if (!res.ok) {
      console.error(`[sendEmail] Resend error para ${to}:`, JSON.stringify(data))
    } else {
      console.log(`[sendEmail] Enviado para ${to}. ID: ${data.id}`)
    }
  } catch (err) {
    console.error('[sendEmail] Fetch error:', err)
  }
}

function textToBase64(text: string): string {
  const bytes = new TextEncoder().encode(text)
  let binary = ''
  bytes.forEach((b) => (binary += String.fromCharCode(b)))
  return btoa(binary)
}

function formatIsoDate(d: Date): string {
  return d.toISOString().replace(/[-:.]/g, '').slice(0, 15) + 'Z'
}

function generateICS(params: {
  uid: string
  start: Date
  end: Date
  summary: string
  description: string
  location: string
  method: 'REQUEST' | 'CANCEL'
}): string {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//MarkaAI//PT',
    `METHOD:${params.method}`,
    'BEGIN:VEVENT',
    `UID:${params.uid}@markaai.com.br`,
    `DTSTAMP:${formatIsoDate(new Date())}`,
    `DTSTART:${formatIsoDate(params.start)}`,
    `DTEND:${formatIsoDate(params.end)}`,
    `SUMMARY:${params.summary.replace(/\n/g, '\\n')}`,
    `DESCRIPTION:${params.description.replace(/\n/g, '\\n')}`,
    `LOCATION:${params.location}`,
    `STATUS:${params.method === 'CANCEL' ? 'CANCELLED' : 'CONFIRMED'}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n')
}

// ==========================================
// Email Templates
// ==========================================

const build48hReminderEmail = (data: {
  clientName: string
  salonName: string
  salonLogo: string
  serviceName: string
  professionalName: string
  date: string
  time: string
  address: string
}) => `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/></head>
<body style="margin:0;padding:0;background:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f0fb;">
    <tr><td align="center" style="padding:48px 20px;">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
        <tr><td align="center" style="background:linear-gradient(160deg,#3b0f8c 0%,#5c1fc4 60%,#7c3aed 100%);border-radius:16px 16px 0 0;padding:36px 48px 32px;">
          <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="140" style="display:block;margin:0 auto;max-height:42px;object-fit:contain;"/>
        </td></tr>
        <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
        <tr><td style="background:#fff;padding:40px 48px 32px;">
          <p style="margin:0 0 8px;color:#5c1fc4;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">⏰ Lembrete — 2 dias antes</p>
          <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Olá, <strong>${data.clientName}</strong>!</p>
          <p style="margin:0 0 28px;color:#4b5563;font-size:15px;line-height:1.75;">
            Informamos que seu agendamento está <strong style="color:#5c1fc4;">confirmado</strong> e acontece em <strong>2 dias</strong>. Confira os detalhes:
          </p>
          <div style="background:#f9fafb;border-radius:14px;padding:28px;margin-bottom:32px;border:1px solid #ede9fe;">
            ${data.salonLogo ? `<div style="text-align:center;margin-bottom:16px;"><img src="${data.salonLogo}" alt="${data.salonName}" width="72" height="72" style="display:block;margin:0 auto;border-radius:12px;object-fit:cover;border:2px solid #ede9fe;"/></div>` : ''}
            <p style="margin:0 0 16px;text-align:center;color:#1a1a2e;font-size:18px;font-weight:700;">${data.salonName}</p>
            <hr style="border:none;border-top:1px solid #ede9fe;margin:16px 0;"/>
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;width:36%;">Serviço</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.serviceName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Profissional</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;">${data.professionalName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Data</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.date}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Horário</td><td style="padding:6px 0;color:#5c1fc4;font-size:17px;font-weight:700;">${data.time}</td></tr>
              ${data.address ? `<tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Endereço</td><td style="padding:6px 0;color:#1a1a2e;font-size:14px;">${data.address}</td></tr>` : ''}
            </table>
          </div>
          <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding-bottom:32px;">
            <a href="https://markaai.com.br" style="display:inline-block;background:linear-gradient(135deg,#5c1fc4,#7c3aed);color:#fff;text-decoration:none;font-size:15px;font-weight:600;padding:16px 44px;border-radius:10px;box-shadow:0 6px 20px rgba(92,31,196,0.3);">Agendar novo horário</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="background:#faf8ff;border-top:1px solid #ede9fe;border-radius:0 0 16px 16px;padding:20px 48px;text-align:center;">
          <p style="margin:0;color:#c4b5fd;font-size:11px;">© 2026 MarkaAI · Email automático, não responda.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`

const build1hReminderEmail = (data: {
  clientName: string
  salonName: string
  salonLogo: string
  serviceName: string
  professionalName: string
  date: string
  time: string
  address: string
}) => `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/></head>
<body style="margin:0;padding:0;background:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f0fb;">
    <tr><td align="center" style="padding:48px 20px;">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
        <tr><td align="center" style="background:linear-gradient(160deg,#3b0f8c 0%,#5c1fc4 60%,#7c3aed 100%);border-radius:16px 16px 0 0;padding:36px 48px 32px;">
          <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="140" style="display:block;margin:0 auto;max-height:42px;object-fit:contain;"/>
        </td></tr>
        <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
        <tr><td style="background:#fff;padding:40px 48px 32px;">
          <p style="margin:0 0 8px;color:#d97706;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">🔔 Lembrete — 1 hora antes</p>
          <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Olá, <strong>${data.clientName}</strong>!</p>
          <p style="margin:0 0 28px;color:#4b5563;font-size:15px;line-height:1.75;">
            Informamos que seu agendamento está <strong style="color:#d97706;">confirmado</strong> e começa em <strong>1 hora</strong>. Já está pronto?
          </p>
          <div style="background:#fffbeb;border-radius:14px;padding:28px;margin-bottom:32px;border:2px solid #fde68a;">
            ${data.salonLogo ? `<div style="text-align:center;margin-bottom:16px;"><img src="${data.salonLogo}" alt="${data.salonName}" width="72" height="72" style="display:block;margin:0 auto;border-radius:12px;object-fit:cover;border:2px solid #fde68a;"/></div>` : ''}
            <p style="margin:0 0 16px;text-align:center;color:#1a1a2e;font-size:18px;font-weight:700;">${data.salonName}</p>
            <hr style="border:none;border-top:1px solid #fde68a;margin:16px 0;"/>
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr><td style="padding:6px 0;color:#92400e;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;width:36%;">Serviço</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.serviceName}</td></tr>
              <tr><td style="padding:6px 0;color:#92400e;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Profissional</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;">${data.professionalName}</td></tr>
              <tr><td style="padding:6px 0;color:#92400e;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Data</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.date}</td></tr>
              <tr><td style="padding:6px 0;color:#92400e;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Horário</td><td style="padding:6px 0;color:#d97706;font-size:20px;font-weight:700;">${data.time}</td></tr>
              ${data.address ? `<tr><td style="padding:6px 0;color:#92400e;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Endereço</td><td style="padding:6px 0;color:#1a1a2e;font-size:14px;">${data.address}</td></tr>` : ''}
            </table>
          </div>
          <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding-bottom:32px;">
            <a href="https://markaai.com.br" style="display:inline-block;background:linear-gradient(135deg,#5c1fc4,#7c3aed);color:#fff;text-decoration:none;font-size:15px;font-weight:600;padding:16px 44px;border-radius:10px;box-shadow:0 6px 20px rgba(92,31,196,0.3);">Agendar novo horário</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="background:#faf8ff;border-top:1px solid #ede9fe;border-radius:0 0 16px 16px;padding:20px 48px;text-align:center;">
          <p style="margin:0;color:#c4b5fd;font-size:11px;">© 2026 MarkaAI · Email automático, não responda.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`

// ==========================================
// Main Handler
// ==========================================

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseAdminClient()
    const now = new Date()

    // ── 1. Lembrete 48h ──────────────────────────────────────────────────────
    // Janela: scheduled_at entre agora+47h e agora+49h
    const window48hStart = new Date(now.getTime() + 47 * 60 * 60 * 1000)
    const window48hEnd   = new Date(now.getTime() + 49 * 60 * 60 * 1000)

    const { data: appts48h, error: err48h } = await supabase
      .from('appointments')
      .select('*, client_id, shop_id')
      .in('status', ['agendado', 'confirmado'])
      .eq('reminder_48h_sent', false)
      .gte('scheduled_at', window48hStart.toISOString())
      .lte('scheduled_at', window48hEnd.toISOString())

    if (err48h) console.error('[48h] Query error:', err48h)
    console.log(`[48h] ${(appts48h || []).length} agendamento(s) encontrado(s)`)

    for (const appt of appts48h || []) {
      await processReminder(supabase, appt, '48h')
    }

    // ── 2. Lembrete 1h ───────────────────────────────────────────────────────
    // Janela: scheduled_at entre agora+55min e agora+65min
    const window1hStart = new Date(now.getTime() + 55 * 60 * 1000)
    const window1hEnd   = new Date(now.getTime() + 65 * 60 * 1000)

    const { data: appts1h, error: err1h } = await supabase
      .from('appointments')
      .select('*, client_id, shop_id')
      .in('status', ['agendado', 'confirmado'])
      .eq('reminder_1h_sent', false)
      .gte('scheduled_at', window1hStart.toISOString())
      .lte('scheduled_at', window1hEnd.toISOString())

    if (err1h) console.error('[1h] Query error:', err1h)
    console.log(`[1h] ${(appts1h || []).length} agendamento(s) encontrado(s)`)

    for (const appt of appts1h || []) {
      await processReminder(supabase, appt, '1h')
    }

    return new Response(
      JSON.stringify({ success: true, processed48h: (appts48h || []).length, processed1h: (appts1h || []).length }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (err) {
    console.error('[appointmentReminders] Erro inesperado:', err)
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})

// ==========================================
// Process individual reminder
// ==========================================

async function processReminder(supabase: any, appt: any, type: '48h' | '1h') {
  try {
    // Resolve dados do cliente
    let clientEmail = appt.client_email
    let clientName  = appt.client_name || 'Cliente'

    if (!clientEmail && appt.client_id) {
      const { data: user } = await supabase
        .from('users')
        .select('email, name')
        .eq('id', appt.client_id)
        .maybeSingle()
      if (user) {
        clientEmail = user.email
        if (!clientName || clientName === 'Cliente') clientName = user.name || clientName
      }
    }

    if (!clientEmail) {
      console.warn(`[${type}] Sem email para agendamento ${appt.id}`)
      return
    }

    // Resolve dados da loja
    let salonName    = appt.salonName || 'Estabelecimento'
    let salonAddress = ''

    let salonLogo = ''

    if (appt.shop_id) {
      const { data: shop, error: shopErr } = await supabase
        .from('shops')
        .select('name, address, number, city, logo_url, owner_id')
        .eq('id', appt.shop_id)
        .maybeSingle()
      if (shopErr) console.error('[processReminder] shops query error:', shopErr.message, '| shop_id:', appt.shop_id)
      if (shop) {
        salonName = shop.name || salonName
        salonLogo = shop.logo_url || ''
        const parts = [shop.address, shop.number ? `nº ${shop.number}` : null, shop.city].filter(Boolean)
        salonAddress = parts.join(', ')
        // Fallback logo: method 1 — user linked via users.shop_id
        if (!salonLogo) {
          const { data: ownerByShopId } = await supabase.from('users').select('photo_url').eq('shop_id', appt.shop_id).in('role', ['business', 'dono']).limit(1).maybeSingle()
          if (ownerByShopId?.photo_url) salonLogo = ownerByShopId.photo_url
        }
        // Fallback logo: method 2 — user linked via shops.owner_id
        if (!salonLogo && shop.owner_id) {
          const { data: ownerById } = await supabase.from('users').select('photo_url').eq('id', shop.owner_id).maybeSingle()
          if (ownerById?.photo_url) salonLogo = ownerById.photo_url
        }
      }
    }

    const scheduledAt = new Date(appt.scheduled_at)

    // O banco armazena o horário local sem offset (tratado como UTC pelo Postgres).
    // Para exibir o horário correto no e-mail, lemos os componentes UTC diretamente
    // sem aplicar nenhuma conversão de fuso — evita a subtração indevida de 3h (BRT).
    const day   = scheduledAt.getUTCDate().toString().padStart(2, '0')
    const month = (scheduledAt.getUTCMonth() + 1).toString().padStart(2, '0')
    const year  = scheduledAt.getUTCFullYear().toString()
    const hour  = scheduledAt.getUTCHours().toString().padStart(2, '0')
    const min   = scheduledAt.getUTCMinutes().toString().padStart(2, '0')
    const dateStr = `${day}/${month}/${year}`
    const timeStr = `${hour}:${min}`

    const durationMin = appt.duration_min || 60
    const endAt = new Date(scheduledAt.getTime() + durationMin * 60 * 1000)

    // Gera ICS como anexo
    const icsContent = generateICS({
      uid: appt.id || `${appt.shop_id}-${appt.client_id}-${appt.scheduled_at}`,
      start: scheduledAt,
      end: endAt,
      summary: `Agendamento – ${appt.service_name || 'Serviço'} no ${salonName}`,
      description: `Serviço: ${appt.service_name || 'Serviço'}\\nProfissional: ${appt.professional_name || 'Profissional'}\\nEndereço: ${salonAddress}`,
      location: salonAddress,
      method: 'REQUEST',
    })

    const attachments = [{
      filename: 'agendamento.ics',
      content: textToBase64(icsContent),
      content_type: 'text/calendar; charset=utf-8; method=REQUEST',
    }]

    const templateData = {
      clientName,
      salonName,
      salonLogo,
      serviceName:      appt.service_name      || 'Serviço',
      professionalName: appt.professional_name || 'Profissional',
      date:  dateStr,
      time:  timeStr,
      address: salonAddress,
    }

    let subject: string
    let html: string

    if (type === '48h') {
      subject = `⏰ Lembrete: Seu agendamento em ${salonName} é em 2 dias`
      html = build48hReminderEmail(templateData)
    } else {
      subject = `🔔 Lembrete: Seu horário começa em 1 hora — ${salonName}`
      html = build1hReminderEmail(templateData)
    }

    await sendEmail(clientEmail, subject, html, attachments)

    // Marca como enviado
    const updateField = type === '48h' ? 'reminder_48h_sent' : 'reminder_1h_sent'
    await supabase
      .from('appointments')
      .update({ [updateField]: true })
      .eq('id', appt.id)

    console.log(`[${type}] Lembrete enviado para agendamento ${appt.id}`)
  } catch (err) {
    console.error(`[${type}] Erro ao processar agendamento ${appt?.id}:`, err)
  }
}
