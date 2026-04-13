import { useEffect, useState, useRef } from 'react'
import { useParams, useNavigate, Link } from 'react-router-dom'
import { ArrowLeft, Send, CheckCircle, XCircle, Lock, ChevronDown } from 'lucide-react'
import toast from 'react-hot-toast'
import { formatDistanceToNow } from 'date-fns'
import { ptBR } from 'date-fns/locale'
import {
  getAdminTicketById,
  getTicketMessages,
  getTicketHistory,
  sendAdminMessage,
  updateTicket,
  markAdminTicketRead,
  getAdminUsers,
  getAllTags,
  getTicketTags,
  setTicketTags,
} from '../../../services/ticketService'
import { useAuth } from '../../../hooks/useAuth'
import { useTicketRealtime } from '../../../hooks/useTicketRealtime'
import type { SupportTicket, TicketMessage, TicketHistory, TicketTag, TicketStatus, TicketPriority } from '../../../types/ticket.types'
import StatusBadge from '../../../components/support/shared/StatusBadge'
import PriorityBadge from '../../../components/support/shared/PriorityBadge'
import CategoryBadge from '../../../components/support/shared/CategoryBadge'
import SLABadge from '../../../components/support/shared/SLABadge'
import SourceBadge from '../../../components/support/shared/SourceBadge'
import TicketChatThread from '../../../components/support/client/TicketChatThread'

const STATUS_OPTIONS: TicketStatus[] = ['open', 'in_progress', 'waiting_client', 'resolved', 'closed']
const PRIORITY_OPTIONS: TicketPriority[] = ['critical', 'high', 'medium', 'low']

export default function SupportDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { user, profile } = useAuth()
  const [ticket, setTicket] = useState<SupportTicket | null>(null)
  const [messages, setMessages] = useState<TicketMessage[]>([])
  const [history, setHistory] = useState<TicketHistory[]>([])
  const [adminUsers, setAdminUsers] = useState<{ id: string; nome: string }[]>([])
  const [allTags, setAllTags] = useState<TicketTag[]>([])
  const [ticketTags, setTicketTagsState] = useState<TicketTag[]>([])
  const [loading, setLoading] = useState(true)
  const [replyBody, setReplyBody] = useState('')
  const [isInternal, setIsInternal] = useState(false)
  const [sending, setSending] = useState(false)
  const [showHistory, setShowHistory] = useState(false)
  const bottomRef = useRef<HTMLDivElement>(null)

  const loadData = async () => {
    if (!id) return
    try {
      const [t, m, h, au, tags, tTags] = await Promise.all([
        getAdminTicketById(id),
        getTicketMessages(id),
        getTicketHistory(id),
        getAdminUsers(),
        getAllTags(),
        getTicketTags(id),
      ])
      setTicket(t)
      setMessages(m)
      setHistory(h)
      setAdminUsers(au)
      setAllTags(tags)
      setTicketTagsState(tTags)
      if (t?.has_unread_admin) markAdminTicketRead(id)
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { loadData() }, [id])
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  useTicketRealtime({ context: 'admin', onTicketChange: loadData, onNewMessage: loadData })

  const handleSendReply = async (andStatus?: TicketStatus) => {
    if (!id || !replyBody.trim()) return
    setSending(true)
    try {
      await sendAdminMessage({
        ticketId: id,
        body: replyBody.trim(),
        authorName: profile?.nome ?? 'Suporte',
        authorRole: 'support',
        isInternal,
      })
      if (andStatus) await updateTicket(id, { status: andStatus })
      setReplyBody('')
      setIsInternal(false)
      await loadData()
      toast.success(isInternal ? 'Nota interna adicionada.' : 'Resposta enviada.')
    } catch { toast.error('Erro ao enviar.') } finally { setSending(false) }
  }

  const handleFieldChange = async (field: string, value: string) => {
    if (!id) return
    try {
      await updateTicket(id, { [field]: value } as any)
      await loadData()
    } catch { toast.error('Erro ao atualizar.') }
  }

  if (loading) {
    return <div className="min-h-screen flex items-center justify-center bg-gray-50"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" /></div>
  }
  if (!ticket) {
    return <div className="min-h-screen flex flex-col items-center justify-center bg-gray-50 gap-4"><p className="text-gray-500">Ticket não encontrado.</p><Link to="/admin/support" className="text-brand-600 hover:underline text-sm">Voltar</Link></div>
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 py-6">
        <button onClick={() => navigate('/admin/support')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-4">
          <ArrowLeft size={16} /> Voltar à fila
        </button>

        <div className="grid grid-cols-1 lg:grid-cols-[1fr_340px] gap-6">
          {/* Left: conversation */}
          <div className="space-y-4">
            {/* Header */}
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <div className="flex items-center gap-2 mb-1">
                <span className="text-sm font-mono text-gray-400">#{ticket.ticket_number}</span>
                <StatusBadge status={ticket.status} context="admin" />
                <PriorityBadge priority={ticket.priority} />
              </div>
              <h1 className="text-xl font-bold text-gray-900">{ticket.title}</h1>
              <div className="flex items-center gap-3 mt-2">
                <CategoryBadge category={ticket.category} />
                <SourceBadge source={ticket.source} />
                <span className="text-xs text-gray-400">{ticket.shop_name}</span>
              </div>
            </div>

            {/* Original description */}
            <div className="bg-blue-50 border border-blue-100 rounded-xl p-4">
              <p className="text-xs font-medium text-blue-600 mb-1">Descrição original</p>
              <p className="text-sm text-gray-700 whitespace-pre-wrap">{ticket.description}</p>
            </div>

            {/* Thread */}
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <TicketChatThread messages={messages} context="admin" />
              <div ref={bottomRef} />
            </div>

            {/* Reply form */}
            <div className="bg-white rounded-xl border border-gray-200 p-5">
              <textarea
                value={replyBody}
                onChange={e => setReplyBody(e.target.value)}
                rows={4}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg resize-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 outline-none text-sm"
                placeholder={isInternal ? 'Escrever nota interna (invisível ao cliente)...' : 'Responder ao cliente...'}
              />
              <div className="flex items-center justify-between mt-3">
                <label className="flex items-center gap-2 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={isInternal}
                    onChange={e => setIsInternal(e.target.checked)}
                    className="rounded border-gray-300 text-yellow-500 focus:ring-yellow-500"
                  />
                  <Lock size={14} className={isInternal ? 'text-yellow-600' : 'text-gray-400'} />
                  <span className={`text-xs font-medium ${isInternal ? 'text-yellow-700' : 'text-gray-500'}`}>Nota Interna</span>
                </label>
                <div className="flex gap-2">
                  <button onClick={() => handleSendReply()} disabled={sending || !replyBody.trim()} className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 transition disabled:opacity-50">
                    <Send size={14} /> Enviar
                  </button>
                  <button onClick={() => handleSendReply('resolved')} disabled={sending || !replyBody.trim()} className="inline-flex items-center gap-1.5 px-4 py-2 bg-green-600 text-white rounded-lg text-sm font-medium hover:bg-green-700 transition disabled:opacity-50">
                    <CheckCircle size={14} /> Enviar e Resolver
                  </button>
                  <button onClick={() => handleSendReply('closed')} disabled={sending || !replyBody.trim()} className="inline-flex items-center gap-1.5 px-4 py-2 bg-gray-600 text-white rounded-lg text-sm font-medium hover:bg-gray-700 transition disabled:opacity-50">
                    <XCircle size={14} /> Enviar e Fechar
                  </button>
                </div>
              </div>
            </div>
          </div>

          {/* Right: info panel */}
          <div className="space-y-4">
            {/* SLA */}
            <div className="bg-white rounded-xl border border-gray-200 p-4">
              <p className="text-xs font-medium text-gray-500 mb-2">SLA</p>
              <SLABadge slaDeadline={ticket.sla_deadline} createdAt={ticket.created_at} showBar />
            </div>

            {/* Editable fields */}
            <div className="bg-white rounded-xl border border-gray-200 p-4 space-y-3">
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Status</label>
                <select value={ticket.status} onChange={e => handleFieldChange('status', e.target.value)} className="w-full px-2 py-1.5 border border-gray-300 rounded-lg text-sm">
                  {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Prioridade</label>
                <select value={ticket.priority} onChange={e => handleFieldChange('priority', e.target.value)} className="w-full px-2 py-1.5 border border-gray-300 rounded-lg text-sm">
                  {PRIORITY_OPTIONS.map(p => <option key={p} value={p}>{p}</option>)}
                </select>
              </div>
              <div>
                <label className="block text-xs font-medium text-gray-500 mb-1">Atribuído a</label>
                <select value={ticket.assigned_to ?? ''} onChange={e => handleFieldChange('assigned_to', e.target.value)} className="w-full px-2 py-1.5 border border-gray-300 rounded-lg text-sm">
                  <option value="">Não atribuído</option>
                  {adminUsers.map(u => <option key={u.id} value={u.id}>{u.nome}</option>)}
                </select>
              </div>
            </div>

            {/* Client info */}
            <div className="bg-white rounded-xl border border-gray-200 p-4">
              <p className="text-xs font-medium text-gray-500 mb-2">Cliente</p>
              <p className="text-sm font-semibold text-gray-900">{ticket.shop_name || 'Sem loja'}</p>
              <p className="text-xs text-gray-500">{ticket.opened_by_name}</p>
              {ticket.reporter_email && <p className="text-xs text-gray-400">{ticket.reporter_email}</p>}
            </div>

            {/* Tags */}
            <div className="bg-white rounded-xl border border-gray-200 p-4">
              <p className="text-xs font-medium text-gray-500 mb-2">Tags</p>
              <div className="flex flex-wrap gap-1.5">
                {allTags.map(tag => {
                  const active = ticketTags.some(t => t.id === tag.id)
                  return (
                    <button
                      key={tag.id}
                      onClick={async () => {
                        const newIds = active ? ticketTags.filter(t => t.id !== tag.id).map(t => t.id) : [...ticketTags.map(t => t.id), tag.id]
                        await setTicketTags(ticket.id, newIds)
                        loadData()
                      }}
                      className={`px-2 py-0.5 rounded-full text-xs font-medium border transition ${active ? 'text-white' : 'bg-white text-gray-600 border-gray-300'}`}
                      style={active ? { backgroundColor: tag.color, borderColor: tag.color } : {}}
                    >
                      {tag.name}
                    </button>
                  )
                })}
              </div>
            </div>

            {/* History */}
            <div className="bg-white rounded-xl border border-gray-200 p-4">
              <button onClick={() => setShowHistory(!showHistory)} className="flex items-center justify-between w-full text-xs font-medium text-gray-500">
                Histórico de alterações
                <ChevronDown size={14} className={`transition ${showHistory ? 'rotate-180' : ''}`} />
              </button>
              {showHistory && (
                <div className="mt-3 space-y-2 max-h-60 overflow-y-auto">
                  {history.length === 0 && <p className="text-xs text-gray-400">Nenhuma alteração registrada.</p>}
                  {history.map(h => (
                    <div key={h.id} className="text-xs border-l-2 border-gray-200 pl-3 py-1">
                      <p className="text-gray-700 font-medium">{h.action}</p>
                      {h.old_value && <p className="text-gray-400">{h.old_value} → {h.new_value}</p>}
                      <p className="text-gray-300">{h.actor_name} · {formatDistanceToNow(new Date(h.created_at), { addSuffix: true, locale: ptBR })}</p>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
