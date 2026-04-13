import { Clock } from 'lucide-react'
import { formatSLARemaining, getSLAColor, getSLARemainingPercent } from '../../../utils/ticketSLA'

interface Props {
  slaDeadline: string | null
  createdAt: string
  showBar?: boolean
}

export default function SLABadge({ slaDeadline, createdAt, showBar = false }: Props) {
  const color = getSLAColor(slaDeadline, createdAt)
  const remaining = formatSLARemaining(slaDeadline)
  const pct = getSLARemainingPercent(createdAt, slaDeadline)

  const colorMap = {
    red: { text: 'text-red-700', bg: 'bg-red-100', bar: 'bg-red-500' },
    amber: { text: 'text-amber-700', bg: 'bg-amber-100', bar: 'bg-amber-500' },
    green: { text: 'text-green-700', bg: 'bg-green-100', bar: 'bg-green-500' },
  }

  const c = colorMap[color]

  return (
    <div className="flex flex-col gap-1">
      <span className={`inline-flex items-center gap-1 text-xs font-medium ${c.text}`}>
        <Clock size={12} />
        {remaining}
      </span>
      {showBar && (
        <div className={`w-full h-1.5 rounded-full ${c.bg}`}>
          <div className={`h-full rounded-full ${c.bar} transition-all`} style={{ width: `${pct}%` }} />
        </div>
      )}
    </div>
  )
}
