import type { TicketCategory } from '../../../types/ticket.types'
import { Calendar, CreditCard, MessageSquare, Receipt, KeyRound, HelpCircle } from 'lucide-react'

const CATEGORY_CONFIG: Record<TicketCategory, { label: string; icon: typeof Calendar; color: string }> = {
  scheduling: { label: 'Agendamentos', icon: Calendar, color: 'text-blue-600' },
  payment:    { label: 'Pagamentos', icon: CreditCard, color: 'text-green-600' },
  whatsapp:   { label: 'WhatsApp', icon: MessageSquare, color: 'text-emerald-600' },
  nfse:       { label: 'NFS-e', icon: Receipt, color: 'text-orange-600' },
  account:    { label: 'Conta e Acesso', icon: KeyRound, color: 'text-red-600' },
  other:      { label: 'Outro', icon: HelpCircle, color: 'text-gray-600' },
}

interface Props {
  category: TicketCategory
  showIcon?: boolean
}

export default function CategoryBadge({ category, showIcon = true }: Props) {
  const cfg = CATEGORY_CONFIG[category]
  const Icon = cfg.icon
  return (
    <span className={`inline-flex items-center gap-1 text-xs font-medium ${cfg.color}`}>
      {showIcon && <Icon size={14} />}
      {cfg.label}
    </span>
  )
}

export { CATEGORY_CONFIG }
