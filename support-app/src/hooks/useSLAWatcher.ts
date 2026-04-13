import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import type { SupportTicket } from '../types/ticket.types'

export function useSLAWatcher() {
  const [urgentTickets, setUrgentTickets] = useState<SupportTicket[]>([])

  useEffect(() => {
    async function check() {
      const now = new Date()
      const soon = new Date(now.getTime() + 30 * 60 * 1000) // +30 min

      const { data } = await supabase
        .from('support_tickets')
        .select('*')
        .in('status', ['open', 'in_progress'])
        .lte('sla_deadline', soon.toISOString())
        .order('sla_deadline', { ascending: true })

      setUrgentTickets(data ?? [])
    }

    check()
    const interval = setInterval(check, 60_000)
    return () => clearInterval(interval)
  }, [])

  return urgentTickets
}
