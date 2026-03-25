import { serve } from 'https://deno.land/std@0.208.0/http/server.ts'
import { corsHeaders } from '../_shared/cors.ts'
import { createSupabaseClient } from '../_shared/supabase.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createSupabaseClient(req)

    // Ensure the user is authenticated
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()

    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Usuário não autenticado' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { professional_id, start_time, duration } = await req.json()

    if (!professional_id || !start_time || !duration) {
      return new Response(
        JSON.stringify({ error: 'Dados incompletos para validação' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const reqStart = new Date(start_time)
    const reqEnd = new Date(reqStart.getTime() + duration * 60000)

    // Fetch appointments for the professional that might conflict
    const { data: appointments, error: fetchError } = await supabase
      .from('appointments')
      .select('scheduled_at, duration_min')
      .eq('professional_id', professional_id)
      .not('status', 'in', '("cancelado","rejeitado","excluido")')
      // Optimisation: only fetch appointments around the requested date
      .gte('scheduled_at', new Date(reqStart.getTime() - 24 * 60 * 60 * 1000).toISOString())
      .lte('scheduled_at', new Date(reqEnd.getTime() + 24 * 60 * 60 * 1000).toISOString())

    if (fetchError) {
      console.error('Database fetch error:', fetchError)
      throw new Error('Erro ao buscar agendamentos')
    }

    const conflicting = (appointments || []).filter((appt) => {
      if (!appt.scheduled_at) return false

      const apptStart = new Date(appt.scheduled_at)
      const apptDuration = appt.duration_min || 30
      const apptEnd = new Date(apptStart.getTime() + apptDuration * 60000)

      return reqStart < apptEnd && reqEnd > apptStart
    })

    return new Response(
      JSON.stringify({
        available: conflicting.length === 0,
        conflicts: conflicting.length,
      }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  } catch (error) {
    console.error('Erro em checkAvailability:', error)
    return new Response(
      JSON.stringify({ error: 'Erro interno ao validar disponibilidade' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )
  }
})
