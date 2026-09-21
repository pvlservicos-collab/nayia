'use client'

import { useMemo, useRef, useEffect } from 'react'
import { Image, VideoCamera, FileAudio, FileText, Lightning, Stack } from '@phosphor-icons/react'
import { QuickReply } from '@/hooks/useQuickReplies'

export interface QuickReplyGroup {
  label: string
  items: QuickReply[]
}

/** Filtra + agrupa (biblioteca da empresa por categoria, depois "Meus Atalhos") — usado
 * tanto pelo picker (renderização) quanto pelo composer (navegação por teclado), para que
 * os dois nunca fiquem com uma ordem diferente da lista. */
export function filterAndGroupQuickReplies(shared: QuickReply[], personal: QuickReply[], filter: string) {
  const needle = filter.trim().toLowerCase()
  const matches = (qr: QuickReply) =>
    !needle || qr.shortcut.toLowerCase().includes(needle) || qr.content.toLowerCase().includes(needle)

  const sharedFiltered = shared.filter(matches)
  const personalFiltered = personal.filter(matches)

  const byCategory = new Map<string, QuickReply[]>()
  for (const qr of sharedFiltered) {
    const key = qr.category?.trim() || 'Outros'
    if (!byCategory.has(key)) byCategory.set(key, [])
    byCategory.get(key)!.push(qr)
  }

  const groups: QuickReplyGroup[] = [...byCategory.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([label, items]) => ({ label, items }))

  if (personalFiltered.length > 0) {
    groups.push({ label: 'Meus Atalhos', items: personalFiltered })
  }

  const flat = groups.flatMap((g) => g.items)
  return { groups, flat }
}

function MediaGlyph({ mediaType }: { mediaType: string | null }) {
  if (!mediaType) return null
  const props = { size: 13, className: 'text-[var(--chat-text-muted)] flex-shrink-0' }
  if (mediaType === 'image' || mediaType === 'sticker') return <Image {...props} />
  if (mediaType === 'video') return <VideoCamera {...props} />
  if (mediaType === 'audio') return <FileAudio {...props} />
  return <FileText {...props} />
}

interface QuickReplyPickerProps {
  shared: QuickReply[]
  personal: QuickReply[]
  filter: string
  highlightedIndex: number
  onHighlightIndex: (index: number) => void
  onSelect: (item: QuickReply) => void
}

export default function QuickReplyPicker({
  shared,
  personal,
  filter,
  highlightedIndex,
  onHighlightIndex,
  onSelect,
}: QuickReplyPickerProps) {
  const { groups, flat } = useMemo(
    () => filterAndGroupQuickReplies(shared, personal, filter),
    [shared, personal, filter]
  )
  const highlightedRef = useRef<HTMLButtonElement>(null)

  useEffect(() => {
    highlightedRef.current?.scrollIntoView({ block: 'nearest' })
  }, [highlightedIndex])

  let runningIndex = -1

  return (
    <div className="glass-raised w-[340px] max-h-[320px] overflow-y-auto rounded-xl py-2">
      {flat.length === 0 ? (
        <div className="px-4 py-6 text-center text-xs text-[var(--chat-text-muted)]">
          {shared.length === 0 && personal.length === 0 ? (
            <>Nenhuma resposta rápida cadastrada ainda.<br />Configure em Ajustes → Respostas Rápidas.</>
          ) : (
            'Nenhum atalho encontrado.'
          )}
        </div>
      ) : (
        groups.map((group) => (
          <div key={group.label} className="mb-1 last:mb-0">
            <p className="px-3 pt-2 pb-1 text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-tertiary)]">
              {group.label}
            </p>
            {group.items.map((qr) => {
              runningIndex += 1
              const index = runningIndex
              const isHighlighted = index === highlightedIndex
              return (
                <button
                  key={qr.id}
                  ref={isHighlighted ? highlightedRef : undefined}
                  type="button"
                  onMouseEnter={() => onHighlightIndex(index)}
                  onClick={() => onSelect(qr)}
                  className={`w-full flex items-start gap-2 px-3 py-2 text-left transition-colors ${
                    isHighlighted ? 'bg-[var(--chat-bg-hover)]' : 'hover:bg-[var(--chat-bg-hover)]/60'
                  }`}
                >
                  <Lightning size={13} weight="fill" className="text-[var(--chat-accent)] flex-shrink-0 mt-0.5" />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-1.5">
                      <span className="text-[12px] font-semibold text-[var(--chat-text-primary)]">/{qr.shortcut}</span>
                      {(!qr.steps || qr.steps.length === 0) && <MediaGlyph mediaType={qr.mediaType} />}
                    </div>
                    {qr.steps && qr.steps.length > 0 ? (
                      <p className="text-[11px] text-[var(--chat-text-muted)] flex items-center gap-1">
                        <Stack size={12} className="flex-shrink-0" />
                        {qr.steps.length} passos
                      </p>
                    ) : (
                      qr.content && (
                        <p className="text-[11px] text-[var(--chat-text-muted)] truncate">{qr.content}</p>
                      )
                    )}
                  </div>
                </button>
              )
            })}
          </div>
        ))
      )}
    </div>
  )
}
