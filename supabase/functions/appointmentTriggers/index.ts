import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'
import { corsHeaders } from '../_shared/cors.ts'

// ==========================================
// Notification Helpers (WhatsApp/Resend)
// ==========================================

const sendWhatsApp = async (phone: string, templateName: string, vars: string[]) => {
  const token = Deno.env.get('WHATSAPP_TOKEN')
  const phoneId = Deno.env.get('WHATSAPP_PHONE_ID')
  
  if (!token || !phoneId) {
    console.warn('WhatsApp API variables missing.')
    return
  }

  // Sanitize phone number to international format (e.g. 5511999999999)
  const to = phone.replace(/\D/g, '')
  if (to.length < 10) return

  const payload = {
    messaging_product: 'whatsapp',
    to,
    type: 'template',
    template: {
      name: templateName,
      language: { code: 'pt_BR' },
      components: [
        {
          type: 'body',
          parameters: vars.map(text => ({ type: 'text', text }))
        }
      ]
    }
  }

  try {
    const res = await fetch(`https://graph.facebook.com/v17.0/${phoneId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    })
    const data = await res.json()
    console.log(`WhatsApp template ${templateName} sent to ${to}:`, data)
  } catch (err) {
    console.error('Error sending WhatsApp:', err)
  }
}

// ==========================================
// Calendar (ICS) Helpers
// ==========================================

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
    `SUMMARY:${params.summary.replace(/[\n\r]/g, '\\n')}`,
    `DESCRIPTION:${params.description.replace(/[\n\r]/g, '\\n')}`,
    `LOCATION:${params.location}`,
    `STATUS:${params.method === 'CANCEL' ? 'CANCELLED' : 'CONFIRMED'}`,
    'END:VEVENT',
    'END:VCALENDAR',
  ].join('\r\n')
}

function buildICSAttachment(appt: any, salonName: string, salonAddress: string, method: 'REQUEST' | 'CANCEL'): any {
  const startAt = appt.scheduled_at ? new Date(appt.scheduled_at) : null
  if (!startAt || isNaN(startAt.getTime())) return null
  const durationMin = appt.duration_min || 60
  const endAt = new Date(startAt.getTime() + durationMin * 60 * 1000)
  const uid = appt.id || `appt-${startAt.toISOString()}`
  const summary = `Agendamento – ${appt.service_name || 'Serviço'} no ${salonName}`
  const description = `Serviço: ${appt.service_name || ''}\\nProfissional: ${appt.professional_name || ''}\\nEndereço: ${salonAddress}`
  const icsContent = generateICS({ uid, start: startAt, end: endAt, summary, description, location: salonAddress, method })
  return {
    filename: method === 'CANCEL' ? 'cancelamento.ics' : 'agendamento.ics',
    content: textToBase64(icsContent),
    content_type: `text/calendar; charset=utf-8; method=${method}`,
  }
}

const sendEmail = async (to: string, subject: string, html: string, attachments?: any[]) => {
  const apiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('EMAIL_FROM') || 'MarkaAI <onboarding@resend.dev>'
  
  if (!apiKey) {
    console.error('[sendEmail] RESEND_API_KEY missing - check Supabase Secrets.')
    return
  }

  console.log(`[sendEmail] Tentando enviar email para: ${to} | Assunto: ${subject} | Remetente: ${from}`)

  try {
    const emailBody: any = { from, to: [to], subject, html }
    if (attachments && attachments.length > 0) emailBody.attachments = attachments
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(emailBody)
    })
    
    const data = await res.json()
    
    if (!res.ok) {
      console.error(`[sendEmail] ERRO na API do Resend ao enviar para ${to}:`, JSON.stringify(data, null, 2))
    } else {
      console.log(`[sendEmail] Sucesso! Email enviado para ${to}. ID: ${data.id}`)
    }
  } catch (err) {
    console.error('[sendEmail] Erro inesperado na requisição (fetch):', err)
  }
}


const APP_ICON = 'https://wismart-118c3.web.app/icons/Icon-192.png'

const sendOwnerPush = async (supabase: any, shopId: string, title: string, message: string, extraData?: any) => {
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) return

  try {
    const { data: shop } = await supabase
      .from('shops')
      .select('owner_id')
      .eq('id', shopId)
      .single()
    if (!shop?.owner_id) return

    await fetch(`${supabaseUrl}/functions/v1/sendPushNotification`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({
        user_id: shop.owner_id,
        title,
        message,
        data: { icon: APP_ICON, ...extraData },
      }),
    })
  } catch (e) {
    console.error('[sendOwnerPush] Erro:', e)
  }
}

async function sendOwnerFCM(supabaseAdmin: any, ownerId: string, title: string, body: string): Promise<void> {
  const { data: tokenData } = await supabaseAdmin
    .from('fcm_tokens')
    .select('token')
    .eq('user_id', ownerId)
    .single();

  if (!tokenData?.token) {
    console.log('[FCM_PUSH] Sem token FCM para owner:', ownerId);
    return;
  }

  const projectId = Deno.env.get('FCM_PROJECT_ID');
  const serviceAccountKey = Deno.env.get('FCM_SERVICE_ACCOUNT_KEY');
  
  if (!projectId || !serviceAccountKey) {
    console.error('[FCM_PUSH] Variáveis de ambiente FCM não configuradas. ProjectId:', projectId);
    return;
  }

  try {
    const accessToken = await getGoogleAccessToken(JSON.parse(serviceAccountKey));
    
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: tokenData.token,
            notification: { title, body },
            android: { priority: 'high' },
            apns: { payload: { aps: { sound: 'default', badge: 1 } } },
          }
        })
      }
    );
    
    if (!res.ok) {
      console.error('[FCM_PUSH] Erro ao enviar:', await res.text());
    } else {
      console.log('[FCM_PUSH] Notificação enviada para:', ownerId);
    }
  } catch(e) {
    console.error('[FCM_PUSH] exception:', e);
  }
}

async function getGoogleAccessToken(serviceAccount: any): Promise<string> {
  const { default: jwt } = await import('npm:jsonwebtoken@9');
  
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: serviceAccount.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  
  const token = jwt.sign(payload, serviceAccount.private_key, { algorithm: 'RS256' });
  
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${token}`,
  });
  
  const data = await res.json();
  return data.access_token;
}

// ==========================================
// Payload Builder
// ==========================================

async function buildPayloadFromAppointment(supabase: any, appt: any) {
  let clientName = appt.client_name || appt.client_nome || appt.nomeCliente || "Cliente";
  let clientEmail = appt.client_email || appt.emailCliente;
  let clientPhone = appt.client_phone || appt.clientPhone || appt.cliente_telefone;
  const serviceName = appt.service_name || appt.servico_nome || appt.servicoNome || "Serviço";
  const professionalName = appt.professional_name || appt.profissional_nome || "Profissional";
  
  let date = "";
  let time = "";
  
  if (appt.scheduled_at) {
    const d = new Date(appt.scheduled_at);
    date = `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}/${d.getFullYear()}`;
    time = `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}`;
  }

  if (!clientPhone && appt.client_id) {
    const { data: userData } = await supabase.from('users').select('phone, email').eq('id', appt.client_id).single()
    if (userData) {
      clientPhone = userData.phone || clientPhone
      clientEmail = clientEmail || userData.email
    }
  }

  let salonName = "Estabelecimento";
  let salonAddress = "";
  
  let salonLogo = ""
  let ownerEmail: string | null = null;
  let ownerIdForFCM: string | null = null;

  console.log('[buildPayload] shop_id:', appt.shop_id)

  if (appt.shop_id) {
    const { data: shopData, error: shopErr } = await supabase.from('shops').select('name, address, number, city, logo_url, owner_id').eq('id', appt.shop_id).maybeSingle()
    if (shopErr) console.error('[buildPayload] shops query error:', shopErr.message, '| shop_id:', appt.shop_id)
    
    // CORREÇÃO: usar shop_id diretamente como owner_id
    // pois os dois são o mesmo UUID neste sistema
    try {
      const ownerId = appt.shop_id; // shop_id === owner_id
      ownerIdForFCM = ownerId;
      
      const { data: { user }, error: userError } = 
        await supabase.auth.admin.getUserById(ownerId);
      
      ownerEmail = user?.email ?? null;
      
      console.log('[OWNER_EMAIL]', {
        ownerId,
        ownerEmail,
        source: 'auth.admin.getUserById via shop_id'
      });
      
      if (!ownerEmail) {
        console.error('[OWNER_EMAIL] Email não encontrado para ownerId:', ownerId);
      }
    } catch (e) {
      console.error('[OWNER_EMAIL] Exceção:', e);
    }
    
    console.log('[buildPayload] shopData:', JSON.stringify(shopData))
    if (shopData) {
      salonName = shopData.name || salonName
      salonLogo = shopData.logo_url || ""
      let addressStr = ""
      if (shopData.address) addressStr += shopData.address
      if (shopData.number) addressStr += `, ${shopData.number}`
      if (shopData.city) addressStr += ` - ${shopData.city}`
      salonAddress = addressStr
      // Fallback logo: method 1 — user linked via users.shop_id (dono com shop_id preenchido)
      if (!salonLogo) {
        const { data: ownerByShopId } = await supabase.from('users').select('photo_url').eq('shop_id', appt.shop_id).in('role', ['business', 'dono']).limit(1).maybeSingle()
        if (ownerByShopId?.photo_url) salonLogo = ownerByShopId.photo_url
      }
      // Fallback logo: method 2 — user linked via shops.owner_id (caso Go4Me e similares)
      if (shopData.owner_id && !salonLogo) {
        const { data: ownerById } = await supabase.from('users').select('photo_url').eq('id', shopData.owner_id).maybeSingle()
        if (ownerById?.photo_url) salonLogo = ownerById.photo_url
      }
    }
  }

  return {
    clientPhone,
    clientEmail,
    ownerEmail,
    ownerId: ownerIdForFCM,
    payload: {
      clientName,
      salonName,
      salonLogo,
      serviceName,
      date,
      time,
      professionalName,
      address: salonAddress
    }
  };
}

// ==========================================
// Email Templates
// ==========================================

const buildOwnerEmail = (data: any, eventType: string, eventColor: string) => `
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><title>${eventType} – MarkaAI</title></head>
<body style="margin:0;padding:0;background:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f0fb;">
    <tr><td align="center" style="padding:48px 20px;">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
        <tr><td align="center" style="background:linear-gradient(160deg,#3b0f8c 0%,#5c1fc4 60%,#7c3aed 100%);border-radius:16px 16px 0 0;padding:36px 48px 32px;">
          <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="140" style="display:block;margin:0 auto;max-height:42px;object-fit:contain;"/>
        </td></tr>
        <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
        <tr><td style="background:#fff;padding:40px 48px 32px;">
          <p style="margin:0 0 8px;color:${eventColor};font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">${eventType}</p>
          <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Olá, <strong>Proprietário</strong>!</p>
          <p style="margin:0 0 28px;color:#4b5563;font-size:15px;line-height:1.75;">
            Informamos uma atualização em um agendamento. Confira os detalhes abaixo:
          </p>
          <div style="background:#f9fafb;border-radius:14px;padding:28px;margin-bottom:32px;border:1px solid #ede9fe;">
            <p style="margin:0 0 16px;text-align:center;color:#1a1a2e;font-size:18px;font-weight:700;">Detalhes do Agendamento</p>
            <hr style="border:none;border-top:1px solid #ede9fe;margin:16px 0;"/>
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;width:36%;">Cliente</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.clientName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Serviço</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.serviceName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Profissional</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;">${data.payload.professionalName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Data</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.date}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Horário</td><td style="padding:6px 0;color:${eventColor};font-size:17px;font-weight:700;">${data.payload.time}</td></tr>
            </table>
          </div>
        </td></tr>
        <tr><td style="background:#faf8ff;border-top:1px solid #ede9fe;border-radius:0 0 16px 16px;padding:20px 48px;text-align:center;">
          <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">© 2026 MarkaAI · Email automático, não responda.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;

const buildConfirmationEmail = (data: any) => `
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><title>Agendamento Confirmado – MarkaAI</title></head>
<body style="margin:0;padding:0;background:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f0fb;">
    <tr><td align="center" style="padding:48px 20px;">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
        <tr><td align="center" style="background:linear-gradient(160deg,#3b0f8c 0%,#5c1fc4 60%,#7c3aed 100%);border-radius:16px 16px 0 0;padding:36px 48px 32px;">
          <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="140" style="display:block;margin:0 auto;max-height:42px;object-fit:contain;"/>
        </td></tr>
        <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
        <tr><td style="background:#fff;padding:40px 48px 32px;">
          <p style="margin:0 0 8px;color:#16a34a;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">✅ Agendamento Confirmado</p>
          <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Olá, <strong>${data.payload.clientName}</strong>!</p>
          <p style="margin:0 0 28px;color:#4b5563;font-size:15px;line-height:1.75;">
            Informamos que seu agendamento foi <strong style="color:#16a34a;">confirmado</strong>. Confira os detalhes abaixo:
          </p>
          <div style="background:#f9fafb;border-radius:14px;padding:28px;margin-bottom:32px;border:1px solid #ede9fe;">
            ${data.payload.salonLogo ? `<div style="text-align:center;margin-bottom:16px;"><img src="${data.payload.salonLogo}" alt="${data.payload.salonName}" width="72" height="72" style="display:block;margin:0 auto;border-radius:12px;object-fit:cover;border:2px solid #ede9fe;"/></div>` : ''}
            <p style="margin:0 0 16px;text-align:center;color:#1a1a2e;font-size:18px;font-weight:700;">${data.payload.salonName}</p>
            <hr style="border:none;border-top:1px solid #ede9fe;margin:16px 0;"/>
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;width:36%;">Serviço</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.serviceName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Profissional</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;">${data.payload.professionalName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Data</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.date}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Horário</td><td style="padding:6px 0;color:#5c1fc4;font-size:17px;font-weight:700;">${data.payload.time}</td></tr>
              ${data.payload.address ? `<tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Endereço</td><td style="padding:6px 0;color:#1a1a2e;font-size:14px;">${data.payload.address}</td></tr>` : ''}
            </table>
          </div>
          <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding-bottom:32px;">
            <a href="https://markaai.com.br" style="display:inline-block;background:linear-gradient(135deg,#5c1fc4,#7c3aed);color:#fff;text-decoration:none;font-size:15px;font-weight:600;padding:16px 44px;border-radius:10px;box-shadow:0 6px 20px rgba(92,31,196,0.3);">Agendar novo horário</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="background:#faf8ff;border-top:1px solid #ede9fe;border-radius:0 0 16px 16px;padding:20px 48px;text-align:center;">
          <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">© 2026 MarkaAI · Email automático, não responda.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;

const buildCancellationEmail = (data: any) => `
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><title>Agendamento Cancelado – MarkaAI</title></head>
<body style="margin:0;padding:0;background:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f0fb;">
    <tr><td align="center" style="padding:48px 20px;">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
        <tr><td align="center" style="background:linear-gradient(160deg,#3b0f8c 0%,#5c1fc4 60%,#7c3aed 100%);border-radius:16px 16px 0 0;padding:36px 48px 32px;">
          <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="140" style="display:block;margin:0 auto;max-height:42px;object-fit:contain;"/>
        </td></tr>
        <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
        <tr><td style="background:#fff;padding:40px 48px 32px;">
          <p style="margin:0 0 8px;color:#ef4444;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">❌ Agendamento Cancelado</p>
          <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Olá, <strong>${data.payload.clientName}</strong>!</p>
          <p style="margin:0 0 28px;color:#4b5563;font-size:15px;line-height:1.75;">
            Informamos que seu agendamento foi <strong style="color:#ef4444;">cancelado</strong>. Veja os detalhes abaixo:
          </p>
          <div style="background:#fef2f2;border-radius:14px;padding:28px;margin-bottom:32px;border:1px solid #fee2e2;">
            ${data.payload.salonLogo ? `<div style="text-align:center;margin-bottom:16px;"><img src="${data.payload.salonLogo}" alt="${data.payload.salonName}" width="72" height="72" style="display:block;margin:0 auto;border-radius:12px;object-fit:cover;border:2px solid #fee2e2;"/></div>` : ''}
            <p style="margin:0 0 16px;text-align:center;color:#1a1a2e;font-size:18px;font-weight:700;">${data.payload.salonName}</p>
            <hr style="border:none;border-top:1px solid #fee2e2;margin:16px 0;"/>
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr><td style="padding:6px 0;color:#9ca3af;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;width:36%;">Serviço</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.serviceName}</td></tr>
              <tr><td style="padding:6px 0;color:#9ca3af;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Profissional</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;">${data.payload.professionalName}</td></tr>
              <tr><td style="padding:6px 0;color:#9ca3af;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Data</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.date}</td></tr>
              <tr><td style="padding:6px 0;color:#9ca3af;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Horário</td><td style="padding:6px 0;color:#ef4444;font-size:17px;font-weight:700;">${data.payload.time}</td></tr>
            </table>
          </div>
          <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding-bottom:32px;">
            <a href="https://markaai.com.br" style="display:inline-block;background:linear-gradient(135deg,#5c1fc4,#7c3aed);color:#fff;text-decoration:none;font-size:15px;font-weight:600;padding:16px 44px;border-radius:10px;box-shadow:0 6px 20px rgba(92,31,196,0.3);">Agendar novo horário</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="background:#faf8ff;border-top:1px solid #ede9fe;border-radius:0 0 16px 16px;padding:20px 48px;text-align:center;">
          <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">© 2026 MarkaAI · Email automático, não responda.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;

const buildReschedulingEmail = (data: any) => `
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><title>Agendamento Atualizado – MarkaAI</title></head>
<body style="margin:0;padding:0;background:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#f4f0fb;">
    <tr><td align="center" style="padding:48px 20px;">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
        <tr><td align="center" style="background:linear-gradient(160deg,#3b0f8c 0%,#5c1fc4 60%,#7c3aed 100%);border-radius:16px 16px 0 0;padding:36px 48px 32px;">
          <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="140" style="display:block;margin:0 auto;max-height:42px;object-fit:contain;"/>
        </td></tr>
        <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
        <tr><td style="background:#fff;padding:40px 48px 32px;">
          <p style="margin:0 0 8px;color:#7c3aed;font-size:13px;font-weight:700;text-transform:uppercase;letter-spacing:1px;">🔄 Agendamento Atualizado</p>
          <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Olá, <strong>${data.payload.clientName}</strong>!</p>
          <p style="margin:0 0 28px;color:#4b5563;font-size:15px;line-height:1.75;">
            Informamos que seu agendamento foi <strong style="color:#7c3aed;">atualizado para um novo horário</strong>. Confira os novos detalhes:
          </p>
          <div style="background:#f9fafb;border-radius:14px;padding:28px;margin-bottom:32px;border:2px solid #7c3aed;">
            ${data.payload.salonLogo ? `<div style="text-align:center;margin-bottom:16px;"><img src="${data.payload.salonLogo}" alt="${data.payload.salonName}" width="72" height="72" style="display:block;margin:0 auto;border-radius:12px;object-fit:cover;border:2px solid #ede9fe;"/></div>` : ''}
            <p style="margin:0 0 16px;text-align:center;color:#1a1a2e;font-size:18px;font-weight:700;">${data.payload.salonName}</p>
            <hr style="border:none;border-top:1px solid #ede9fe;margin:16px 0;"/>
            <table width="100%" cellpadding="0" cellspacing="0">
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;width:36%;">Serviço</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.serviceName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Profissional</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;">${data.payload.professionalName}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Data</td><td style="padding:6px 0;color:#1a1a2e;font-size:15px;font-weight:600;">${data.payload.date}</td></tr>
              <tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Horário</td><td style="padding:6px 0;color:#7c3aed;font-size:17px;font-weight:700;">${data.payload.time}</td></tr>
              ${data.payload.address ? `<tr><td style="padding:6px 0;color:#6b7280;font-size:13px;font-weight:600;text-transform:uppercase;letter-spacing:.4px;">Endereço</td><td style="padding:6px 0;color:#1a1a2e;font-size:14px;">${data.payload.address}</td></tr>` : ''}
            </table>
          </div>
          <table width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding-bottom:32px;">
            <a href="https://markaai.com.br" style="display:inline-block;background:linear-gradient(135deg,#5c1fc4,#7c3aed);color:#fff;text-decoration:none;font-size:15px;font-weight:600;padding:16px 44px;border-radius:10px;box-shadow:0 6px 20px rgba(92,31,196,0.3);">Agendar novo horário</a>
          </td></tr></table>
        </td></tr>
        <tr><td style="background:#faf8ff;border-top:1px solid #ede9fe;border-radius:0 0 16px 16px;padding:20px 48px;text-align:center;">
          <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">© 2026 MarkaAI · Email automático, não responda.</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;

// ==========================================
// Webhook Handler
// ==========================================

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const payload = await req.json()
    const supabase = createSupabaseAdminClient()

    // Handle Database Webhook
    if (payload.type === 'INSERT') {
      const appt = payload.record
      
      // Só envia notificação de confirmação para status finais.
      // Ignora 'pendente', 'pendente_verificacao' e outros status intermediários
      // para evitar notificar o cliente antes do pagamento ser confirmado.
      const notifiableStatuses = ['agendado', 'confirmado']
      const currentStatus = (appt.status || '').toLowerCase()
      if (!notifiableStatuses.includes(currentStatus)) {
        console.log(`Skipping notification for appointment ${appt.id}: status="${currentStatus}" is not notifiable`)
        return new Response(JSON.stringify({ skipped: true, reason: `status ${currentStatus} not notifiable` }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      const data = await buildPayloadFromAppointment(supabase, appt)
      
      if (!data.clientPhone && !data.clientEmail) {
        console.warn(`[INSERT] Sem informações de contato para o agendamento ${appt.id}. Registros presentes:`, JSON.stringify({ phone: data.clientPhone, email: data.clientEmail }))
        return new Response('No contact info', { status: 200 })
      }

      const emailHtml = buildConfirmationEmail(data)
      const icsAttachment = buildICSAttachment(appt, data.payload.salonName, data.payload.address, 'REQUEST')
      const attachments = icsAttachment ? [icsAttachment] : []

      console.log(`[INSERT] Disparando notificações para agendamento ${appt.id}...`)
      console.log('[OWNER_EMAIL_DEBUG]', {
        ownerId: appt.shop_id,
        ownerEmail: data.ownerEmail,
        clientEmail: data.clientEmail,
        eventType: 'INSERT'
      });
      const results = await Promise.allSettled([
        data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_confirmation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time, data.payload.serviceName]) : Promise.resolve(),
        data.clientEmail ? sendEmail(data.clientEmail, '✅ Agendamento Confirmado — MarkaAI', emailHtml, attachments) : Promise.resolve(),
        data.ownerEmail ? sendEmail(data.ownerEmail, '✅ Novo Agendamento — MarkaAI', buildOwnerEmail(data, '✅ Novo Agendamento', '#16a34a')) : Promise.resolve(),
        appt.shop_id ? sendOwnerPush(supabase, appt.shop_id, '📅 Novo Agendamento', `${data.payload.clientName} — ${data.payload.serviceName} às ${data.payload.time} (${data.payload.date})`) : Promise.resolve(),
        data.ownerId ? sendOwnerFCM(supabase, data.ownerId, '📅 Novo Agendamento', `${data.payload.clientName} — ${data.payload.serviceName} às ${data.payload.time} (${data.payload.date})`) : Promise.resolve(),
      ])

      results.forEach((r, i) => {
        if (r.status === 'rejected') {
          console.error(`[PROMISE_${i}_FAILED]`, r.reason);
        }
      });

    } 
    else if (payload.type === 'UPDATE') {
      const before = payload.old_record
      const after = payload.record
      const notifiableStatuses = ['agendado', 'confirmado']
      const statusChanged = before.status !== after.status
      const dateChanged = before.scheduled_at !== after.scheduled_at
      const currentStatus = (after.status || '').toLowerCase()

      // 1. Mudança para Confirmação / Agendamento (ex: de 'pendente' para 'confirmado')
      if (statusChanged && notifiableStatuses.includes(currentStatus) && !notifiableStatuses.includes((before.status || '').toLowerCase())) {
        console.log(`[UPDATE] Status alterado para "${currentStatus}" no agendamento ${after.id}. Enviando email de confirmação...`)
        const data = await buildPayloadFromAppointment(supabase, after)
        const emailHtml = buildConfirmationEmail(data)
        const icsAtt = buildICSAttachment(after, data.payload.salonName, data.payload.address, 'REQUEST')
        const atts = icsAtt ? [icsAtt] : []
        
        console.log('[OWNER_EMAIL_DEBUG]', {
          ownerId: after.shop_id,
          ownerEmail: data.ownerEmail,
          clientEmail: data.clientEmail,
          eventType: 'UPDATE_CONFIRMED'
        });
        
        const results = await Promise.allSettled([
          data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_confirmation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time, data.payload.serviceName]) : Promise.resolve(),
          data.clientEmail ? sendEmail(data.clientEmail, '✅ Agendamento Confirmado — MarkaAI', emailHtml, atts) : Promise.resolve(),
          data.ownerEmail ? sendEmail(data.ownerEmail, '✅ Agendamento Confirmado — MarkaAI', buildOwnerEmail(data, '✅ Agendamento Confirmado', '#16a34a')) : Promise.resolve(),
          after.shop_id ? sendOwnerPush(supabase, after.shop_id, '✅ Agendamento Confirmado', `${data.payload.clientName} — ${data.payload.serviceName} às ${data.payload.time} (${data.payload.date})`) : Promise.resolve(),
          data.ownerId ? sendOwnerFCM(supabase, data.ownerId, '✅ Agendamento Confirmado', `${data.payload.clientName} — ${data.payload.serviceName} às ${data.payload.time} (${data.payload.date})`) : Promise.resolve(),
        ])
        
        results.forEach((r, i) => {
          if (r.status === 'rejected') {
            console.error(`[PROMISE_${i}_FAILED]`, r.reason);
          }
        });
      }
      // 2. Mudança para Cancelamento
      else if (statusChanged && currentStatus === 'cancelado') {
        console.log(`[UPDATE] Status alterado para "cancelado" no agendamento ${after.id}. Enviando email de cancelamento...`)
        const data = await buildPayloadFromAppointment(supabase, after)
        const emailHtml = buildCancellationEmail(data)
        const icsAtt = buildICSAttachment(after, data.payload.salonName, data.payload.address, 'CANCEL')
        const atts = icsAtt ? [icsAtt] : []
        
        console.log('[OWNER_EMAIL_DEBUG]', {
          ownerId: after.shop_id,
          ownerEmail: data.ownerEmail,
          clientEmail: data.clientEmail,
          eventType: 'UPDATE_CANCELLED'
        });
        
        const results = await Promise.allSettled([
          data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_cancellation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time]) : Promise.resolve(),
          data.clientEmail ? sendEmail(data.clientEmail, '❌ Agendamento Cancelado — MarkaAI', emailHtml, atts) : Promise.resolve(),
          data.ownerEmail ? sendEmail(data.ownerEmail, '❌ Agendamento Cancelado — MarkaAI', buildOwnerEmail(data, '❌ Agendamento Cancelado', '#ef4444')) : Promise.resolve(),
          after.shop_id ? sendOwnerPush(supabase, after.shop_id, '❌ Agendamento Cancelado', `${data.payload.clientName} cancelou — ${data.payload.serviceName} de ${data.payload.date} às ${data.payload.time}`) : Promise.resolve(),
          data.ownerId ? sendOwnerFCM(supabase, data.ownerId, '❌ Agendamento Cancelado', `${data.payload.clientName} cancelou — ${data.payload.serviceName} de ${data.payload.date} às ${data.payload.time}`) : Promise.resolve(),
        ])
        
        results.forEach((r, i) => {
          if (r.status === 'rejected') {
            console.error(`[PROMISE_${i}_FAILED]`, r.reason);
          }
        });
      }
      // 3. Reagendamento (Mudança de Data/Hora mantendo status confirmado)
      else if (dateChanged && notifiableStatuses.includes(currentStatus)) {
        console.log(`[UPDATE] Data/Hora alterada no agendamento ${after.id}. Enviando email de reagendamento...`)
        const data = await buildPayloadFromAppointment(supabase, after)
        const emailHtml = buildReschedulingEmail(data)
        const icsAtt = buildICSAttachment(after, data.payload.salonName, data.payload.address, 'REQUEST')
        const atts = icsAtt ? [icsAtt] : []
        
        console.log('[OWNER_EMAIL_DEBUG]', {
          ownerId: after.shop_id,
          ownerEmail: data.ownerEmail,
          clientEmail: data.clientEmail,
          eventType: 'UPDATE_RESCHEDULED'
        });
        
        const results = await Promise.allSettled([
          data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_confirmation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time, data.payload.serviceName]) : Promise.resolve(),
          data.clientEmail ? sendEmail(data.clientEmail, '🔄 Agendamento Atualizado — MarkaAI', emailHtml, atts) : Promise.resolve(),
          data.ownerEmail ? sendEmail(data.ownerEmail, '🔄 Agendamento Atualizado — MarkaAI', buildOwnerEmail(data, '🔄 Agendamento Atualizado', '#7c3aed')) : Promise.resolve(),
          after.shop_id ? sendOwnerPush(supabase, after.shop_id, '🔄 Reagendamento', `${data.payload.clientName} reagendou — ${data.payload.serviceName} para ${data.payload.date} às ${data.payload.time}`) : Promise.resolve(),
          data.ownerId ? sendOwnerFCM(supabase, data.ownerId, '🔄 Reagendamento', `${data.payload.clientName} reagendou — ${data.payload.serviceName} para ${data.payload.date} às ${data.payload.time}`) : Promise.resolve(),
        ])
        
        results.forEach((r, i) => {
          if (r.status === 'rejected') {
            console.error(`[PROMISE_${i}_FAILED]`, r.reason);
          }
        });
      }
    }


    return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    console.error('Error in appointmentTriggers:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
