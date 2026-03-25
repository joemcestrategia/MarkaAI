import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseAdminClient } from '../_shared/supabase.ts'

const fetchFeriadosNacionais = async (ano: number) => {
  try {
    const res = await fetch(`https://brasilapi.com.br/api/feriados/v1/${ano}`)
    if (!res.ok) return []
    return await res.json()
  } catch (error) {
    console.error('Erro buscando feriados BrasilAPI:', error)
    return []
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseAdminClient()
    const hoje = new Date()
    const hojeISO = hoje.toISOString().split("T")[0]

    // Fetch eligible shops
    const { data: shops, error: fetchError } = await supabase
      .from('shops')
      .select('id, plan, status, dias_agenda_padrao, dias_extras_vip, feriados_personalizados, feriados_configurados')
      .in('plan', ['plus', 'pro'])

    if (fetchError || !shops || shops.length === 0) {
      console.log("[feriados] Nenhum salão elegível encontrado.")
      return new Response(JSON.stringify({ message: "Nenhum salão elegível encontrado." }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const yearlyHolidays: Record<number, any[]> = {}

    for (const shop of shops) {
      if (shop.status !== "ativo" && shop.status !== "active") continue

      const diasAgenda = shop.dias_agenda_padrao || 30
      const diasVip = shop.dias_extras_vip || 0
      const totalRadar = diasAgenda + diasVip

      const dataFim = new Date()
      dataFim.setDate(hoje.getDate() + totalRadar)
      const dataFimISO = dataFim.toISOString().split("T")[0]

      const anosNecessarios = [hoje.getFullYear(), dataFim.getFullYear()]
      const anosUnicos = [...new Set(anosNecessarios)]

      let todosFeriados: any[] = []

      for (const ano of anosUnicos) {
        if (!yearlyHolidays[ano]) {
          yearlyHolidays[ano] = await fetchFeriadosNacionais(ano)
        }
        todosFeriados = todosFeriados.concat(yearlyHolidays[ano])
      }

      if (shop.plan === "pro" && Array.isArray(shop.feriados_personalizados)) {
        todosFeriados = todosFeriados.concat(shop.feriados_personalizados)
      }

      const configurados = shop.feriados_configurados || {}
      const feriadosPendentes: string[] = []

      for (const feriado of todosFeriados) {
        if (!feriado || !feriado.date) continue
        
        const fDate = feriado.date
        const dentroJanela = fDate >= hojeISO && fDate <= dataFimISO
        const pendente = !(fDate in configurados)

        if (dentroJanela && pendente) {
          feriadosPendentes.push(fDate)
        }
      }

      // Ensure distinct dates in pending array
      const pendentesUnicos = [...new Set(feriadosPendentes)]

      await supabase.from('shops').update({
        feriados_pendentes: pendentesUnicos,
        feriados_pendentes_updated_at: new Date().toISOString()
      }).eq('id', shop.id)
    }

    console.log(`[feriados] Processamento concluído para ${shops.length} salões.`)
    return new Response(JSON.stringify({ success: true, processed: shops.length }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    console.error("[feriados] Erro geral na execução:", error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
