'use client'

import { useState } from 'react'
import { CaretUp, CaretDown, PushPin, X } from '@phosphor-icons/react'
import { PinnedMessage } from '@/lib/types'

interface PinnedMessagesBarProps {
  pinned: PinnedMessage[]
  onUnpin: (activityId: string) => void
}

function previewText(pin: PinnedMessage): string {
  const meta = pin.activity.metadata
  if (meta?.media_type) {
    const labels: Record<string, string> = {
      image: '📷 Imagem', video: '🎥 Vídeo', audio: '🎵 Áudio', document: '📄 Documento', sticker: '✨ Figurinha',
    }
    return labels[meta.media_type] || pin.activity.content || '📎 Mídia'
  }
  return pin.activity.content || ''
}

function scrollToActivity(activityId: string) {
  const el = document.getElementById(`activity-${activityId}`)
  if (!el) return
  el.scrollIntoView({ behavior: 'smooth', block: 'center' })
  el.classList.add('ring-2', 'ring-[var(--chat-accent)]', 'rounded-2xl')
  setTimeout(() => el.classList.remove('ring-2', 'ring-[var(--chat-accent)]', 'rounded-2xl'), 1500)
}

export default function PinnedMessagesBar({ pinned, onUnpin }: PinnedMessagesBarProps) {
  const [activeIndex, setActiveIndex] = useState(0)
  const [showAll, setShowAll] = useState(false)

  if (pinned.length === 0) return null

  const safeIndex = Math.min(activeIndex, pinned.length - 1)
  const current = pinned[safeIndex]

  const goTo = (delta: number) => {
    setActiveIndex((prev) => (prev + delta + pinned.length) % pinned.length)
  }

  return (
    <div className="relative border-b border-[var(--chat-border)] bg-[var(--chat-bg-panel)]">
      <div className="flex items-center gap-2 px-4 py-2">
        {pinned.length > 1 && (
          <div className="flex flex-col items-center justify-center text-[var(--chat-text-muted)]">
            <button onClick={() => goTo(-1)} className="hover:text-[var(--chat-text-primary)]" title="Fixada anterior">
              <CaretUp size={12} weight="bold" />
            </button>
            <button onClick={() => goTo(1)} className="hover:text-[var(--chat-text-primary)]" title="Próxima fixada">
              <CaretDown size={12} weight="bold" />
            </button>
          </div>
        )}
        <PushPin size={16} weight="fill" className="text-[var(--chat-accent)] -rotate-45 flex-shrink-0" />
        <button
          onClick={() => scrollToActivity(current.activity_id)}
          className="flex-1 min-w-0 text-left"
        >
          <p className="text-xs font-semibold text-[var(--chat-accent)]">
            Mensagem fixada {pinned.length > 1 ? `(${safeIndex + 1}/${pinned.length})` : ''}
          </p>
          <p className="text-sm text-[var(--chat-text-primary)] truncate">{previewText(current)}</p>
        </button>
        {pinned.length > 1 && (
          <button
            onClick={() => setShowAll((v) => !v)}
            className="text-xs font-medium text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] whitespace-nowrap px-2"
          >
            Ver todas
          </button>
        )}
        <button
          onClick={() => onUnpin(current.activity_id)}
          className="text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] flex-shrink-0"
          title="Desafixar"
        >
          <X size={16} weight="bold" />
        </button>
      </div>

      {showAll && (
        <div className="absolute left-0 right-0 top-full z-30 max-h-72 overflow-y-auto bg-[var(--chat-bg-menu)] border border-[var(--chat-border)] shadow-xl rounded-b-xl">
          {pinned.map((pin, idx) => (
            <div
              key={pin.id}
              className="flex items-center gap-2 px-4 py-2 hover:bg-[var(--chat-bg-hover)] border-b border-[var(--chat-border)] last:border-b-0"
            >
              <button
                onClick={() => { setActiveIndex(idx); setShowAll(false); scrollToActivity(pin.activity_id) }}
                className="flex-1 min-w-0 text-left"
              >
                <p className="text-sm text-[var(--chat-text-primary)] truncate">{previewText(pin)}</p>
              </button>
              <button
                onClick={() => onUnpin(pin.activity_id)}
                className="text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] flex-shrink-0"
                title="Desafixar"
              >
                <X size={14} weight="bold" />
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
