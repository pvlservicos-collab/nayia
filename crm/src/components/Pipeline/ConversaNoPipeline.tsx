'use client'

/**
 * A CONVERSA NO PIPELINE (Pedro, 03/11/2026: "ao clicar em abrir conversa com o lead abrir um popup que eu posso conversar
 * com o lead pelo pipeline"): a mesma conversa do chat (ChatWindow), por cima do funil, pela linha do lead -- a resposta sai
 * pelo número dele. "Abrir no chat" leva para a aba do número, como o botão fazia antes. Esc ou clicar fora fecha.
 */
import { useEffect } from 'react'
import Link from 'next/link'
import { ArrowSquareOut, X } from '@phosphor-icons/react'
import type { LeadWithOwner } from '@/lib/types'
import { CAMINHO_DA_LINHA, getLinhaWhatsapp } from '@/lib/leadChannel'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { ChatWindow } from '@/components/Chat'

const NUMERO: Record<string, string> = {
  captacao: 'WhatsApp Leads · 8595-6408', parceria: 'WhatsApp Parceria · 9445-3618', oficial: 'WhatsApp Oficial · 8456-0874',
}

export default function ConversaNoPipeline({ lead, organizationId, aoFechar, aoEnviar }: {
  lead: LeadWithOwner
  organizationId: string
  aoFechar: () => void
  aoEnviar?: (conteudo: string) => void
}) {
  const linha = getLinhaWhatsapp(lead)
  const { marcas } = useParceriaMarcas(linha === 'parceria')
  useEffect(() => {
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') aoFechar() }
    window.addEventListener('keydown', tecla)
    return () => window.removeEventListener('keydown', tecla)
  }, [aoFechar])

  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-3" onClick={aoFechar}>
      <div className="absolute inset-0 bg-black/50" />
      <div className="chat-theme relative w-[min(780px,96vw)] h-[min(90vh,920px)] rounded-2xl overflow-hidden shadow-2xl flex flex-col"
           style={{ background: 'var(--wa-panel)' }} onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-2 px-3 py-2 flex-shrink-0 text-[13px]" style={{ borderBottom: '1px solid var(--wa-divider)', color: 'var(--wa-text-2)' }}>
          <span className="truncate">Conversa pelo {NUMERO[linha || ''] || 'número do lead'}</span>
          <Link prefetch={false} href={`${CAMINHO_DA_LINHA[linha ?? 'parceria']}?leadId=${lead.id}&abrir=${Date.now()}`}
                className="ml-auto flex items-center gap-1 px-2 py-1 rounded-md hover:bg-black/5 dark:hover:bg-white/10" style={{ color: 'var(--wa-text)' }}>
            <ArrowSquareOut size={15} /> Abrir no chat
          </Link>
          <button type="button" onClick={aoFechar} className="wa-icone-btn" aria-label="Fechar a conversa"><X size={20} /></button>
        </div>
        <div className="flex-1 min-h-0">
          <ChatWindow key={lead.id} lead={lead} organizationId={organizationId} linha={linha || undefined}
                      marca={linha === 'parceria' ? marcas[lead.id] : undefined} onMessageSent={(c) => aoEnviar?.(c)} />
        </div>
      </div>
    </div>
  )
}
