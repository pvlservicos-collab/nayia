'use client'

import { memo } from 'react'
import type { Atendente } from '@/lib/atendentes'

/** `atendente:<member_id>` filtra as conversas de quem está atendendo. */
export type ChatTab = 'all' | 'human' | 'urgent' | `atendente:${string}`

interface ChatFilterTabsProps {
  activeTab: ChatTab
  onChange: (tab: ChatTab) => void
  counts: Record<string, number>
  /** Abas de pessoa, entre HUMANO e URGENTES, cada uma na cor dela. */
  atendentes?: Atendente[]
}

const classeBase = 'flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-medium whitespace-nowrap transition-colors border'

function Contador({ valor, ativo }: { valor: number; ativo: boolean }) {
  if (valor <= 0) return null
  return (
    <span
      className={`px-1.5 rounded-full text-[10px] font-bold ${
        ativo ? 'bg-black/20 text-[var(--chat-bg-conversation)]' : 'bg-white/10 text-[var(--chat-text-primary)]'
      }`}
    >
      {valor}
    </span>
  )
}

function ChatFilterTabs({ activeTab, onChange, counts, atendentes = [] }: ChatFilterTabsProps) {
  const abaFixa = (key: ChatTab, label: string) => {
    const isActive = activeTab === key
    return (
      <button
        key={key}
        onClick={() => onChange(key)}
        className={`${classeBase} ${
          isActive
            ? 'bg-[var(--chat-accent)] border-white/20 text-[var(--chat-bg-conversation)]'
            : 'bg-white/[0.04] border-[var(--chat-border)] text-[var(--chat-text-muted)] hover:bg-white/[0.08] hover:text-[var(--chat-text-primary)]'
        }`}
      >
        {label}
        <Contador valor={counts[key] ?? 0} ativo={isActive} />
      </button>
    )
  }

  return (
    <div className="flex items-center gap-1.5 px-3 py-2 border-b border-[var(--chat-border)] overflow-x-auto">
      {abaFixa('all', 'TODOS')}
      {abaFixa('human', 'HUMANO')}

      {atendentes.map((a) => {
        const key: ChatTab = `atendente:${a.id}`
        const isActive = activeTab === key
        return (
          <button
            key={key}
            onClick={() => onChange(isActive ? 'all' : key)}
            title={`Conversas que ${a.nome} está atendendo`}
            className={`${classeBase} ${isActive ? 'text-[#111]' : 'hover:brightness-125'}`}
            style={
              isActive
                ? { backgroundColor: a.cor, borderColor: a.cor }
                : { backgroundColor: a.cor + '14', borderColor: a.cor + '59', color: a.cor }
            }
          >
            {a.nome.toUpperCase()}
            <Contador valor={counts[key] ?? 0} ativo={isActive} />
          </button>
        )
      })}

      {abaFixa('urgent', 'URGENTES')}
    </div>
  )
}

export default memo(ChatFilterTabs)
