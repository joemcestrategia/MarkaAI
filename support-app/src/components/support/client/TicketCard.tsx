import { useNavigate } from 'react-router-dom'
import { formatDistanceToNow } from 'date-fns'
import { ptBR } from 'date-fns/locale'
import { MessageSquare } from 'lucide-react'
import type { SupportTicket } from '../../../types/ticket.types'
import StatusBadge from '../shared/StatusBadge'
import CategoryBadge from '../shared/CategoryBadge'

interface Props {
  ticket: SupportTicket
}

export default function TicketCard({ ticket }: Props) {
  const navigate = useNavigate()
  const timeAgo = formatDistanceToNow(new Date(ticket.created_at), { addSuffix: true, locale: ptBR })

  return (
    <div
      onClick={() => navigate(`/app/suporte/${ticket.id}`)}
      className={`relative bg-white rounded-xl border p-4 cursor-pointer hover:shadow-md transition group ${
        ticket.has_unread_client ? 'border-brand-300 bg-brand-50/30' : 'border-gray-200'
      }`}
    >
      {ticket.has_unread_client && (
        <span className="absolute top-3 right-3 flex h-2.5 w-2.5">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-brand-400 opacity-75" />
          <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-brand-500" />
        </span>
      )}

      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs font-mono text-gray-400">#{ticket.ticket_number}</span>
            <StatusBadge status={ticket.status} context="client" />
          </div>
          <h3 className={`text-sm font-semibold text-gray-900 truncate ${ticket.has_unread_client ? 'font-bold' : ''}`}>
            {ticket.title}
          </h3>
          <div className="flex items-center gap-3 mt-2">
            <CategoryBadge category={ticket.category} />
            <span className="text-xs text-gray-400">{timeAgo}</span>
          </div>
        </div>
      </div>

      {ticket.has_unread_client && (
        <div className="mt-2 flex items-center gap-1 text-xs text-brand-600 font-medium">
          <MessageSquare size={12} />
          Nova resposta
        </div>
      )}
    </div>
  )
}
