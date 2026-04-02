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

const sendEmail = async (to: string, subject: string, html: string) => {
  const apiKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('EMAIL_FROM') || 'MarkaAI <no-reply@markaai.com.br>'
  
  if (!apiKey) {
    console.error('[sendEmail] RESEND_API_KEY missing - check Supabase Secrets.')
    return
  }

  console.log(`[sendEmail] Tentando enviar email para: ${to} | Assunto: ${subject} | Remetente: ${from}`)

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ 
        from, 
        to: [to], // Resend aceita string ou array, mas array é mais robusto
        subject, 
        html 
      })
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

  let salonName = appt.salonName || "Salão";
  let salonAddress = appt.salonAddress || "";
  
  if (appt.shop_id) {
    const { data: shopData } = await supabase.from('shops').select('name, address, address_number, city').eq('id', appt.shop_id).single()
    if (shopData) {
      salonName = shopData.name || salonName
      let addressStr = ""
      if (shopData.address) addressStr += shopData.address
      if (shopData.address_number) addressStr += `, ${shopData.address_number}`
      if (shopData.city) addressStr += ` - ${shopData.city}`
      salonAddress = addressStr || salonAddress
    }
  }

  return {
    clientPhone,
    clientEmail,
    payload: {
      clientName,
      salonName,
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

const buildConfirmationEmail = (data: any) => `
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Agendamento Confirmado – MarkaAI</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f0fb;">
    <tr>
      <td align="center" style="padding:48px 20px;">
        <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
          <tr>
            <td align="center" style="background:linear-gradient(160deg, #3b0f8c 0%, #5c1fc4 60%, #7c3aed 100%); border-radius:16px 16px 0 0; padding:36px 48px 32px;">
              <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="148" style="display:block;margin:0 auto;max-height:44px;object-fit:contain;" />
            </td>
          </tr>
          <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
          <tr>
            <td style="background:#ffffff;padding:44px 48px 36px;">
              <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Agendamento Confirmado! 🗓️</p>
              <p style="margin:0 0 16px;color:#4b5563;font-size:15px;line-height:1.75;">
                Olá <strong>${data.payload.clientName}</strong>, seu agendamento no salão <strong style="color:#5c1fc4;">${data.payload.salonName}</strong> foi confirmado com sucesso.
              </p>
              <div style="background:#f9fafb; border-radius:12px; padding:24px; margin-bottom:32px; border:1px solid #f3f4f6;">
                <p style="margin:0 0 12px; font-size:14px; color:#6b7280; text-transform:uppercase; font-weight:600; letter-spacing:0.5px;">Detalhes do Agendamento</p>
                <p style="margin:0 0 8px; color:#1a1a2e; font-size:16px;"><strong>Serviço:</strong> ${data.payload.serviceName}</p>
                <p style="margin:0 0 8px; color:#1a1a2e; font-size:16px;"><strong>Profissional:</strong> ${data.payload.professionalName}</p>
                <p style="margin:0 0 8px; color:#1a1a2e; font-size:16px;"><strong>Data:</strong> ${data.payload.date} às ${data.payload.time}</p>
                ${data.payload.address ? `<p style="margin:0; color:#1a1a2e; font-size:16px;"><strong>Endereço:</strong> ${data.payload.address}</p>` : ''}
              </div>
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="padding-bottom:36px;">
                    <a href="https://markaai.com.br" style="display:inline-block; background:linear-gradient(135deg,#5c1fc4,#7c3aed); color:#ffffff; text-decoration:none; font-size:15px; font-weight:600; padding:16px 44px; border-radius:10px; letter-spacing:0.2px; box-shadow:0 6px 20px rgba(92,31,196,0.35);">Ver meus agendamentos</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="background:#faf8ff; border-top:1px solid #ede9fe; border-radius:0 0 16px 16px; padding:24px 48px; text-align:center;">
              <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">© 2026 MarkaAI · Email automático, não responda.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

const buildCancellationEmail = (data: any) => `
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Agendamento Cancelado – MarkaAI</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f0fb;">
    <tr>
      <td align="center" style="padding:48px 20px;">
        <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
          <tr>
            <td align="center" style="background:linear-gradient(160deg, #3b0f8c 0%, #5c1fc4 60%, #7c3aed 100%); border-radius:16px 16px 0 0; padding:36px 48px 32px;">
              <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="148" style="display:block;margin:0 auto;max-height:44px;object-fit:contain;" />
            </td>
          </tr>
          <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
          <tr>
            <td style="background:#ffffff;padding:44px 48px 36px;">
              <p style="margin:0 0 20px;color:#ef4444;font-size:20px;font-weight:700;line-height:1.3;">Agendamento Cancelado ❌</p>
              <p style="margin:0 0 16px;color:#4b5563;font-size:15px;line-height:1.75;">
                Olá <strong>${data.payload.clientName}</strong>, informamos que seu agendamento em <strong style="color:#5c1fc4;">${data.payload.salonName}</strong> foi cancelado.
              </p>
              <div style="background:#fef2f2; border-radius:12px; padding:24px; margin-bottom:32px; border:1px solid #fee2e2;">
                <p style="margin:0 0 8px; color:#1a1a2e; font-size:16px;"><strong>O agendamento de:</strong> ${data.payload.date} às ${data.payload.time}</p>
                <p style="margin:0; color:#1a1a2e; font-size:16px;"><strong>Serviço:</strong> ${data.payload.serviceName}</p>
              </div>
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="padding-bottom:36px;">
                    <a href="https://markaai.com.br" style="display:inline-block; background:linear-gradient(135deg,#5c1fc4,#7c3aed); color:#ffffff; text-decoration:none; font-size:15px; font-weight:600; padding:16px 44px; border-radius:10px; letter-spacing:0.2px; box-shadow:0 6px 20px rgba(92,31,196,0.35);">Agendar novo horário</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="background:#faf8ff; border-top:1px solid #ede9fe; border-radius:0 0 16px 16px; padding:24px 48px; text-align:center;">
              <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">© 2026 MarkaAI · Email automático, não responda.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

const buildReschedulingEmail = (data: any) => `
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Agendamento Atualizado – MarkaAI</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f0fb;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#f4f0fb;">
    <tr>
      <td align="center" style="padding:48px 20px;">
        <table width="560" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;width:100%;">
          <tr>
            <td align="center" style="background:linear-gradient(160deg, #3b0f8c 0%, #5c1fc4 60%, #7c3aed 100%); border-radius:16px 16px 0 0; padding:36px 48px 32px;">
              <img src="https://uhccgcojwqvkfyzrmebv.supabase.co/storage/v1/object/public/Logo%20MarkaAI/logo_white.png" alt="MarkaAI" width="148" style="display:block;margin:0 auto;max-height:44px;object-fit:contain;" />
            </td>
          </tr>
          <tr><td style="height:3px;background:linear-gradient(90deg,#7c3aed,#a78bfa,#7c3aed);"></td></tr>
          <tr>
            <td style="background:#ffffff;padding:44px 48px 36px;">
              <p style="margin:0 0 20px;color:#1a1a2e;font-size:20px;font-weight:700;line-height:1.3;">Horário Atualizado! 🔄</p>
              <p style="margin:0 0 16px;color:#4b5563;font-size:15px;line-height:1.75;">
                Olá <strong>${data.payload.clientName}</strong>, seu agendamento no salão <strong style="color:#5c1fc4;">${data.payload.salonName}</strong> foi atualizado para um novo horário.
              </p>
              <div style="background:#f9fafb; border-radius:12px; padding:24px; margin-bottom:32px; border:1px solid #7c3aed;">
                <p style="margin:0 0 12px; font-size:14px; color:#7c3aed; text-transform:uppercase; font-weight:600; letter-spacing:0.5px;">Novo Horário</p>
                <p style="margin:0 0 8px; color:#1a1a2e; font-size:16px;"><strong>Data:</strong> ${data.payload.date} às ${data.payload.time}</p>
                <p style="margin:0 0 8px; color:#1a1a2e; font-size:16px;"><strong>Serviço:</strong> ${data.payload.serviceName}</p>
                <p style="margin:0; color:#1a1a2e; font-size:16px;"><strong>Profissional:</strong> ${data.payload.professionalName}</p>
              </div>
              <table width="100%" cellpadding="0" cellspacing="0" border="0">
                <tr>
                  <td align="center" style="padding-bottom:36px;">
                    <a href="https://markaai.com.br" style="display:inline-block; background:linear-gradient(135deg,#5c1fc4,#7c3aed); color:#ffffff; text-decoration:none; font-size:15px; font-weight:600; padding:16px 44px; border-radius:10px; letter-spacing:0.2px; box-shadow:0 6px 20px rgba(92,31,196,0.35);">Ver detalhes</a>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="background:#faf8ff; border-top:1px solid #ede9fe; border-radius:0 0 16px 16px; padding:24px 48px; text-align:center;">
              <p style="margin:0;color:#c4b5fd;font-size:11px;line-height:1.6;">© 2026 MarkaAI · Email automático, não responda.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;

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

      console.log(`[INSERT] Disparando notificações para agendamento ${appt.id}...`)
      await Promise.allSettled([
        data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_confirmation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time, data.payload.serviceName]) : Promise.resolve(),
        data.clientEmail ? sendEmail(data.clientEmail, 'Agendamento Confirmado', emailHtml) : Promise.resolve()
      ])

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
        
        await Promise.allSettled([
          data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_confirmation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time, data.payload.serviceName]) : Promise.resolve(),
          data.clientEmail ? sendEmail(data.clientEmail, 'Agendamento Confirmado', emailHtml) : Promise.resolve()
        ])
      }
      // 2. Mudança para Cancelamento
      else if (statusChanged && currentStatus === 'cancelado') {
        console.log(`[UPDATE] Status alterado para "cancelado" no agendamento ${after.id}. Enviando email de cancelamento...`)
        const data = await buildPayloadFromAppointment(supabase, after)
        const emailHtml = buildCancellationEmail(data)
        
        await Promise.allSettled([
          data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_cancellation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time]) : Promise.resolve(),
          data.clientEmail ? sendEmail(data.clientEmail, 'Agendamento Cancelado', emailHtml) : Promise.resolve()
        ])
      }
      // 3. Reagendamento (Mudança de Data/Hora mantendo status confirmado)
      else if (dateChanged && notifiableStatuses.includes(currentStatus)) {
        console.log(`[UPDATE] Data/Hora alterada no agendamento ${after.id}. Enviando email de reagendamento...`)
        const data = await buildPayloadFromAppointment(supabase, after)
        const emailHtml = buildReschedulingEmail(data)
        
        await Promise.allSettled([
          data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_confirmation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time, data.payload.serviceName]) : Promise.resolve(),
          data.clientEmail ? sendEmail(data.clientEmail, 'Agendamento Atualizado (Reagendamento)', emailHtml) : Promise.resolve()
        ])
      }
    }


    return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    console.error('Error in appointmentTriggers:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
