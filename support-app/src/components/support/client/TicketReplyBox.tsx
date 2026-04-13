import { useState } from 'react'
import { Send } from 'lucide-react'

interface Props {
  onSend: (body: string) => Promise<void>
  disabled?: boolean
  placeholder?: string
}

export default function TicketReplyBox({ onSend, disabled, placeholder }: Props) {
  const [body, setBody] = useState('')
  const [sending, setSending] = useState(false)

  const handleSend = async () => {
    if (!body.trim() || sending) return
    setSending(true)
    try {
      await onSend(body.trim())
      setBody('')
    } finally {
      setSending(false)
    }
  }

  return (
    <div className="border-t border-gray-200 pt-4">
      <textarea
        value={body}
        onChange={e => setBody(e.target.value)}
        disabled={disabled}
        placeholder={placeholder ?? 'Adicionar informação ou responder...'}
        className="w-full px-3 py-2 border border-gray-300 rounded-lg resize-none focus:ring-2 focus:ring-brand-500 focus:border-brand-500 outline-none text-sm disabled:bg-gray-50"
        rows={3}
        onKeyDown={e => {
          if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) handleSend()
        }}
      />
      <div className="flex justify-end mt-2">
        <button
          onClick={handleSend}
          disabled={disabled || !body.trim() || sending}
          className="inline-flex items-center gap-2 px-4 py-2 bg-brand-600 text-white rounded-lg text-sm font-medium hover:bg-brand-700 transition disabled:opacity-50"
        >
          <Send size={14} />
          {sending ? 'Enviando...' : 'Enviar'}
        </button>
      </div>
    </div>
  )
}
