import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowLeft, Send } from 'lucide-react'
import toast from 'react-hot-toast'
import { useAuth } from '../../../hooks/useAuth'
import { createManualTicket, getAdminUsers, searchShops } from '../../../services/ticketService'
import { getDefaultPriorityByCategory } from '../../../utils/ticketPriority'
import type { TicketCategory, TicketPriority, TicketSource } from '../../../types/ticket.types'

const CATEGORIES: { key: TicketCategory; label: string }[] = [
  { key: 'scheduling', label: 'Agendamentos' },
  { key: 'payment', label: 'Pagamentos' },
  { key: 'whatsapp', label: 'WhatsApp' },
  { key: 'nfse', label: 'NFS-e' },
  { key: 'account', label: 'Conta e Acesso' },
  { key: 'other', label: 'Outro' },
]

const SOURCES: { key: TicketSource; label: string }[] = [
  { key: 'manual', label: 'Manual' },
  { key: 'email', label: 'E-mail' },
  { key: 'whatsapp', label: 'WhatsApp' },
]

const PRIORITIES: { key: TicketPriority; label: string }[] = [
  { key: 'critical', label: 'Crítico' },
  { key: 'high', label: 'Alto' },
  { key: 'medium', label: 'Médio' },
  { key: 'low', label: 'Baixo' },
]

export default function SupportNewPage() {
  const navigate = useNavigate()
  const { profile } = useAuth()
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [category, setCategory] = useState<TicketCategory>('other')
  const [priority, setPriority] = useState<TicketPriority>('medium')
  const [source, setSource] = useState<TicketSource>('manual')
  const [shopQuery, setShopQuery] = useState('')
  const [shopResults, setShopResults] = useState<{ id: string; name: string }[]>([])
  const [selectedShop, setSelectedShop] = useState<{ id: string; name: string } | null>(null)
  const [reporterEmail, setReporterEmail] = useState('')
  const [internalNote, setInternalNote] = useState('')
  const [sending, setSending] = useState(false)

  const handleCategoryChange = (cat: TicketCategory) => {
    setCategory(cat)
    setPriority(getDefaultPriorityByCategory(cat))
  }

  const handleShopSearch = async (q: string) => {
    setShopQuery(q)
    if (q.length >= 2) {
      const results = await searchShops(q)
      setShopResults(results)
    } else {
      setShopResults([])
    }
  }

  const handleSubmit = async () => {
    if (!title.trim() || !description.trim()) return
    setSending(true)
    try {
      const ticket = await createManualTicket({
        title: title.trim(),
        description: description.trim(),
        category,
        priority,
        source,
        shop_id: selectedShop?.id,
        shop_name: selectedShop?.name,
        opened_by_name: profile?.nome ?? 'Admin',
        reporter_email: reporterEmail || undefined,
        internal_note: internalNote || undefined,
      })
      toast.success(`Ticket #${ticket.ticket_number} criado.`)
      navigate(`/admin/support/${ticket.id}`)
    } catch (err) {
      toast.error('Erro ao criar ticket.')
      console.error(err)
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-2xl mx-auto px-4 py-8">
        <button onClick={() => navigate('/admin/support')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-6">
          <ArrowLeft size={16} /> Voltar
        </button>
        <h1 className="text-2xl font-bold text-gray-900 mb-6">Criar Ticket Manual</h1>

        <div className="bg-white rounded-xl border border-gray-200 p-6 space-y-5">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Categoria</label>
              <select value={category} onChange={e => handleCategoryChange(e.target.value as TicketCategory)} className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm">
                {CATEGORIES.map(c => <option key={c.key} value={c.key}>{c.label}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Prioridade</label>
              <select value={priority} onChange={e => setPriority(e.target.value as TicketPriority)} className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm">
                {PRIORITIES.map(p => <option key={p.key} value={p.key}>{p.label}</option>)}
              </select>
            </div>
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Fonte</label>
            <select value={source} onChange={e => setSource(e.target.value as TicketSource)} className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm">
              {SOURCES.map(s => <option key={s.key} value={s.key}>{s.label}</option>)}
            </select>
          </div>

          <div className="relative">
            <label className="block text-sm font-medium text-gray-700 mb-1">Loja (buscar)</label>
            <input
              type="text"
              value={shopQuery}
              onChange={e => handleShopSearch(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              placeholder="Pesquisar loja pelo nome..."
            />
            {selectedShop && (
              <p className="text-xs text-green-600 mt-1">Selecionada: {selectedShop.name}</p>
            )}
            {shopResults.length > 0 && !selectedShop && (
              <div className="absolute z-10 w-full bg-white border border-gray-200 rounded-lg mt-1 shadow-lg max-h-40 overflow-y-auto">
                {shopResults.map(s => (
                  <button key={s.id} onClick={() => { setSelectedShop(s); setShopQuery(s.name); setShopResults([]) }} className="w-full text-left px-3 py-2 hover:bg-gray-50 text-sm">
                    {s.name}
                  </button>
                ))}
              </div>
            )}
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">E-mail do solicitante</label>
            <input type="email" value={reporterEmail} onChange={e => setReporterEmail(e.target.value)} className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm" placeholder="email@exemplo.com" />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Título *</label>
            <input type="text" value={title} onChange={e => setTitle(e.target.value)} maxLength={120} className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm" placeholder="Resumo do problema" />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Descrição *</label>
            <textarea value={description} onChange={e => setDescription(e.target.value)} rows={4} className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm resize-none" placeholder="Detalhes do problema..." />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Nota interna (opcional)</label>
            <textarea value={internalNote} onChange={e => setInternalNote(e.target.value)} rows={2} className="w-full px-3 py-2 border border-yellow-300 bg-yellow-50 rounded-lg text-sm resize-none" placeholder="Visível apenas para a equipe de suporte..." />
          </div>

          <div className="flex justify-end pt-2">
            <button onClick={handleSubmit} disabled={sending || !title.trim() || !description.trim()} className="inline-flex items-center gap-2 px-5 py-2.5 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 transition disabled:opacity-50">
              <Send size={14} />
              {sending ? 'Criando...' : 'Criar Ticket'}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
