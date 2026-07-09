import { createClient } from 'npm:@supabase/supabase-js'
import Stripe from 'npm:stripe'

const supabaseUrl = Deno.env.get('SUPABASE_URL')
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
const stripeKey = Deno.env.get('STRIPE_SECRET_KEY')

if (!supabaseUrl || !supabaseKey || !stripeKey) {
  console.error('Faltam variáveis de ambiente (SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, STRIPE_SECRET_KEY)')
  Deno.exit(1)
}

const supabase = createClient(supabaseUrl, supabaseKey)
const stripe = new Stripe(stripeKey, {
  apiVersion: '2023-10-16',
})

async function main() {
  console.log('Iniciando reconciliação retroativa das datas de assinatura da Stripe...')

  // Busca apenas os shops que têm uma assinatura Stripe ativa ou cancelada mas com ID
  const { data: shops, error } = await supabase
    .from('shops')
    .select('id, subscription')
    .not('subscription->stripe_subscription_id', 'is', null)

  if (error) {
    console.error('Erro ao buscar shops:', error)
    return
  }

  console.log(`Encontrados ${shops.length} shops com stripe_subscription_id. Sincronizando...`)

  let successCount = 0
  let errorCount = 0

  for (const shop of shops) {
    const subId = shop.subscription?.stripe_subscription_id
    if (!subId) continue

    try {
      const stripeSub = await stripe.subscriptions.retrieve(subId)
      
      const startedAt = new Date(stripeSub.start_date * 1000).toISOString()
      const currentPeriodEnd = new Date(stripeSub.current_period_end * 1000).toISOString()
      const cancelAtPeriodEnd = stripeSub.cancel_at_period_end

      await supabase.from('shops').update({
        subscription_started_at: startedAt,
        current_period_end: currentPeriodEnd,
        cancel_at_period_end: cancelAtPeriodEnd,
        has_used_trial: true // Definitivo
      }).eq('id', shop.id)

      console.log(`✅ Shop ${shop.id} sincronizado. Started At: ${startedAt}`)
      successCount++
    } catch (e: any) {
      if (e.code === 'resource_missing') {
        console.log(`⚠️ Shop ${shop.id}: Assinatura ${subId} não encontrada na Stripe. Ignorando atualização de datas.`)
      } else {
        console.error(`❌ Erro no shop ${shop.id}:`, e.message)
      }
      errorCount++
    }
  }

  console.log(`\n🎉 Concluído! Sucessos: ${successCount} | Erros/Não encontrados: ${errorCount}`)
}

main()
