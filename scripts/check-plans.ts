import { createClient } from 'npm:@supabase/supabase-js'

const supabaseUrl = Deno.env.get('SUPABASE_URL')
const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

if (!supabaseUrl || !supabaseKey) {
  console.error('Faltam variáveis de ambiente')
  Deno.exit(1)
}

const supabase = createClient(supabaseUrl, supabaseKey)

async function main() {
  const { data, error } = await supabase.rpc('query_plan_counts', {})
  
  if (error) {
    // Se não tiver RPC, vamos buscar tudo e contar em memória
    console.log("RPC não existe, buscando todos os shops...")
    const { data: shops, error: shopsErr } = await supabase.from('shops').select('plan_id').not('plan_id', 'is', null)
    if (shopsErr) {
        console.error(shopsErr)
        return
    }
    const counts = shops.reduce((acc: Record<string, number>, shop: any) => {
        const p = shop.plan_id;
        acc[p] = (acc[p] || 0) + 1;
        return acc;
    }, {});
    console.log("=== RESULTADO DA CONTAGEM (EM MEMÓRIA) ===")
    console.table(counts)
  } else {
    console.log("=== RESULTADO DA CONTAGEM (RPC) ===")
    console.table(data)
  }
}

main()
