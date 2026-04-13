import type { TicketStatus } from '../../../types/ticket.types'

const CLIENT_LABELS: Record<TicketStatus, string> = {
  open: 'Aguardando atendimento',
  in_progress: 'Em atendimento',
  waiting_client: 'Aguardando sua resposta',
  resolved: 'Resolvido',
  closed: 'Encerrado',
}

const ADMIN_LABELS: Record<TicketStatus, string> = {
  open: 'Aberto',
  in_progress: 'Em Atendimento',
  waiting_client: 'Aguardando Cliente',
  resolved: 'Resolvido',
  closed: 'Fechado',
}

const STATUS_STYLES: Record<TicketStatus, string> = {
  open: 'bg-blue-100 text-blue-800',
  in_progress: 'bg-purple-100 text-purple-800',
  waiting_client: 'bg-amber-100 text-amber-800',
  resolved: 'bg-green-100 text-green-800',
  closed: 'bg-gray-100 text-gray-600',
}

interface Props {
  status: TicketStatus
  context?: 'client' | 'admin'
  pulse?: boolean
}

export default function StatusBadge({ status, context = 'admin', pulse }: Props) {
  const labels = context === 'client' ? CLIENT_LABELS : ADMIN_LABELS
  const isWaiting = status === 'waiting_client' && context === 'client'

  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium ${STATUS_STYLES[status]} ${isWaiting ? 'ring-2 ring-amber-300' : ''}`}>
      {(pulse || isWaiting) && (
        <span className="relative flex h-2 w-2">
          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75" />
          <span className="relative inline-flex rounded-full h-2 w-2 bg-amber-500" />
        </span>
      )}
      {labels[status]}
    </span>
  )
}
