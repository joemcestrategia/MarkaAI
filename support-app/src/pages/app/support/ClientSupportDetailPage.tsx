import { useEffect, useState, useRef } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, CheckCircle, RotateCcw, Plus } from 'lucide-react'
import toast from 'react-hot-toast'
import {
  getClientTicketById,
  getTicketMessages,
  sendClientMessage,
  clientConfirmResolved,
  clientReopenTicket,
} from '../../../services/ticketService'
import { useAuth } from '../../../hooks/useAuth'
import { useTicketRealtime } from '../../../hooks/useTicketRealtime'
import type { SupportTicket, TicketMessage } from '../../../types/ticket.types'
import StatusBadge from '../../../components/support/shared/StatusBadge'
import CategoryBadge from '../../../components/support/shared/CategoryBadge'
import SLABadge from '../../../components/support/shared/SLABadge'
import TicketChatThread from '../../../components/support/client/TicketChatThread'
import TicketReplyBox from '../../../components/support/client/TicketReplyBox'

export default function ClientSupportDetailPage() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const { user, profile } = useAuth()
  const [ticket, setTicket] = useState<SupportTicket | null>(null)
  const [messages, setMessages] = useState<TicketMessage[]>([])
  const [loading, setLoading] = useState(true)
  const bottomRef = useRef<HTMLDivElement>(null)

  const loadData = async () => {
    if (!id) return
    try {
      const [t, m] = await Promise.all([
        getClientTicketById(id),
        getTicketMessages(id),
      ])
      setTicket(t)
      setMessages(m)
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { loadData() }, [id])
  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }) }, [messages])

  useTicketRealtime({
    context: 'client',
    onTicketChange: loadData,
    onNewMessage: loadData,
  })

  const handleSend = async (body: string) => {
    if (!id) return
    await sendClientMessage(id, body, profile?.nome ?? user?.email ?? 'Cliente')
    await loadData()
  }

  const handleConfirmResolved = async () => {
    if (!id) return
    try {
      await clientConfirmResolved(id)
      toast.success('Chamado encerrado. Obrigado!')
      await loadData()
    } catch { toast.error('Erro ao fechar chamado.') }
  }

  const handleReopen = async () => {
    if (!id) return
    try {
      await clientReopenTicket(id, profile?.nome ?? 'Cliente')
      toast.success('Chamado reaberto.')
      await loadData()
    } catch { toast.error('Erro ao reabrir chamado.') }
  }

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
      </div>
    )
  }

  if (!ticket) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-gray-50 gap-4">
        <p className="text-gray-500">Chamado não encontrado.</p>
        <button onClick={() => navigate('/app/suporte')} className="text-brand-600 hover:underline text-sm">Voltar</button>
      </div>
    )
  }

  const canReply = !['closed', 'resolved'].includes(ticket.status)

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-3xl mx-auto px-4 py-8">
        {/* Back */}
        <button onClick={() => navigate('/app/suporte')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-6">
          <ArrowLeft size={16} /> Voltar
        </button>

        {/* Header */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 mb-4">
          <div className="flex items-start justify-between flex-wrap gap-3">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <span className="text-sm font-mono text-gray-400">#{ticket.ticket_number}</span>
                <StatusBadge status={ticket.status} context="client" />
              </div>
              <h1 className="text-xl font-bold text-gray-900">{ticket.title}</h1>
              <div className="flex items-center gap-3 mt-2">
                <CategoryBadge category={ticket.category} />
                <SLABadge slaDeadline={ticket.sla_deadline} createdAt={ticket.created_at} />
              </div>
            </div>
          </div>
          <div className="mt-4 bg-gray-50 rounded-lg p-3">
            <p className="text-sm text-gray-700 whitespace-pre-wrap">{ticket.description}</p>
          </div>
        </div>

        {/* Resolved banner */}
        {ticket.status === 'resolved' && (
          <div className="bg-green-50 border border-green-200 rounded-xl p-4 mb-4">
            <p className="text-sm font-medium text-green-800 mb-3">
              Este chamado foi marcado como resolvido. O problema foi resolvido?
            </p>
            <div className="flex gap-3">
              <button onClick={handleConfirmResolved} className="inline-flex items-center gap-1.5 px-4 py-2 bg-green-600 text-white rounded-lg text-sm font-medium hover:bg-green-700 transition">
                <CheckCircle size={14} /> Sim, pode fechar
              </button>
              <button onClick={handleReopen} className="inline-flex items-center gap-1.5 px-4 py-2 bg-white border border-gray-300 text-gray-700 rounded-lg text-sm font-medium hover:bg-gray-50 transition">
                <RotateCcw size={14} /> Não, ainda preciso de ajuda
              </button>
            </div>
          </div>
        )}

        {/* Closed banner */}
        {ticket.status === 'closed' && (
          <div className="bg-gray-100 border border-gray-200 rounded-xl p-4 mb-4">
            <p className="text-sm text-gray-600 mb-3">Este chamado está encerrado.</p>
            <button
              onClick={() => navigate('/app/suporte/novo')}
              className="inline-flex items-center gap-1.5 px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 transition"
            >
              <Plus size={14} /> Abrir novo chamado sobre o mesmo assunto
            </button>
          </div>
        )}

        {/* Chat thread */}
        <div className="bg-white rounded-xl border border-gray-200 p-5 mb-4">
          <h2 className="text-sm font-semibold text-gray-700 mb-4">Conversa</h2>
          <TicketChatThread messages={messages} context="client" />
          <div ref={bottomRef} />
        </div>

        {/* Reply box */}
        {canReply && (
          <div className="bg-white rounded-xl border border-gray-200 p-5">
            <TicketReplyBox onSend={handleSend} />
          </div>
        )}
      </div>
    </div>
  )
}
