import { useState } from 'react'
import { CheckCircle2, ChevronDown, ChevronUp } from 'lucide-react'
import type { TicketCategory } from '../../../types/ticket.types'

const FAQ_DATA: Partial<Record<TicketCategory, { question: string; answer: string }[]>> = {
  payment: [
    {
      question: 'O pagamento PIX não foi confirmado?',
      answer: 'Verifique se o PIX foi enviado para a chave correta e se o valor confere. O sistema confirma pagamentos em até 5 minutos. Se persistir, continue abrindo o ticket.',
    },
    {
      question: 'Cartão de crédito recusado?',
      answer: 'Verifique se o cartão está ativo, se há limite disponível e se os dados estão corretos. Tente novamente ou use outro cartão.',
    },
  ],
  scheduling: [
    {
      question: 'Horários não aparecem para clientes?',
      answer: 'Verifique se os horários de trabalho estão configurados corretamente em Configurações > Horários. Certifique-se de que o profissional está ativo.',
    },
    {
      question: 'Agendamento duplicado?',
      answer: 'Isso pode ocorrer se o cliente agendar duas vezes. Você pode cancelar o duplicado no painel de agendamentos.',
    },
  ],
  whatsapp: [
    {
      question: 'Mensagens de confirmação não estão sendo enviadas?',
      answer: 'Verifique se a integração WhatsApp está ativa em Configurações > Integrações. Confira se o número está correto.',
    },
  ],
  nfse: [
    {
      question: 'Erro "município não aderido"?',
      answer: 'Nem todos os municípios aderiram ao sistema nacional de NFS-e. Verifique no portal da sua prefeitura se há um sistema próprio.',
    },
  ],
  account: [
    {
      question: 'Não consigo recuperar minha senha?',
      answer: 'Verifique sua caixa de spam/lixo eletrônico. O e-mail de recuperação pode levar até 5 minutos. Se não chegar, tente novamente.',
    },
  ],
}

interface Props {
  category: TicketCategory
  onResolved: () => void
}

export default function CategoryFAQ({ category, onResolved }: Props) {
  const [expanded, setExpanded] = useState<number | null>(null)
  const faqs = FAQ_DATA[category]

  if (!faqs || faqs.length === 0) return null

  return (
    <div className="bg-amber-50 border border-amber-200 rounded-xl p-4 space-y-3">
      <p className="text-sm font-medium text-amber-800">
        Antes de abrir um chamado, veja se uma dessas dicas resolve:
      </p>
      <div className="space-y-2">
        {faqs.map((faq, i) => (
          <div key={i} className="bg-white rounded-lg border border-amber-100">
            <button
              type="button"
              onClick={() => setExpanded(expanded === i ? null : i)}
              className="w-full flex items-center justify-between p-3 text-sm font-medium text-gray-700 hover:text-gray-900"
            >
              {faq.question}
              {expanded === i ? <ChevronUp size={16} /> : <ChevronDown size={16} />}
            </button>
            {expanded === i && (
              <div className="px-3 pb-3">
                <p className="text-sm text-gray-600">{faq.answer}</p>
              </div>
            )}
          </div>
        ))}
      </div>
      <button
        type="button"
        onClick={onResolved}
        className="flex items-center gap-2 text-sm font-medium text-green-700 hover:text-green-800 transition"
      >
        <CheckCircle2 size={16} />
        Meu problema foi resolvido!
      </button>
    </div>
  )
}
