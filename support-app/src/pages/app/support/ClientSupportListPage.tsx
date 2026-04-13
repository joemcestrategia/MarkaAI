import { useEffect, useState } from 'react'
import { useNavigate, Link } from 'react-router-dom'
import { Plus, Headphones, Inbox } from 'lucide-react'
import { getClientTickets } from '../../../services/ticketService'
import { useAuth } from '../../../hooks/useAuth'
import { useTicketRealtime } from '../../../hooks/useTicketRealtime'
import type { SupportTicket } from '../../../types/ticket.types'
import TicketCard from '../../../components/support/client/TicketCard'

type FilterTab = 'all' | 'open_active' | 'resolved' | 'closed'

export default function ClientSupportListPage() {
  const { profile } = useAuth()
  const navigate = useNavigate()
  const [tickets, setTickets] = useState<SupportTicket[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState<FilterTab>('all')

  const loadTickets = async () => {
    try {
      const data = await getClientTickets(filter === 'all' ? undefined : filter)
      setTickets(data)
    } catch (err) {
      console.error(err)
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { loadTickets() }, [filter])

  useTicketRealtime({
    context: 'client',
    shopId: profile?.shop_id,
    onTicketChange: loadTickets,
    onNewMessage: loadTickets,
  })

  const tabs: { key: FilterTab; label: string }[] = [
    { key: 'all', label: 'Todos' },
    { key: 'open_active', label: 'Abertos' },
    { key: 'resolved', label: 'Resolvidos' },
    { key: 'closed', label: 'Fechados' },
  ]

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-3xl mx-auto px-4 py-8">
        {/* Header */}
        <div className="flex items-center justify-between mb-6">
          <div>
            <div className="flex items-center gap-2">
              <Headphones className="text-brand-600" size={24} />
              <h1 className="text-2xl font-bold text-gray-900">Central de Suporte</h1>
            </div>
            <p className="text-sm text-gray-500 mt-1">
              Precisa de ajuda? Nossa equipe responde em poucas horas.
            </p>
          </div>
          <button
            onClick={() => navigate('/app/suporte/novo')}
            className="inline-flex items-center gap-2 px-4 py-2.5 bg-brand-600 text-white rounded-xl font-medium hover:bg-brand-700 transition text-sm shadow-sm"
          >
            <Plus size={16} />
            Abrir Chamado
          </button>
        </div>

        {/* Filter tabs */}
        <div className="flex gap-1 bg-gray-100 rounded-lg p-1 mb-6">
          {tabs.map(tab => (
            <button
              key={tab.key}
              onClick={() => setFilter(tab.key)}
              className={`flex-1 px-3 py-2 rounded-md text-sm font-medium transition ${
                filter === tab.key ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Ticket list */}
        {loading ? (
          <div className="flex justify-center py-16">
            <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-brand-600" />
          </div>
        ) : tickets.length === 0 ? (
          <div className="text-center py-16">
            <Inbox className="mx-auto text-gray-300 mb-4" size={48} />
            <h3 className="text-lg font-semibold text-gray-600">Tudo certo por aqui!</h3>
            <p className="text-sm text-gray-400 mt-1">Caso precise de ajuda, abra um chamado.</p>
            <button
              onClick={() => navigate('/app/suporte/novo')}
              className="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 transition"
            >
              <Plus size={14} />
              Abrir Chamado
            </button>
          </div>
        ) : (
          <div className="space-y-3">
            {tickets.map(t => (
              <TicketCard key={t.id} ticket={t} />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
