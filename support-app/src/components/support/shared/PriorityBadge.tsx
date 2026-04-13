import type { TicketPriority } from '../../../types/ticket.types'
import { PRIORITY_CONFIG } from '../../../utils/ticketPriority'

interface Props {
  priority: TicketPriority
}

export default function PriorityBadge({ priority }: Props) {
  const cfg = PRIORITY_CONFIG[priority]
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-0.5 rounded-full text-xs font-medium ${cfg.bg} ${cfg.color}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${cfg.dot}`} />
      {cfg.label}
    </span>
  )
}
