import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface SendMessagePayload {
  action?: 'test' | 'send';
  shop_id?: string;
  phone_number_id?: string; // para teste
  access_token?: string; // para teste
  to?: string;
  template_name?: string;
  language_code?: string;
  components?: object[];
}

serve(async (req) => {
  // CORS configuration
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // --- GET: WEBHOOK VERIFICATION MODO ---
  if (req.method === 'GET') {
    const url = new URL(req.url)
    const mode = url.searchParams.get('hub.mode')
    const token = url.searchParams.get('hub.verify_token')
    const challenge = url.searchParams.get('hub.challenge')

    // Normally you'd want to query 'shop_whatsapp_config' to check if 'token' is valid.
    // However, finding the specific token without knowing the shop is a bit broad.
    // As a simple validation, we check if the token exists for ANY active shop:
    if (mode === 'subscribe' && token && challenge) {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      )
      
      const { data, error } = await supabase
        .from('shop_whatsapp_config')
        .select('id')
        .eq('wa_webhook_verify_token', token)
        .eq('is_active', true)
        .maybeSingle()

      if (data && !error) {
        return new Response(challenge, { status: 200 })
      } else {
        return new Response('Forbidden', { status: 403 })
      }
    }
    return new Response('Bad Request', { status: 400 })
  }

  // --- POST: SEND MESSAGE ---
  try {
    // Verifica autenticação — apenas usuários logados podem disparar mensagens
    const authHeader = req.headers.get('Authorization')?.replace('Bearer ', '') ?? ''
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Não autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }
    const authClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? ''
    )
    const { data: { user }, error: authError } = await authClient.auth.getUser(authHeader)
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Não autorizado' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const payload: SendMessagePayload = await req.json()
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // Verifica se o usuário é dono da loja
    if (payload.shop_id) {
      const { data: ownerCheck, error: ownerError } = await supabase
        .from('shops')
        .select('owner_id')
        .eq('id', payload.shop_id)
        .maybeSingle()

      if (ownerError || !ownerCheck || ownerCheck.owner_id !== user.id) {
        return new Response(JSON.stringify({ error: 'Apenas o dono da loja pode enviar mensagens' }), {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }
    }

    // TEST CONNECTION ACTION
    if (payload.action === 'test') {
      const { phone_number_id, access_token } = payload
      if (!phone_number_id || !access_token) throw new Error('Missing test params')

      // Dispara uma request simples para validar credenciais.
      const testRes = await fetch(`https://graph.facebook.com/v19.0/${phone_number_id}`, {
        headers: { 'Authorization': `Bearer ${access_token}` }
      })

      if (testRes.ok) {
        return new Response(JSON.stringify({ success: true }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      } else {
        return new Response(JSON.stringify({ success: false, error: await testRes.text() }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }
    }

    // SEND MESSAGE ACTION
    if (!payload.shop_id || !payload.to || !payload.template_name) {
      throw new Error('Parâmetros ausentes (shop_id, to, template_name)')
    }

    // Verifica se a loja está em plano plus ou pro
    const { data: shopData, error: shopError } = await supabase
      .from('shops')
      .select('plan')
      .eq('id', payload.shop_id)
      .maybeSingle()

    if (shopError) throw shopError

    const shopPlan = (shopData?.plan || '').toLowerCase()
    if (shopPlan !== 'plus' && shopPlan !== 'pro') {
      throw new Error(`WhatsApp disponível apenas para planos Plus e Pro. Plano atual: ${shopPlan || 'free'}`)
    }

    // Busca configurações
    const { data: config, error: configError } = await supabase
      .from('shop_whatsapp_config')
      .select('*')
      .eq('shop_id', payload.shop_id)
      .eq('is_active', true)
      .maybeSingle()

    if (configError) throw configError
    
    // Fallback logic
    const phoneNumberId = config?.wa_phone_number_id || Deno.env.get('GLOBAL_WA_PHONE_NUMBER_ID')
    const accessToken = config?.wa_access_token || Deno.env.get('GLOBAL_WA_ACCESS_TOKEN')

    if (!phoneNumberId || !accessToken) {
      throw new Error('Integração WABA não está ativa para esta loja e credenciais globais não encontradas.')
    }

    // Format phone to E.164
    const toPhone = payload.to.replace(/\D/g, '')

    const metaPayload = {
      messaging_product: 'whatsapp',
      to: toPhone,
      type: 'template',
      template: {
        name: payload.template_name,
        language: { code: payload.language_code || 'pt_BR' },
      }
    } as any

    if (payload.components && payload.components.length > 0) {
      metaPayload.template.components = payload.components
    }

    // Call Meta API
    const metaRes = await fetch(`https://graph.facebook.com/v19.0/${phoneNumberId}/messages`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(metaPayload)
    })

    const metaData = await metaRes.json()
    const success = metaRes.ok

    // Log the request
    await supabase.from('whatsapp_send_log').insert({
      shop_id: payload.shop_id,
      to_phone: toPhone,
      template_name: payload.template_name,
      status: success ? 'success' : 'error',
      response_json: metaData
    })

    if (!success) {
      throw new Error(JSON.stringify(metaData))
    }

    return new Response(JSON.stringify({ success: true, meta_response: metaData }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    console.error('Error on whatsapp-send:', error)
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
