import { formatDistanceToNow, differenceInMilliseconds, isPast } from 'date-fns'
import { ptBR } from 'date-fns/locale'
import type { TicketPriority } from '../types/ticket.types'

export function getSLAHoursByPriority(priority: TicketPriority): number {
  switch (priority) {
    case 'critical': return 2
    case 'high':     return 8
    case 'medium':   return 24
    case 'low':      return 72
    default:         return 24
  }
}

export function isSLABreached(slaDeadline: string | null): boolean {
  if (!slaDeadline) return false
  return isPast(new Date(slaDeadline))
}

export function getSLARemainingPercent(createdAt: string, slaDeadline: string | null): number {
  if (!slaDeadline) return 100
  const start = new Date(createdAt).getTime()
  const end = new Date(slaDeadline).getTime()
  const now = Date.now()
  const total = end - start
  if (total <= 0) return 0
  const remaining = end - now
  return Math.max(0, Math.min(100, (remaining / total) * 100))
}

export function formatSLARemaining(slaDeadline: string | null): string {
  if (!slaDeadline) return '—'
  const deadline = new Date(slaDeadline)
  if (isPast(deadline)) return 'SLA vencido'
  return formatDistanceToNow(deadline, { addSuffix: false, locale: ptBR })
}

export function getSLAColor(slaDeadline: string | null, createdAt: string): 'red' | 'amber' | 'green' {
  if (!slaDeadline) return 'green'
  if (isSLABreached(slaDeadline)) return 'red'
  const pct = getSLARemainingPercent(createdAt, slaDeadline)
  if (pct < 20) return 'amber'
  return 'green'
}
