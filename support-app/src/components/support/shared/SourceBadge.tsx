import type { TicketSource } from '../../../types/ticket.types'
import { Monitor, PenLine, Mail, MessageCircle } from 'lucide-react'

const SOURCE_CONFIG: Record<TicketSource, { label: string; icon: typeof Monitor }> = {
  client_portal: { label: 'Portal', icon: Monitor },
  manual:        { label: 'Manual', icon: PenLine },
  email:         { label: 'E-mail', icon: Mail },
  whatsapp:      { label: 'WhatsApp', icon: MessageCircle },
}

interface Props {
  source: TicketSource
}

export default function SourceBadge({ source }: Props) {
  const cfg = SOURCE_CONFIG[source]
  const Icon = cfg.icon
  return (
    <span className="inline-flex items-center gap-1 text-xs text-gray-500">
      <Icon size={12} />
      {cfg.label}
    </span>
  )
}
