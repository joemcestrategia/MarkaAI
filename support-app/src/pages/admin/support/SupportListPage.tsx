import { useEffect, useState, useCallback } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { Plus, Download, Search, X, AlertTriangle, MessageSquareText, BarChart3 } from 'lucide-react'
import toast from 'react-hot-toast'
import { formatDistanceToNow } from 'date-fns'
import { ptBR } from 'date-fns/locale'
import {
  getAdminTickets,
  getTicketMetrics,
  assignTicketToMe,
  updateTicket,
} from '../../../services/ticketService'
import { useAuth } from '../../../hooks/useAuth'
import { useTicketRealtime } from '../../../hooks/useTicketRealtime'
import { useSLAWatcher } from '../../../hooks/useSLAWatcher'
import type { SupportTicket, TicketFilters, TicketMetrics, TicketStatus, TicketPriority, TicketCategory, TicketSource } from '../../../types/ticket.types'
import StatusBadge from '../../../components/support/shared/StatusBadge'
import PriorityBadge from '../../../components/support/shared/PriorityBadge'
import CategoryBadge from '../../../components/support/shared/CategoryBadge'
import SLABadge from '../../../components/support/shared/SLABadge'
import SourceBadge from '../../../components/support/shared/SourceBadge'
import { isSLABreached, getSLARemainingPercent } from '../../../utils/ticketSLA'

const STATUS_OPTIONS: { key: TicketStatus; label: string }[] = [
  { key: 'open', label: 'Aberto' },
  { key: 'in_progress', label: 'Em Atendimento' },
  { key: 'waiting_client', label: 'Aguardando Cliente' },
  { key: 'resolved', label: 'Resolvido' },
  { key: 'closed', label: 'Fechado' },
]

export default function SupportListPage() {
  const navigate = useNavigate()
  const { user, isAdmin } = useAuth()
  const [tickets, setTickets] = useState<SupportTicket[]>([])
  const [metrics, setMetrics] = useState<TicketMetrics | null>(null)
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState<TicketStatus[]>([])
  const [page, setPage] = useState(0)
  const urgentTickets = useSLAWatcher()

  const loadData = useCallback(async () => {
    try {
      const filters: TicketFilters = {}
      if (search) filters.search = search
      if (statusFilter.length) filters.status = statusFilter
      const [t, m] = await Promise.all([getAdminTickets(filters), getTicketMetrics()])
      setTickets(t)
      setMetrics(m)
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }, [search, statusFilter])

  useEffect(() => { loadData() }, [loadData])

  useTicketRealtime({
    context: 'admin',
    onTicketChange: loadData,
    onNewMessage: loadData,
  })

  const handleAssignToMe = async (ticketId: string) => {
    try {
      await assignTicketToMe(ticketId)
      toast.success('Ticket atribuído a você.')
      loadData()
    } catch { toast.error('Erro ao atribuir.') }
  }

  const handleStatusChange = async (ticketId: string, status: TicketStatus) => {
    try {
      await updateTicket(ticketId, { status })
      loadData()
    } catch { toast.error('Erro ao atualizar status.') }
  }

  const paged = tickets.slice(page * 25, (page + 1) * 25)
  const totalPages = Math.ceil(tickets.length / 25)

  if (!isAdmin) {
    return <div className="min-h-screen flex items-center justify-center"><p className="text-red-500 font-medium">Acesso restrito a administradores.</p></div>
  }

  return (
    <div className="min-h-screen bg-gray-50">
      {/* SLA urgent banner */}
      {urgentTickets.length > 0 && (
        <div className="bg-red-50 border-b border-red-200 px-4 py-3">
          <div className="max-w-7xl mx-auto flex items-center gap-2">
            <AlertTriangle className="text-red-500 shrink-0" size={18} />
            <span className="text-sm font-medium text-red-700">
              {urgentTickets.length} ticket(s) com SLA prestes a vencer:
            </span>
            {urgentTickets.slice(0, 5).map(t => (
              <Link key={t.id} to={`/admin/support/${t.id}`} className="text-sm text-red-600 hover:underline font-mono">
                #{t.ticket_number}
              </Link>
            ))}
          </div>
        </div>
      )}

      <div className="max-w-7xl mx-auto px-4 py-6">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold text-gray-900">Fila de Suporte</h1>
          <div className="flex gap-2">
            <Link to="/admin/support/relatorios" className="inline-flex items-center gap-1.5 px-3 py-2 border border-gray-300 rounded-lg text-sm text-gray-600 hover:bg-gray-50 transition">
              <BarChart3 size={14} /> Relatórios
            </Link>
            <Link to="/admin/support/novo" className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 transition">
              <Plus size={14} /> Novo Ticket
            </Link>
          </div>
        </div>

        {/* Metrics bar */}
        {metrics && (
          <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 mb-6">
            {[
              { label: 'Críticos abertos', value: metrics.criticalOpen, color: 'text-red-600' },
              { label: 'Com resposta nova', value: metrics.unreadFromClient, color: 'text-amber-600' },
              { label: 'Abertos hoje', value: metrics.openedToday, color: 'text-blue-600' },
              { label: 'TMA (h)', value: metrics.avgResponseTimeHours, color: 'text-gray-700' },
              { label: 'Taxa SLA', value: `${metrics.slaCompliancePercent}%`, color: 'text-green-600' },
            ].map((m, i) => (
              <div key={i} className="bg-white rounded-xl border border-gray-200 p-4">
                <p className="text-xs text-gray-500">{m.label}</p>
                <p className={`text-2xl font-bold ${m.color}`}>{m.value}</p>
              </div>
            ))}
          </div>
        )}

        {/* Filters */}
        <div className="flex flex-wrap items-center gap-3 mb-4">
          <div className="relative flex-1 min-w-[200px]">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" size={16} />
            <input
              type="text"
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Buscar por título, loja ou #número..."
              className="w-full pl-9 pr-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-brand-500 focus:border-brand-500 outline-none"
            />
          </div>
          <div className="flex gap-1 flex-wrap">
            {STATUS_OPTIONS.map(s => {
              const active = statusFilter.includes(s.key)
              return (
                <button
                  key={s.key}
                  onClick={() => setStatusFilter(prev => active ? prev.filter(x => x !== s.key) : [...prev, s.key])}
                  className={`px-3 py-1.5 rounded-full text-xs font-medium border transition ${active ? 'bg-brand-600 text-white border-brand-600' : 'bg-white text-gray-600 border-gray-300 hover:border-gray-400'}`}
                >
                  {s.label}
                </button>
              )
            })}
            {statusFilter.length > 0 && (
              <button onClick={() => setStatusFilter([])} className="px-2 py-1.5 text-xs text-gray-400 hover:text-gray-600">
                <X size={14} />
              </button>
            )}
          </div>
        </div>

        {/* Table */}
        {loading ? (
          <div className="flex justify-center py-16"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" /></div>
        ) : (
          <div className="bg-white rounded-xl border border-gray-200 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="bg-gray-50 border-b border-gray-200">
                    <th className="text-left px-4 py-3 font-medium text-gray-500">ID</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-500">Assunto</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-500">Prioridade</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-500">Categoria</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-500">Status</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-500">Fonte</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-500">SLA</th>
                    <th className="text-left px-4 py-3 font-medium text-gray-500">Ações</th>
                  </tr>
                </thead>
                <tbody>
                  {paged.map(ticket => {
                    const breached = isSLABreached(ticket.sla_deadline)
                    const pct = getSLARemainingPercent(ticket.created_at, ticket.sla_deadline)
                    const borderColor = breached ? 'border-l-4 border-l-red-500' : pct < 20 ? 'border-l-4 border-l-amber-400' : 'border-l-4 border-l-transparent'
                    const rowBg = ticket.priority === 'critical' ? 'bg-red-50/50' : ''
                    return (
                      <tr
                        key={ticket.id}
                        onClick={() => navigate(`/admin/support/${ticket.id}`)}
                        className={`border-b border-gray-100 cursor-pointer hover:bg-gray-50 transition ${borderColor} ${rowBg}`}
                      >
                        <td className="px-4 py-3">
                          <div className="flex items-center gap-1.5">
                            {ticket.has_unread_admin && (
                              <MessageSquareText size={14} className="text-brand-500" />
                            )}
                            <span className="font-mono text-gray-500">#{ticket.ticket_number}</span>
                          </div>
                        </td>
                        <td className="px-4 py-3 max-w-[250px]">
                          <p className={`truncate ${ticket.has_unread_admin ? 'font-bold text-gray-900' : 'text-gray-700'}`}>{ticket.title}</p>
                          <p className="text-xs text-gray-400 truncate">{ticket.shop_name} · {formatDistanceToNow(new Date(ticket.created_at), { addSuffix: true, locale: ptBR })}</p>
                        </td>
                        <td className="px-4 py-3"><PriorityBadge priority={ticket.priority} /></td>
                        <td className="px-4 py-3"><CategoryBadge category={ticket.category} /></td>
                        <td className="px-4 py-3"><StatusBadge status={ticket.status} context="admin" /></td>
                        <td className="px-4 py-3"><SourceBadge source={ticket.source} /></td>
                        <td className="px-4 py-3"><SLABadge slaDeadline={ticket.sla_deadline} createdAt={ticket.created_at} /></td>
                        <td className="px-4 py-3" onClick={e => e.stopPropagation()}>
                          <div className="flex gap-1">
                            <button
                              onClick={() => handleAssignToMe(ticket.id)}
                              className="text-xs text-brand-600 hover:underline whitespace-nowrap"
                            >
                              Atribuir a mim
                            </button>
                          </div>
                        </td>
                      </tr>
                    )
                  })}
                  {paged.length === 0 && (
                    <tr><td colSpan={8} className="text-center py-12 text-gray-400">Nenhum ticket encontrado.</td></tr>
                  )}
                </tbody>
              </table>
            </div>
            {/* Pagination */}
            {totalPages > 1 && (
              <div className="flex items-center justify-between px-4 py-3 border-t border-gray-200">
                <span className="text-xs text-gray-500">{tickets.length} tickets</span>
                <div className="flex gap-1">
                  {Array.from({ length: totalPages }, (_, i) => (
                    <button key={i} onClick={() => setPage(i)} className={`px-3 py-1 rounded text-xs ${page === i ? 'bg-brand-600 text-white' : 'text-gray-500 hover:bg-gray-100'}`}>
                      {i + 1}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}
