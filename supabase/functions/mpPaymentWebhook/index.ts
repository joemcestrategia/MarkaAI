import { createSupabaseAdminClient } from '../_shared/supabase.ts'

/**
 * Valida assinatura HMAC-SHA256 do Mercado Pago.
 * Header: x-signature = "ts=<timestamp>,v1=<hex_hash>"
 * O payload assinado é "ts<timestamp>.+raw_body" ou "data.id=...;request-id=...;ts=...;"
 */
async function verifyMPSignature(
  rawBody: string,
  signatureHeader: string | null,
  secret: string,
  dataId: string,
): Promise<boolean> {
  if (!signatureHeader) return false
  const parts = signatureHeader.split(',')
  const ts = parts.find(p => p.startsWith('ts='))?.replace('ts=', '')
  const v1 = parts.find(p => p.startsWith('v1='))?.replace('v1=', '')
  if (!ts || !v1) return false

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const templates = [
    `id:${dataId};ts:${ts};`,
    `${ts}.${rawBody}`,
  ]
  for (const template of templates) {
    const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(template))
    const computed = Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('')
    if (computed === v1) return true
  }
  return false
}

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
    const rawBody = await req.text()
    const body = JSON.parse(rawBody)
    console.log('[mpPaymentWebhook] Recebido:', JSON.stringify(body))

    // Validação HMAC — se chave configurada, assinatura é obrigatória
    const secret = Deno.env.get('MERCADOPAGO_WEBHOOK_SECRET')
    if (secret) {
      const signature = req.headers.get('x-signature')
      const valid = await verifyMPSignature(rawBody, signature, secret, body.data?.id?.toString() ?? '')
      if (!valid) {
        console.error('[mpPaymentWebhook] Assinatura HMAC inválida')
        return new Response(JSON.stringify({ error: 'Assinatura inválida' }), {
          status: 401,
          headers: { 'Content-Type': 'application/json' },
        })
      }
    } else {
      console.warn('[mpPaymentWebhook] MERCADOPAGO_WEBHOOK_SECRET não configurada — pulando validação HMAC')
    }

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

    // -----------------------------------------------------------------------
    // Passo 2.5: Sincronização de Estornos Externos (BLOCO ISOLADO)
    // Se o pagamento foi estornado no painel do MP, sincronizamos o status
    // no nosso banco. Este bloco retorna ANTES de tocar no fluxo de pagamento.
    // -----------------------------------------------------------------------
    if (paymentData.status === 'refunded') {
      console.log(`[mpPaymentWebhook] Pagamento ${paymentId} tem status 'refunded'. Iniciando sincronização de estorno externo.`)

      // Buscar o agendamento vinculado a este payment_id
      const { data: refundAppt } = await supabase
        .from('appointments')
        .select('id, refund_status, paid_amount')
        .eq('payment_id', paymentId)
        .maybeSingle()

      if (!refundAppt) {
        console.warn(`[mpPaymentWebhook] Pagamento ${paymentId} refunded, mas nenhum agendamento vinculado encontrado.`)
        return new Response(
          JSON.stringify({ ok: true, message: 'Estorno detectado, mas sem agendamento vinculado', payment_id: paymentId }),
          { status: 200, headers: { 'Content-Type': 'application/json' } },
        )
      }

      // Idempotência: se já está 'estornado', não faz nada
      if (refundAppt.refund_status === 'estornado') {
        console.log(`[mpPaymentWebhook] Agendamento ${refundAppt.id} já está com refund_status='estornado'. Idempotência OK.`)
        return new Response(
          JSON.stringify({ ok: true, already_refunded: true, appointment_id: refundAppt.id }),
          { status: 200, headers: { 'Content-Type': 'application/json' } },
        )
      }

      // Buscar dados reais do refund na API do MP (server-side verification, não confia no body do webhook)
      let totalRefundedAmount = 0
      try {
        const refundsRes = await fetch(`${baseUrl}/v1/payments/${paymentId}/refunds`, {
          headers: { Authorization: `Bearer ${accessToken}` },
        })
        if (refundsRes.ok) {
          const refundsData = await refundsRes.json()
          // Pode haver múltiplos refunds parciais — somar todos
          if (Array.isArray(refundsData)) {
            totalRefundedAmount = refundsData.reduce((sum: number, r: any) => sum + (r.amount ?? 0), 0)
          }
        } else {
          console.warn(`[mpPaymentWebhook] Não conseguiu buscar refunds da API do MP (status ${refundsRes.status}). Usando paid_amount como fallback.`)
          totalRefundedAmount = refundAppt.paid_amount ?? 0
        }
      } catch (refundFetchError: any) {
        console.warn(`[mpPaymentWebhook] Erro ao buscar refunds da API do MP:`, refundFetchError?.message)
        totalRefundedAmount = refundAppt.paid_amount ?? 0
      }

      // UPDATE condicional (idempotência via WHERE)
      const { data: updatedRefund, error: refundUpdateError } = await supabase
        .from('appointments')
        .update({
          refund_status: 'estornado',
          refund_amount: totalRefundedAmount,
          refunded_at: new Date().toISOString(),
          refunded_by: 'mercadopago_webhook',
        })
        .eq('id', refundAppt.id)
        .in('refund_status', ['nao_aplicavel', 'pendente', 'processando'])
        .select('id')
        .maybeSingle()

      if (refundUpdateError) {
        console.error(`[mpPaymentWebhook] Erro ao sincronizar estorno externo:`, refundUpdateError)
        return new Response(
          JSON.stringify({ error: 'Erro ao sincronizar estorno externo' }),
          { status: 500, headers: { 'Content-Type': 'application/json' } },
        )
      }

      if (updatedRefund) {
        console.log(`[mpPaymentWebhook] ESTORNO_EXTERNO_SINCRONIZADO: appointment ${refundAppt.id}, valor ${totalRefundedAmount}, payment ${paymentId}`)
      } else {
        console.log(`[mpPaymentWebhook] Estorno externo para appointment ${refundAppt.id} — nenhuma linha atualizada (já processado ou status incompatível).`)
      }

      return new Response(
        JSON.stringify({ ok: true, refund_synced: true, appointment_id: refundAppt.id, amount: totalRefundedAmount }),
        { status: 200, headers: { 'Content-Type': 'application/json' } },
      )
    }

    // Fluxo normal: só processa pagamentos aprovados
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
        .select('id, status, shop_id')
        .eq('id', externalRef)
        .maybeSingle()

      if (apptRow) {
        appointmentId = apptRow.id
        shopId = shopId || apptRow.shop_id
      }
    }

    // Fallback pelo payment_id
    if (!appointmentId) {
      const { data: apptRows } = await supabase
        .from('appointments')
        .select('id, status, shop_id')
        .eq('payment_id', paymentId)
        .limit(1)

      if (apptRows && apptRows.length > 0) {
        appointmentId = apptRows[0].id
        shopId = shopId || apptRows[0].shop_id
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

    const paidAmount = paymentData.transaction_amount ?? 0

    // -----------------------------------------------------------------------
    // Passo 3.5: Idempotência Atômica via Tabela de Controle
    // -----------------------------------------------------------------------
    const { error: insertError } = await supabase
      .from('mp_processed_payments')
      .insert({
        payment_id: paymentId,
        appointment_id: appointmentId,
        shop_id: shopId,
        amount: paidAmount,
        status: paymentData.status
      })

    // Se violar a PRIMARY KEY (código 23505), já processamos este webhook
    if (insertError) {
      if (insertError.code === '23505') {
        console.log(`[mpPaymentWebhook] Pagamento ${paymentId} já processado anteriormente. Retornando 200 (idempotência atômica).`)
        return new Response(JSON.stringify({ ok: true, already_processed: true }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      } else {
        console.error(`[mpPaymentWebhook] Erro ao inserir na tabela de idempotência:`, insertError)
        return new Response(JSON.stringify({ error: 'Erro interno ao validar idempotência' }), {
          status: 500,
          headers: { 'Content-Type': 'application/json' },
        })
      }
    }

    // -----------------------------------------------------------------------
    // Passo 4: Confirmar o agendamento
    // -----------------------------------------------------------------------

    try {
      // Busca total_payable, paid_amount, payment_id e metadata para calcular remaining e consolidar pagamentos
      const { data: currentAppt, error: selectError } = await supabase
        .from('appointments')
        .select('total_payable, paid_amount, payment_id, metadata, status')
        .eq('id', appointmentId)
        .maybeSingle()

      if (selectError) throw selectError

      const paymentTypeId = paymentData.payment_type_id?.toString()?.toLowerCase() || ''
      const paymentMethodId = paymentData.payment_method_id?.toString()?.toLowerCase() || ''

      let realPaymentMethod = 'Pix' // fallback default
      if (paymentTypeId === 'credit_card') {
        realPaymentMethod = 'Cartão de Crédito'
      } else if (paymentTypeId === 'debit_card') {
        realPaymentMethod = 'Cartão de Débito'
      } else if (paymentMethodId === 'pix' || paymentTypeId === 'bank_transfer') {
        realPaymentMethod = 'Pix'
      } else if (paymentTypeId === 'ticket') {
        realPaymentMethod = 'Boleto'
      } else if (paymentTypeId === 'account_money') {
        realPaymentMethod = 'Saldo Mercado Pago'
      }

      // Calcula os valores somados, verificando se não é um pagamento repetido
      const totalPayable = currentAppt?.total_payable ?? paidAmount
      let newPaidAmount = currentAppt?.paid_amount ?? 0
      let isSecondPayment = false
      
      if (currentAppt?.payment_id && currentAppt.payment_id !== paymentId.toString()) {
        isSecondPayment = true
        const meta = currentAppt?.metadata || {}
        if (meta.completion_payment_id !== paymentId.toString()) {
          newPaidAmount += paidAmount
        }
      } else {
        newPaidAmount = paidAmount
      }

      const remainingAmount = Math.max(0, totalPayable - newPaidAmount)
      const newStatus = currentAppt?.status === 'concluido' ? 'concluido' : 'confirmado'

      const updatePayload: any = {
        status: newStatus,
        payment_status: newPaidAmount >= (totalPayable - 0.05) ? 'pago' : 'parcial',
        paid_amount: newPaidAmount,
        remaining_amount: remainingAmount,
        pago_em: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }

      if (isSecondPayment) {
        const currentMeta = currentAppt?.metadata || {}
        updatePayload.payment_method = realPaymentMethod
        updatePayload.metadata = {
          ...currentMeta,
          advance_payment_id: currentMeta.advance_payment_id || currentAppt?.payment_id,
          payment_id: paymentId,
          completion_payment_id: paymentId,
          completion_payment_method: realPaymentMethod,
          completion_paid_at: new Date().toISOString(),
          valor_pago: newPaidAmount,
          restante_a_pagar: remainingAmount,
        }
      } else {
        updatePayload.payment_id = paymentId
        updatePayload.payment_method = realPaymentMethod
      }

      const { error: updateError } = await supabase
        .from('appointments')
        .update(updatePayload)
        .eq('id', appointmentId)

      if (updateError) throw updateError

    } catch (passo4Error: any) {
      console.error('[mpPaymentWebhook] Erro no processamento final do Passo 4:', passo4Error)
      
      // Rollback compensatório (Opção 2b aprimorada):
      // Removemos o registro de idempotência recém-inserido caso qualquer 
      // operação (SELECT, cálculos, UPDATE) falhe, permitindo o retry pelo MP.
      await supabase
        .from('mp_processed_payments')
        .delete()
        .eq('payment_id', paymentId)
      
      return new Response(JSON.stringify({ error: 'Falha no processamento, rollback executado' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    console.log(`[mpPaymentWebhook] ✅ Agendamento ${appointmentId} confirmado via webhook (payment ${paymentId})`)

    // ── Auto-emissão NFS-e (fire-and-forget) ──────────────────────────────
    // Verifica se a loja tem emissão automática ativa para pagamentos online.
    // Nunca bloqueia o webhook — qualquer falha é silenciada.
    try {
      const { data: nfseCfg } = await supabase
        .from('nfse_config')
        .select('id, ativo, emitir_automatico_cartao')
        .eq('shop_id', shopId)
        .eq('ativo', true)
        .maybeSingle()

      if (nfseCfg?.emitir_automatico_cartao === true) {
        supabase.functions.invoke('emitir-nfse', {
          body: { appointment_id: appointmentId, shop_id: shopId }
        }).catch((e: any) => {
          console.warn('[mpPaymentWebhook] Auto-emissão NFS-e falhou silenciosamente:', e?.message)
        })
        console.log(`[mpPaymentWebhook] 🧾 Auto-emissão NFS-e disparada para agendamento ${appointmentId}`)
      }
    } catch (nfseErr: any) {
      console.warn('[mpPaymentWebhook] Erro ao verificar config NFS-e (ignorado):', nfseErr?.message)
    }
    // ── Fim Auto-emissão NFS-e ─────────────────────────────────────────────

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
