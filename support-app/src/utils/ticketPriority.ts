import type { TicketCategory, TicketPriority } from '../types/ticket.types'

export function getDefaultPriorityByCategory(category: TicketCategory): TicketPriority {
  switch (category) {
    case 'payment':
    case 'nfse':
    case 'account':
      return 'high'
    case 'scheduling':
    case 'whatsapp':
      return 'medium'
    case 'other':
    default:
      return 'low'
  }
}

export const PRIORITY_CONFIG: Record<TicketPriority, { label: string; color: string; bg: string; dot: string; order: number }> = {
  critical: { label: 'Crítico', color: 'text-red-700', bg: 'bg-red-50', dot: 'bg-red-500', order: 0 },
  high:     { label: 'Alto',    color: 'text-amber-700', bg: 'bg-amber-50', dot: 'bg-amber-500', order: 1 },
  medium:   { label: 'Médio',   color: 'text-blue-700', bg: 'bg-blue-50', dot: 'bg-blue-500', order: 2 },
  low:      { label: 'Baixo',   color: 'text-green-700', bg: 'bg-green-50', dot: 'bg-green-500', order: 3 },
}
