import { formatDistanceToNow } from 'date-fns'
import { ptBR } from 'date-fns/locale'
import { Paperclip } from 'lucide-react'
import type { TicketMessage } from '../../../types/ticket.types'

interface Props {
  messages: TicketMessage[]
  context?: 'client' | 'admin'
}

export default function TicketChatThread({ messages, context = 'client' }: Props) {
  if (messages.length === 0) {
    return (
      <div className="text-center py-8 text-sm text-gray-400">
        Nenhuma mensagem ainda. Aguardando resposta do suporte.
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {messages.map((msg) => {
        const isClient = msg.author_role === 'client'
        const isInternal = msg.is_internal
        const isRight = context === 'client' ? isClient : !isClient
        const timeAgo = formatDistanceToNow(new Date(msg.created_at), { addSuffix: true, locale: ptBR })

        return (
          <div key={msg.id} className={`flex ${isRight ? 'justify-end' : 'justify-start'}`}>
            <div className={`max-w-[80%] rounded-2xl px-4 py-3 ${
              isInternal
                ? 'bg-yellow-50 border border-yellow-200'
                : isRight
                  ? 'bg-brand-50 border border-brand-100'
                  : 'bg-gray-50 border border-gray-200'
            }`}>
              <div className="flex items-center gap-2 mb-1">
                <span className="text-xs font-semibold text-gray-700">{msg.author_name}</span>
                {isInternal && (
                  <span className="text-xs bg-yellow-200 text-yellow-800 px-1.5 py-0.5 rounded font-medium">
                    Nota Interna
                  </span>
                )}
                <span className="text-xs text-gray-400">{timeAgo}</span>
              </div>
              <p className="text-sm text-gray-800 whitespace-pre-wrap">{msg.body}</p>
              {msg.attachments && msg.attachments.length > 0 && (
                <div className="mt-2 space-y-1">
                  {msg.attachments.map((att, i) => (
                    <a
                      key={i}
                      href={att.url}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="flex items-center gap-1 text-xs text-brand-600 hover:underline"
                    >
                      <Paperclip size={12} />
                      {att.name}
                    </a>
                  ))}
                </div>
              )}
            </div>
          </div>
        )
      })}
    </div>
  )
}
