import { createSupabaseAdminClient } from '../_shared/supabase.ts'

/**
 * Webhook do Mercado Pago para pagamentos PIX.
 *
 * Fluxo:
 * 1. MP chama esta URL quando um pagamento muda de status.
 * 2. Verificamos o pagamento na API do MP usando o access_token da loja.
 * 3. Se aprovado, encontramos o agendamento via external_reference (appointment_id)
 *    ou via coluna payment_id e atualizamos o status para 'confirmado'.
 *
 * Configuração no Mercado Pago:
 *   URL: https://<SUPABASE_URL>/functions/v1/mpPaymentWebhook
 *   Tópico: payments
 */

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    })
  }

  // MP às vezes envia GET para validar a URL do webhook
  if (req.method === 'GET') {
    return new Response(JSON.stringify({ ok: true }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  try {
    const body = await req.json()
    console.log('[mpPaymentWebhook] Recebido:', JSON.stringify(body))

    // Só processa eventos de pagamento
    if (body.type !== 'payment') {
      return new Response(JSON.stringify({ ok: true, skipped: true, type: body.type }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const paymentId = body.data?.id?.toString()
    const mpUserId = body.user_id?.toString() // ID do vendedor no MP

    if (!paymentId) {
      return new Response(JSON.stringify({ error: 'payment_id ausente' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const supabase = createSupabaseAdminClient()

    // -----------------------------------------------------------------------
    // Passo 1: Encontrar o access_token da loja via MP user_id
    // -----------------------------------------------------------------------
    let accessToken: string | null = null
    let shopId: string | null = null

    if (mpUserId) {
      const { data: shopRows } = await supabase
        .from('shops')
        .select('id, mercadopago')
        .filter('mercadopago->>user_id', 'eq', mpUserId)
        .limit(1)

      if (shopRows && shopRows.length > 0) {
        shopId = shopRows[0].id
        accessToken = shopRows[0].mercadopago?.access_token ?? null
      }
    }

    // Fallback: buscar pelo payment_id já salvo no agendamento
    if (!accessToken) {
      const { data: apptRows } = await supabase
        .from('appointments')
        .select('id, shop_id')
        .eq('payment_id', paymentId)
        .limit(1)

      if (apptRows && apptRows.length > 0) {
        shopId = apptRows[0].shop_id
        const { data: shopRow } = await supabase
          .from('shops')
          .select('mercadopago')
          .eq('id', shopId)
          .maybeSingle()
        accessToken = shopRow?.mercadopago?.access_token ?? null
      }
    }

    if (!accessToken) {
      console.error('[mpPaymentWebhook] Access token não encontrado para MP user_id:', mpUserId)
      // Retornamos 200 para o MP não reenviar (sem token = loja não configurada)
      return new Response(JSON.stringify({ ok: false, message: 'Loja não configurada' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // -----------------------------------------------------------------------
    // Passo 2: Verificar o pagamento na API do Mercado Pago
    // -----------------------------------------------------------------------
    const baseUrl = accessToken.startsWith('TEST-')
      ? 'https://api.sandbox.mercadopago.com'
      : 'https://api.mercadopago.com'

    const paymentRes = await fetch(`${baseUrl}/v1/payments/${paymentId}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    })

    if (!paymentRes.ok) {
      console.error('[mpPaymentWebhook] Erro ao buscar pagamento no MP:', paymentRes.status)
      return new Response(JSON.stringify({ error: 'Falha ao verificar pagamento no MP' }), {
        status: 502,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const paymentData = await paymentRes.json()
    console.log(`[mpPaymentWebhook] Pagamento ${paymentId} status: ${paymentData.status}`)

    if (paymentData.status !== 'approved') {
      return new Response(
        JSON.stringify({ ok: true, status: paymentData.status, message: 'Pagamento não aprovado ainda' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // -----------------------------------------------------------------------
    // Passo 3: Encontrar o agendamento
    // Primeira opção: external_reference (= appointment ID pré-salvo)
    // Segunda opção: coluna payment_id
    // -----------------------------------------------------------------------
    const externalRef = paymentData.external_reference?.toString()
    let appointmentId: string | null = null

    if (externalRef) {
      const { data: apptRow } = await supabase
        .from('appointments')
        .select('id, status')
        .eq('id', externalRef)
        .maybeSingle()

      if (apptRow) {
        appointmentId = apptRow.id
        if (apptRow.status === 'confirmado') {
          console.log(`[mpPaymentWebhook] Agendamento ${appointmentId} já confirmado — idempotente, ok.`)
          return new Response(JSON.stringify({ ok: true, already_confirmed: true }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          })
        }
      }
    }

    // Fallback pelo payment_id
    if (!appointmentId) {
      const { data: apptRows } = await supabase
        .from('appointments')
        .select('id, status')
        .eq('payment_id', paymentId)
        .limit(1)

      if (apptRows && apptRows.length > 0) {
        appointmentId = apptRows[0].id
        if (apptRows[0].status === 'confirmado') {
          return new Response(JSON.stringify({ ok: true, already_confirmed: true }), {
            status: 200,
            headers: { 'Content-Type': 'application/json' },
          })
        }
      }
    }

    if (!appointmentId) {
      console.error(
        `[mpPaymentWebhook] Agendamento não encontrado — payment_id: ${paymentId}, external_ref: ${externalRef}`,
      )
      // Retornamos 200 para o MP não reenviar infinitamente
      return new Response(
        JSON.stringify({ ok: false, message: 'Agendamento não encontrado', payment_id: paymentId }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // -----------------------------------------------------------------------
    // Passo 4: Confirmar o agendamento
    // -----------------------------------------------------------------------
    const paidAmount = paymentData.transaction_amount ?? 0

    // Busca total_payable para calcular remaining
    const { data: currentAppt } = await supabase
      .from('appointments')
      .select('total_payable')
      .eq('id', appointmentId)
      .maybeSingle()

    const totalPayable = currentAppt?.total_payable ?? paidAmount
    const remainingAmount = Math.max(0, totalPayable - paidAmount)

    const { error: updateError } = await supabase
      .from('appointments')
      .update({
        status: 'confirmado',
        payment_status: 'pago',
        payment_id: paymentId,
        payment_method: 'Pix',
        paid_amount: paidAmount,
        remaining_amount: remainingAmount,
        updated_at: new Date().toISOString(),
      })
      .eq('id', appointmentId)

    if (updateError) {
      console.error('[mpPaymentWebhook] Erro ao atualizar agendamento:', updateError)
      return new Response(JSON.stringify({ error: 'Falha ao confirmar agendamento' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    console.log(`[mpPaymentWebhook] ✅ Agendamento ${appointmentId} confirmado via webhook (payment ${paymentId})`)

    return new Response(JSON.stringify({ ok: true, appointment_id: appointmentId }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error: any) {
    console.error('[mpPaymentWebhook] Erro inesperado:', error)
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
