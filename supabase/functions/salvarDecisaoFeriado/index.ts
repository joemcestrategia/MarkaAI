import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseClient(req)
    
    // Auth Check
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Usuário não autenticado' }), { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { shop_id, date, configuration } = await req.json()

    if (!shop_id || !date || !configuration) {
      return new Response(JSON.stringify({ error: 'Parâmetros incompletos' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { data: shopDoc, error: fetchError } = await supabase
      .from('shops')
      .select('configured_holidays, pending_holidays')
      .eq('id', shop_id)
      .single()

    if (fetchError || !shopDoc) {
      return new Response(JSON.stringify({ error: 'Loja não encontrada' }), { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Merge logic
    const configured = shopDoc.configured_holidays || {}
    configured[date] = {
      decision: configuration.decision,
      rewritten_hours: configuration.decision === "abrir_horarios" ? configuration.hours : null,
      updated_at: new Date().toISOString(),
      updated_by: user.id
    }

    let pending = Array.isArray(shopDoc.pending_holidays) ? shopDoc.pending_holidays : []
    pending = pending.filter((d: string) => d !== date)

    const { error: updateError } = await supabase.from('shops').update({
      configured_holidays: configured,
      pending_holidays: pending
    }).eq('id', shop_id)

    if (updateError) throw updateError

    return new Response(JSON.stringify({ success: true, message: 'Decisão do feriado salva com sucesso.' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    console.error('Error salvarDecisaoFeriado:', error)
    return new Response(JSON.stringify({ error: error.message }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
