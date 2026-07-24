import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient, createSupabaseAdminClient } from '../_shared/supabase.ts'

serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseClient(req)
    const supabaseAdmin = createSupabaseAdminClient()

    // 1. Autenticação e extração do JWT
    let user: any
    try {
      const { data, error: authError } = await supabase.auth.getUser()
      if (authError || !data?.user) {
        return new Response(
          JSON.stringify({ error: 'Usuário não autenticado.' }),
          { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      user = data.user
    } catch (_) {
      return new Response(
        JSON.stringify({ error: 'Usuário não autenticado.' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 2. Extração dos parâmetros com tratamento de erro
    const bodyText = await req.text()
    let bodyData: any
    try {
      bodyData = JSON.parse(bodyText)
    } catch (_) {
      return new Response(
        JSON.stringify({ error: 'Corpo da requisição malformado (JSON inválido).' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { appointment_id, amount } = bodyData

    if (!appointment_id) {
      return new Response(
        JSON.stringify({ error: 'O appointment_id é obrigatório para processar o estorno.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 3. Buscar agendamento e informações da loja (para validação)
    const { data: appointment, error: aptError } = await supabaseAdmin
      .from('appointments')
      .select(`
        id, 
        shop_id, 
        payment_id, 
        paid_amount, 
        refund_status,
        shops (
          owner_id,
          mercadopago
        )
      `)
      .eq('id', appointment_id)
      .single()

    if (aptError || !appointment) {
      return new Response(
        JSON.stringify({ error: 'Agendamento não encontrado.' }),
        { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validação a: appointment existe e tem payment_id preenchido
    if (!appointment.payment_id) {
      return new Response(
        JSON.stringify({ error: 'Este agendamento não possui um pagamento registrado no Mercado Pago.' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validação b: refund_status atual é 'pendente' ou 'processando'
    if (appointment.refund_status !== 'pendente' && appointment.refund_status !== 'processando') {
      return new Response(
        JSON.stringify({ error: `O status de estorno atual é '${appointment.refund_status}' e não pode ser processado. Apenas estornos pendentes (ou em re-tentativa) são permitidos.` }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validação c: user.id bate com shops.owner_id
    // IMPORTANTE: Neste sistema, shop.id === user.id por design (ver login_page.dart).
    // owner_id pode estar vazio em lojas antigas — usamos shop_id como fallback confiável.
    const shopOwnerIdRaw = Array.isArray(appointment.shops) 
      ? appointment.shops[0]?.owner_id 
      : appointment.shops?.owner_id

    // Normaliza ambos os lados para evitar falhas por tipo (TEXT vs UUID) ou espaços
    const shopOwnerIdNormalized = shopOwnerIdRaw?.toString().trim().toLowerCase() ?? ''
    const userId = user.id?.toString().trim().toLowerCase() ?? ''

    // Fallback: se owner_id estiver vazio, usa shop_id (pois shop.id === user.id neste sistema)
    const shopId = appointment.shop_id?.toString().trim().toLowerCase() ?? ''
    const effectiveOwnerId = shopOwnerIdNormalized || shopId

    console.log(`[processRefund] Verificando permissão: user.id="${userId}" vs owner_id="${shopOwnerIdNormalized}" (fallback shop_id="${shopId}")`)

    if (!effectiveOwnerId || userId !== effectiveOwnerId) {
      console.warn(`[processRefund] Permissão negada: user.id="${userId}", effective_owner_id="${effectiveOwnerId}", appointment_id="${appointment_id}"`)
      return new Response(
        JSON.stringify({ error: 'Sem permissão. Apenas o dono da loja pode realizar estornos financeiros.' }),
        { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // Validação d: validação do amount (se parcial) com tolerância financeira
    const paidAmount = parseFloat(appointment.paid_amount || '0')
    let requestedRefundAmount: number | undefined = undefined

    if (amount !== undefined && amount !== null) {
      requestedRefundAmount = parseFloat(amount)
      if (isNaN(requestedRefundAmount) || requestedRefundAmount <= 0) {
        return new Response(
          JSON.stringify({ error: 'O valor do estorno deve ser maior que zero.' }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
      // Tolerância de 5 centavos para não bloquear por pequenos arredondamentos
      if (requestedRefundAmount > paidAmount + 0.05) {
        return new Response(
          JSON.stringify({ error: `O valor do estorno (${requestedRefundAmount}) não pode ser maior que o valor pago (${paidAmount}).` }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }
    }

    // 4. Buscar o access_token do Mercado Pago da loja
    const mercadopagoConfig = Array.isArray(appointment.shops) 
      ? appointment.shops[0]?.mercadopago 
      : appointment.shops?.mercadopago

    const accessToken = mercadopagoConfig?.access_token
    if (!accessToken) {
      return new Response(
        JSON.stringify({ error: 'Conta do Mercado Pago não configurada para esta loja. Impossível realizar estorno.' }),
        { status: 412, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // 5. TRAVA ATÔMICA (Atomic Lock) - Defesa em Profundidade
    // Se o estorno já estava em 'processando' (retry), reaproveitamos o valor que foi gravado na primeira tentativa,
    // ignorando qualquer novo valor no body. Isso garante semântica correta na idempotency key.
    let targetRefundAmount = requestedRefundAmount ?? paidAmount;
    if (appointment.refund_status === 'processando' && appointment.refund_amount) {
      const savedAmount = parseFloat(appointment.refund_amount.toString());
      if (!isNaN(savedAmount)) {
        targetRefundAmount = savedAmount;
      }
    }

    // Tentamos fazer update condicional. Aceitamos transição de pendente -> processando OU processando -> processando (retry)
    // Gravamos o targetRefundAmount logo na trava para "congelar" a intenção inicial.
    const { data: lockData, error: lockError } = await supabaseAdmin
      .from('appointments')
      .update({ 
        refund_status: 'processando',
        refund_amount: targetRefundAmount
      })
      .eq('id', appointment.id)
      .in('refund_status', ['pendente', 'processando'])
      .select('id')
      .maybeSingle()

    if (lockError || !lockData) {
      console.warn(`[processRefund] Concorrência bloqueada: appointment_id ${appointment.id} teve o status alterado antes de adquirir o lock.`)
      return new Response(
        JSON.stringify({ error: 'Não foi possível adquirir a trava atômica para este estorno. Verifique se ele já foi concluído.' }),
        { status: 409, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    // A partir daqui, estamos em 'processando'. Qualquer erro de rede/parsing DEVE reverter para 'pendente' se não foi confirmado pelo MP.
    let mpConfirmedSuccess = false;
    let mpResponseData: any = null;

    try {
      // 6. Chamar a API de Refunds do Mercado Pago
      // Chave determinística (Idempotency Key): Garante que re-tentativas da MESMA operação não disparem duplo estorno no MP
      const idempotencyKey = `refund-${appointment.payment_id}`
      const baseUrl = accessToken.startsWith('TEST-') 
        ? 'https://api.sandbox.mercadopago.com' 
        : 'https://api.mercadopago.com'

      // Se targetRefundAmount for exatamente igual ao pago, enviamos sem payload para o MP fazer um estorno TOTAL automático.
      // Se for menor, enviamos parcial.
      const refundPayload = targetRefundAmount < paidAmount ? { amount: targetRefundAmount } : {}

      console.log(`[processRefund] Iniciando estorno para payment_id ${appointment.payment_id}. Total pago: ${paidAmount}. Solicitado: ${targetRefundAmount}`)

      const res = await fetch(`${baseUrl}/v1/payments/${appointment.payment_id}/refunds`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${accessToken}`,
          'X-Idempotency-Key': idempotencyKey,
          'Content-Type': 'application/json'
        },
        body: Object.keys(refundPayload).length > 0 ? JSON.stringify(refundPayload) : undefined
      })

      // Se falhar o parse (HTML no lugar de JSON, etc), lançará erro capturado pelo try/catch
      mpResponseData = await res.json()

      // Tratar os erros conhecidos da API do Mercado Pago
      if (!res.ok || (res.status !== 200 && res.status !== 201)) {
        console.error("[processRefund] Erro do Mercado Pago:", mpResponseData)
        const causeStr = JSON.stringify(mpResponseData.cause || {}).toLowerCase()
        const messageStr = (mpResponseData.message || '').toLowerCase()

        let errorMessage = 'O Mercado Pago recusou o estorno.'
        
        if (causeStr.includes('refund_amount_exceeds')) {
          errorMessage = 'Saldo insuficiente na transação ou valor do estorno excede o limite.'
        } else if (causeStr.includes('3024') || messageStr.includes('partial refund')) {
          errorMessage = 'O tipo de pagamento desta transação não suporta estornos parciais.'
        } else if (causeStr.includes('insufficient_balance') || messageStr.includes('insufficient balance')) {
          errorMessage = 'Sua conta do Mercado Pago não possui saldo suficiente para cobrir este estorno.'
        } else if (causeStr.includes('expired') || causeStr.includes('time limit')) {
          errorMessage = 'O prazo máximo para estorno desta transação (geralmente 180 dias) já expirou no Mercado Pago.'
        } else {
          errorMessage = `Erro MP: ${mpResponseData.message || 'Desconhecido'}`
        }

        // MP respondeu ativamente recusando. Revertemos o status para permitir tentar novamente.
        console.log(`[processRefund] MP recusou. Fazendo rollback do lock de 'processando' para 'pendente' no appointment ${appointment.id}`)
        await supabaseAdmin
          .from('appointments')
          .update({ refund_status: 'pendente' })
          .eq('id', appointment.id)

        return new Response(
          JSON.stringify({ error: errorMessage, details: mpResponseData }),
          { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
      }

      // Se chegamos aqui, o Mercado Pago confirmou sucesso no estorno (200/201).
      mpConfirmedSuccess = true;
    } catch (apiError: any) {
      console.error('[processRefund] Erro de rede ou parsing na chamada ao MP:', apiError)
      // Ocorreu erro de rede/timeout/parsing ANTES de termos confirmação de sucesso do MP.
      // É seguro reverter para 'pendente', já que a idempotency key protegerá contra duplo processamento em nova tentativa.
      await supabaseAdmin
        .from('appointments')
        .update({ refund_status: 'pendente' })
        .eq('id', appointment.id)

      return new Response(
        JSON.stringify({ error: `Erro de comunicação com o Mercado Pago: ${apiError.message}. Tente novamente.` }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } } // 502 Bad Gateway
      )
    }

    // 7. Sucesso no estorno — atualizar a tabela appointments
    // Se o código chegou aqui, mpConfirmedSuccess é true. O dinheiro já saiu no MP.
    const finalRefundAmount = mpResponseData.amount ?? targetRefundAmount
    
    const { error: updateError } = await supabaseAdmin
      .from('appointments')
      .update({
        refund_status: 'estornado',
        refund_amount: finalRefundAmount,
        refunded_at: new Date().toISOString(),
        refunded_by: user.id
      })
      .eq('id', appointment.id)

    if (updateError) {
      console.error("[processRefund] ALERTA_ESTORNO_PRESO: Erro crítico ao atualizar o banco após sucesso no MP:", updateError)
      // O dinheiro foi devolvido no MP, mas o banco falhou em salvar.
      // NÃO FAREMOS ROLLBACK para 'pendente' para não esconder que o dinheiro já foi devolvido.
      // Continua como 'processando', podendo ser retentado (a key idem. garantirá 200/201 do MP e re-tentará este UPDATE).
      return new Response(
        JSON.stringify({ 
          error: 'O estorno foi processado no Mercado Pago com sucesso, mas ocorreu um erro ao salvar o status final. O status continua como Processando, você pode tentar confirmar novamente sem risco de cobrança dupla.', 
          mp_data: mpResponseData 
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    return new Response(
      JSON.stringify({ 
        message: 'Estorno processado com sucesso!', 
        refund_amount: finalRefundAmount,
        mp_data: mpResponseData 
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error: any) {
    // Erros catastróficos que caiam aqui (antes do lock ou depois que saímos do fluxo principal)
    console.error('[processRefund] Erro interno:', error)
    return new Response(
      JSON.stringify({ error: `Erro inesperado: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
