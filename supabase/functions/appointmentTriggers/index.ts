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
    console.warn('Resend API key missing.')
    return
  }

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({ from, to, subject, html })
    })
    const data = await res.json()
    console.log(`Email sent to ${to}:`, data)
  } catch (err) {
    console.error('Error sending Email:', err)
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
  } else if (appt.data_agendamento) {
    const d = new Date(appt.data_agendamento);
    date = `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}/${d.getFullYear()}`;
    time = appt.horario || "";
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
      const data = await buildPayloadFromAppointment(supabase, appt)
      
      if (!data.clientPhone && !data.clientEmail) {
        console.warn('No contact info for appointment:', appt.id)
        return new Response('No contact info', { status: 200 })
      }

      const emailHtml = `<h1>Agendamento Confirmado!</h1>
        <p>Olá ${data.payload.clientName}, seu agendamento no salão <strong>${data.payload.salonName}</strong> foi confirmado.</p>
        <ul>
          <li><strong>Serviço:</strong> ${data.payload.serviceName}</li>
          <li><strong>Profissional:</strong> ${data.payload.professionalName}</li>
          <li><strong>Data:</strong> ${data.payload.date} às ${data.payload.time}</li>
        </ul>`

      await Promise.allSettled([
        data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_confirmation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time, data.payload.serviceName]) : Promise.resolve(),
        data.clientEmail ? sendEmail(data.clientEmail, 'Agendamento Confirmado', emailHtml) : Promise.resolve()
      ])
    } 
    else if (payload.type === 'UPDATE') {
      const before = payload.old_record
      const after = payload.record

      if (before.status !== after.status && after.status === 'cancelado') {
        const data = await buildPayloadFromAppointment(supabase, after)
        
        const emailHtml = `<h1>Agendamento Cancelado</h1>
        <p>Olá ${data.payload.clientName}, informamos que seu agendamento de ${data.payload.date} às ${data.payload.time} em <strong>${data.payload.salonName}</strong> foi cancelado.</p>`

        await Promise.allSettled([
          data.clientPhone ? sendWhatsApp(data.clientPhone, 'appointment_cancellation', [data.payload.clientName, data.payload.salonName, data.payload.date, data.payload.time]) : Promise.resolve(),
          data.clientEmail ? sendEmail(data.clientEmail, 'Agendamento Cancelado', emailHtml) : Promise.resolve()
        ])
      }
    }

    return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (error) {
    console.error('Error in appointmentTriggers:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
