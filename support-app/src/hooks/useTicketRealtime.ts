import { useEffect } from 'react'
import { supabase } from '../lib/supabase'
import toast from 'react-hot-toast'

interface RealtimeOptions {
  context: 'client' | 'admin'
  shopId?: string | null
  onTicketChange?: () => void
  onNewMessage?: () => void
}

export function useTicketRealtime({ context, shopId, onTicketChange, onNewMessage }: RealtimeOptions) {
  useEffect(() => {
    const channels: ReturnType<typeof supabase.channel>[] = []

    // Listen for ticket changes
    const ticketChannel = supabase
      .channel('support_tickets_realtime')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'support_tickets' },
        (payload) => {
          const ticket = payload.new as any

          if (context === 'admin') {
            if (payload.eventType === 'INSERT') {
              const priority = ticket?.priority
              const style = priority === 'critical'
                ? { style: { background: '#FEE2E2', borderLeft: '4px solid #EF4444' } }
                : {}
              toast(`Novo ticket #${ticket?.ticket_number} — ${ticket?.shop_name ?? 'Sem loja'} — ${priority?.toUpperCase()}`, style)
            }
          }

          if (context === 'client' && ticket) {
            const old = payload.old as any
            if (old?.status !== ticket.status) {
              const statusLabels: Record<string, string> = {
                in_progress: 'Em Atendimento',
                resolved: 'Resolvido',
                waiting_client: 'Aguardando sua resposta',
                closed: 'Encerrado',
              }
              const label = statusLabels[ticket.status] ?? ticket.status
              toast(`Seu chamado #${ticket.ticket_number} foi atualizado para: ${label}`)
            }
          }

          onTicketChange?.()
        }
      )
      .subscribe()
    channels.push(ticketChannel)

    // Listen for new messages
    const msgChannel = supabase
      .channel('ticket_messages_realtime')
      .on(
        'postgres_changes',
        { event: 'INSERT', schema: 'public', table: 'ticket_messages' },
        (payload) => {
          const msg = payload.new as any
          if (context === 'admin' && msg?.author_role === 'client') {
            toast(`Nova mensagem do cliente no ticket`)
          }
          if (context === 'client' && msg?.author_role !== 'client' && !msg?.is_internal) {
            toast(`Nova resposta no seu chamado`)
          }
          onNewMessage?.()
        }
      )
      .subscribe()
    channels.push(msgChannel)

    return () => {
      channels.forEach(ch => supabase.removeChannel(ch))
    }
  }, [context, shopId])
}
