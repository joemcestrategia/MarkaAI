import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ArrowLeft, ArrowRight, Send, Calendar, CreditCard, MessageSquare, Receipt, KeyRound, HelpCircle } from 'lucide-react'
import toast from 'react-hot-toast'
import { useAuth } from '../../../hooks/useAuth'
import { createClientTicket, getClientShopInfo } from '../../../services/ticketService'
import { getDefaultPriorityByCategory } from '../../../utils/ticketPriority'
import type { TicketCategory } from '../../../types/ticket.types'
import CategoryFAQ from '../../../components/support/client/CategoryFAQ'

const CATEGORIES: { key: TicketCategory; label: string; icon: typeof Calendar }[] = [
  { key: 'scheduling', label: 'Agendamentos', icon: Calendar },
  { key: 'payment',    label: 'Pagamentos', icon: CreditCard },
  { key: 'whatsapp',   label: 'WhatsApp / Notificações', icon: MessageSquare },
  { key: 'nfse',       label: 'Nota Fiscal (NFS-e)', icon: Receipt },
  { key: 'account',    label: 'Conta e Acesso', icon: KeyRound },
  { key: 'other',      label: 'Outro', icon: HelpCircle },
]

export default function ClientSupportNewPage() {
  const navigate = useNavigate()
  const { user, profile } = useAuth()
  const [step, setStep] = useState(1)
  const [category, setCategory] = useState<TicketCategory | null>(null)
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [sending, setSending] = useState(false)

  const handleSubmit = async () => {
    if (!category || !title.trim() || description.trim().length < 20) return
    setSending(true)
    try {
      const shop = await getClientShopInfo()
      const ticket = await createClientTicket({
        title: title.trim(),
        description: description.trim(),
        category,
        shop_id: shop?.id ?? '',
        shop_name: shop?.name ?? '',
        opened_by_name: profile?.nome ?? user?.email ?? 'Cliente',
        reporter_email: profile?.email ?? user?.email,
      })
      toast.success(`Chamado #${ticket.ticket_number} aberto com sucesso! Nossa equipe já foi notificada.`)
      navigate(`/app/suporte/${ticket.id}`)
    } catch (err: any) {
      toast.error('Erro ao abrir chamado. Tente novamente.')
      console.error(err)
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-2xl mx-auto px-4 py-8">
        {/* Header */}
        <button onClick={() => navigate('/app/suporte')} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700 mb-6">
          <ArrowLeft size={16} />
          Voltar
        </button>
        <h1 className="text-2xl font-bold text-gray-900 mb-2">Abrir Novo Chamado</h1>

        {/* Stepper */}
        <div className="flex items-center gap-3 mb-8">
          <div className={`flex items-center gap-2 text-sm font-medium ${step >= 1 ? 'text-brand-600' : 'text-gray-400'}`}>
            <span className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold ${step >= 1 ? 'bg-brand-600 text-white' : 'bg-gray-200 text-gray-500'}`}>1</span>
            Categoria
          </div>
          <div className="flex-1 h-0.5 bg-gray-200"><div className={`h-full bg-brand-600 transition-all ${step >= 2 ? 'w-full' : 'w-0'}`} /></div>
          <div className={`flex items-center gap-2 text-sm font-medium ${step >= 2 ? 'text-brand-600' : 'text-gray-400'}`}>
            <span className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold ${step >= 2 ? 'bg-brand-600 text-white' : 'bg-gray-200 text-gray-500'}`}>2</span>
            Detalhes
          </div>
        </div>

        {/* Step 1 */}
        {step === 1 && (
          <div className="space-y-4">
            <p className="text-sm text-gray-600 font-medium">Selecione a categoria do seu problema:</p>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {CATEGORIES.map(cat => {
                const Icon = cat.icon
                const selected = category === cat.key
                return (
                  <button
                    key={cat.key}
                    onClick={() => setCategory(cat.key)}
                    className={`flex flex-col items-center gap-2 p-4 rounded-xl border-2 transition text-center ${
                      selected ? 'border-brand-500 bg-brand-50' : 'border-gray-200 hover:border-gray-300 bg-white'
                    }`}
                  >
                    <Icon size={24} className={selected ? 'text-brand-600' : 'text-gray-400'} />
                    <span className={`text-sm font-medium ${selected ? 'text-brand-700' : 'text-gray-700'}`}>{cat.label}</span>
                  </button>
                )
              })}
            </div>

            {category && (
              <CategoryFAQ
                category={category}
                onResolved={() => {
                  toast.success('Que bom que resolveu! Ficamos à disposição.')
                  navigate('/app/suporte')
                }}
              />
            )}

            <div className="flex justify-end pt-4">
              <button
                onClick={() => setStep(2)}
                disabled={!category}
                className="inline-flex items-center gap-2 px-5 py-2.5 bg-brand-600 text-white rounded-lg font-medium hover:bg-brand-700 transition disabled:opacity-50 text-sm"
              >
                Continuar
                <ArrowRight size={16} />
              </button>
            </div>
          </div>
        )}

        {/* Step 2 */}
        {step === 2 && (
          <div className="space-y-5">
            <button onClick={() => setStep(1)} className="flex items-center gap-1 text-sm text-gray-500 hover:text-gray-700">
              <ArrowLeft size={14} />
              Voltar para categorias
            </button>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Título / Resumo *</label>
              <input
                type="text"
                value={title}
                onChange={e => setTitle(e.target.value)}
                maxLength={120}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-brand-500 focus:border-brand-500 outline-none text-sm"
                placeholder="Descreva brevemente o problema"
              />
              <p className="text-xs text-gray-400 mt-1">{title.length}/120</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">Descrição detalhada *</label>
              <textarea
                value={description}
                onChange={e => setDescription(e.target.value)}
                rows={5}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-brand-500 focus:border-brand-500 outline-none text-sm resize-none"
                placeholder="Descreva o que aconteceu, quando aconteceu e o que você já tentou fazer."
              />
              {description.length > 0 && description.length < 20 && (
                <p className="text-xs text-red-500 mt-1">Mínimo de 20 caracteres ({description.length}/20)</p>
              )}
            </div>

            <div className="bg-gray-50 rounded-lg p-3 text-xs text-gray-500">
              Prioridade auto-atribuída: <span className="font-semibold">{category ? getDefaultPriorityByCategory(category).toUpperCase() : '—'}</span> (baseada na categoria)
            </div>

            <div className="flex justify-end gap-3 pt-2">
              <button
                onClick={() => setStep(1)}
                className="px-4 py-2.5 text-sm text-gray-600 hover:text-gray-800 transition"
              >
                Voltar
              </button>
              <button
                onClick={handleSubmit}
                disabled={sending || !title.trim() || description.trim().length < 20}
                className="inline-flex items-center gap-2 px-5 py-2.5 bg-brand-600 text-white rounded-lg font-medium hover:bg-brand-700 transition disabled:opacity-50 text-sm"
              >
                <Send size={14} />
                {sending ? 'Enviando...' : 'Enviar Chamado'}
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
