import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.39.0'
import { load } from "https://deno.land/std@0.208.0/dotenv/mod.ts"

// 1. Load env variables
const env = await load({ envPath: "./scripts/tests/.env" })
const SUPABASE_URL = env["SUPABASE_URL"] || Deno.env.get("SUPABASE_URL")
const SUPABASE_KEY = env["SUPABASE_SERVICE_ROLE_KEY"] || Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")

if (!SUPABASE_URL || !SUPABASE_KEY) {
  console.error("ERRO: SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY não encontrados.")
  Deno.exit(1)
}

const supabase = createClient(SUPABASE_URL, SUPABASE_KEY)

async function runDryRun() {
  console.log("==================================================")
  console.log("🔍 INICIANDO DRY-RUN: RECONCILIAÇÃO MERCADO PAGO")
  console.log("==================================================")

  // Busca lojas que têm MP configurado
  const { data: shops, error: shopErr } = await supabase
    .from('shops')
    .select('id, name, mercadopago')
    .not('mercadopago', 'is', null)

  if (shopErr) {
    console.error("Erro ao buscar lojas:", shopErr)
    return
  }

  const shopMap = new Map()
  for (const s of shops) {
    if (s.mercadopago?.access_token) {
      shopMap.set(s.id, {
        name: s.name,
        accessToken: s.mercadopago.access_token,
        baseUrl: s.mercadopago.access_token.startsWith('TEST-') 
          ? 'https://api.sandbox.mercadopago.com' 
          : 'https://api.mercadopago.com'
      })
    }
  }
  console.log(`Encontradas ${shopMap.size} lojas com Mercado Pago configurado.`)

  // Busca agendamentos suspeitos (que não estão 100% pagos, mas já confirmados/concluídos)
  let allAppts: any[] = []
  let from = 0
  const step = 1000
  let fetchMore = true

  console.log("Buscando todos os agendamentos na base (paginação infinita)...")
  while (fetchMore) {
    const { data: appts, error: apptErr } = await supabase
      .from('appointments')
      .select('id, shop_id, status, payment_status, total_payable, paid_amount, payment_id, metadata, client_name, created_at')
      .order('created_at', { ascending: false })
      .range(from, from + step - 1)

    if (apptErr) {
      console.error("Erro ao buscar agendamentos:", apptErr)
      return
    }
    
    if (appts && appts.length > 0) {
      allAppts = allAppts.concat(appts)
      from += step
      if (appts.length < step) fetchMore = false
    } else {
      fetchMore = false
    }
  }

  // Filtra em memória para pegar agendamentos que teoricamente estão "devendo" no banco
  // Já aplicando a sua regra de segurança: a discrepância SÓ É VÁLIDA se o 
  // dinheiro aprovado no Mercado Pago for MAIOR que o pago_amount no banco.
  const apptsFiltrados = allAppts.filter(a => {
    const paid = a.paid_amount || 0;
    const total = a.total_payable || 0;
    return paid < total;
  });
  
  console.log(`\nTotal de agendamentos 'confirmado'/'concluido' no histórico: ${allAppts.length}`)
  console.log(`Desse total, filtrados ${apptsFiltrados.length} que têm paid_amount < total_payable para checar na API do MP...\n`)

  const discrepancias = []

  for (let i = 0; i < apptsFiltrados.length; i++) {
    const appt = apptsFiltrados[i]
    const shop = shopMap.get(appt.shop_id)
    if (!shop) continue // Shop didn't have MP or access_token

    // Delay to avoid MP rate limiting
    await new Promise(r => setTimeout(r, 100))

    let mpPayments = []

    // 1. Procurar por external_reference = appt.id
    try {
      const searchRes = await fetch(`${shop.baseUrl}/v1/payments/search?external_reference=${appt.id}&status=approved`, {
        headers: { 'Authorization': `Bearer ${shop.accessToken}` }
      })
      if (searchRes.ok) {
        const searchData = await searchRes.json()
        if (searchData.results && searchData.results.length > 0) {
          mpPayments.push(...searchData.results)
        }
      }
    } catch (e) {
      console.error(`Erro ao buscar MP para appt ${appt.id}:`, e)
    }

    // 2. Se há um payment_id específico no banco que não veio pela busca acima
    if (appt.payment_id) {
      const alreadyFound = mpPayments.some(p => p.id.toString() === appt.payment_id.toString())
      if (!alreadyFound) {
        try {
          const pRes = await fetch(`${shop.baseUrl}/v1/payments/${appt.payment_id}`, {
            headers: { 'Authorization': `Bearer ${shop.accessToken}` }
          })
          if (pRes.ok) {
            const pData = await pRes.json()
            if (pData.status === 'approved') {
              mpPayments.push(pData)
            }
          }
        } catch (e) {}
      }
    }

    if (mpPayments.length > 0) {
      // Soma o total pago aprovado no Mercado Pago para esse agendamento
      const totalApprovedMP = mpPayments.reduce((sum, p) => sum + p.transaction_amount, 0)
      const currentPaidDB = appt.paid_amount || 0
      
      // Se MP tem mais dinheiro aprovado que o nosso banco, achamos uma discrepância
      if (totalApprovedMP > currentPaidDB) {
        discrepancias.push({
          appointment: {
            id: appt.id,
            client_name: appt.client_name,
            date: appt.date_time,
            status: appt.status,
            db_paid_amount: currentPaidDB,
            db_total_payable: appt.total_payable
          },
          mercadopago: {
            total_approved: totalApprovedMP,
            payments_found: mpPayments.map(p => ({
              id: p.id,
              status: p.status,
              amount: p.transaction_amount,
              date_approved: p.date_approved
            }))
          },
          loja: shop.name
        })
      }
    }
  }

  console.log("==================================================")
  console.log(`🚨 RESULTADO DO DRY-RUN: ${discrepancias.length} discrepâncias encontradas`)
  console.log("==================================================")

  if (discrepancias.length > 0) {
    console.log(JSON.stringify(discrepancias, null, 2))
  } else {
    console.log("Nenhuma discrepância encontrada. O banco está sincronizado com o Mercado Pago.")
  }
}

runDryRun()
