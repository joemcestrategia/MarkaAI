import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowLeft, TrendingUp, BarChart3 } from 'lucide-react'
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, PieChart, Pie, Cell, Legend } from 'recharts'
import { getTicketStatsForReports, getTicketMetrics } from '../../../services/ticketService'
import type { SupportTicket, TicketMetrics } from '../../../types/ticket.types'

const COLORS = ['#3B82F6', '#8B5CF6', '#F59E0B', '#10B981', '#6B7280', '#EF4444']

export default function SupportReportsPage() {
  const navigate = useNavigate()
  const [tickets, setTickets] = useState<SupportTicket[]>([])
  const [metrics, setMetrics] = useState<TicketMetrics | null>(null)
  const [period, setPeriod] = useState(30)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function load() {
      setLoading(true)
      const [t, m] = await Promise.all([
        getTicketStatsForReports(period),
        getTicketMetrics(period),
      ])
      setTickets(t as SupportTicket[])
      setMetrics(m)
      setLoading(false)
    }
    load()
  }, [period])

  // Category distribution
  const categoryCount: Record<string, number> = {}
  tickets.forEach(t => { categoryCount[t.category] = (categoryCount[t.category] || 0) + 1 })
  const categoryData = Object.entries(categoryCount).map(([name, value]) => ({ name, value }))

  // Status distribution
  const statusCount: Record<string, number> = {}
  tickets.forEach(t => { statusCount[t.status] = (statusCount[t.status] || 0) + 1 })
  const statusData = Object.entries(statusCount).map(([name, value]) => ({ name, value }))

  // Daily volume (last N days)
  const dailyMap: Record<string, number> = {}
  tickets.forEach(t => {
    const day = t.created_at.slice(0, 10)
    dailyMap[day] = (dailyMap[day] || 0) + 1
  })
  const dailyData = Object.entries(dailyMap)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, count]) => ({ date: date.slice(5), count }))

  // Priority distribution
  const priorityCount: Record<string, number> = {}
  tickets.forEach(t => { priorityCount[t.priority] = (priorityCount[t.priority] || 0) + 1 })
  const priorityData = Object.entries(priorityCount).map(([name, value]) => ({ name, value }))

  const PRIORITY_COLORS: Record<string, string> = {
    critical: '#EF4444',
    high: '#F59E0B',
    medium: '#3B82F6',
    low: '#10B981',
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-6xl mx-auto px-4 py-6">
        <button onClick={() => navigate('/admin/support')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
          <ArrowLeft size={16} /> Voltar
        </button>
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center gap-2">
            <BarChart3 className="text-brand-600" size={24} />
            <h1 className="text-2xl font-bold text-gray-900">Relatórios de Suporte</h1>
          </div>
          <select
            value={period}
            onChange={e => setPeriod(Number(e.target.value))}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
          >
            <option value={7}>Últimos 7 dias</option>
            <option value={30}>Últimos 30 dias</option>
            <option value={90}>Últimos 90 dias</option>
          </select>
        </div>

        {loading ? (
          <div className="flex justify-center py-16">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
          </div>
        ) : (
          <>
            {/* KPI Cards */}
            {metrics && (
              <div className="grid grid-cols-2 md:grid-cols-5 gap-3 mb-6">
                {[
                  { label: 'Total de tickets', value: tickets.length, color: 'text-gray-900' },
                  { label: 'Críticos abertos', value: metrics.criticalOpen, color: 'text-red-600' },
                  { label: 'Abertos hoje', value: metrics.openedToday, color: 'text-blue-600' },
                  { label: 'TMA (h)', value: metrics.avgResponseTimeHours, color: 'text-amber-600' },
                  { label: 'Taxa SLA', value: `${metrics.slaCompliancePercent}%`, color: 'text-green-600' },
                ].map((m, i) => (
                  <div key={i} className="bg-white rounded-xl border border-gray-200 p-4">
                    <p className="text-xs text-gray-500">{m.label}</p>
                    <p className={`text-2xl font-bold ${m.color}`}>{m.value}</p>
                  </div>
                ))}
              </div>
            )}

            {/* Charts */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              {/* Daily volume */}
              <div className="bg-white rounded-xl border border-gray-200 p-5">
                <h3 className="text-sm font-semibold text-gray-700 mb-4 flex items-center gap-1.5">
                  <TrendingUp size={16} /> Volume diário
                </h3>
                <ResponsiveContainer width="100%" height={250}>
                  <BarChart data={dailyData}>
                    <XAxis dataKey="date" fontSize={11} />
                    <YAxis fontSize={11} allowDecimals={false} />
                    <Tooltip />
                    <Bar dataKey="count" fill="#3B82F6" radius={[4, 4, 0, 0]} />
                  </BarChart>
                </ResponsiveContainer>
              </div>

              {/* Category pie */}
              <div className="bg-white rounded-xl border border-gray-200 p-5">
                <h3 className="text-sm font-semibold text-gray-700 mb-4">Por Categoria</h3>
                <ResponsiveContainer width="100%" height={250}>
                  <PieChart>
                    <Pie data={categoryData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={80} label>
                      {categoryData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                    </Pie>
                    <Legend fontSize={12} />
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </div>

              {/* Status pie */}
              <div className="bg-white rounded-xl border border-gray-200 p-5">
                <h3 className="text-sm font-semibold text-gray-700 mb-4">Por Status</h3>
                <ResponsiveContainer width="100%" height={250}>
                  <PieChart>
                    <Pie data={statusData} dataKey="value" nameKey="name" cx="50%" cy="50%" outerRadius={80} label>
                      {statusData.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
                    </Pie>
                    <Legend fontSize={12} />
                    <Tooltip />
                  </PieChart>
                </ResponsiveContainer>
              </div>

              {/* Priority bar */}
              <div className="bg-white rounded-xl border border-gray-200 p-5">
                <h3 className="text-sm font-semibold text-gray-700 mb-4">Por Prioridade</h3>
                <ResponsiveContainer width="100%" height={250}>
                  <BarChart data={priorityData} layout="vertical">
                    <XAxis type="number" fontSize={11} allowDecimals={false} />
                    <YAxis dataKey="name" type="category" fontSize={11} width={60} />
                    <Tooltip />
                    <Bar dataKey="value" radius={[0, 4, 4, 0]}>
                      {priorityData.map((entry, i) => <Cell key={i} fill={PRIORITY_COLORS[entry.name] ?? '#6B7280'} />)}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
