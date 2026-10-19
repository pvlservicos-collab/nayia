'use client'

import type { ReactNode } from 'react'
import { ChatCircleText, CalendarCheck, ClipboardText } from '@phosphor-icons/react'

/**
 * As abas da Parceria, na faixa de cima da tela (Pedro, 29/09/2026: "quero que
 * o whatsapp parceria fica em abas, primeiro chat, depois visitas agendadas";
 * e em seguida: "as abas devem ficar no lugar de Z-API (parceria) +55 92
 * 9445-3618" -- a faixa que dizia a linha e o número). O número da linha
 * continua no topo da lista de conversas.
 *
 * Depois das abas, até o canto direito, vem a barra de métricas (`children`):
 * fica à vista no chat e na agenda, não é aba (Pedro, 29/09).
 */
export type AbaDaParceria = 'conversas' | 'visitas' | 'fechamento'

/* 18/10 (Pedro: "a agenda não está lá no número de captação; precisa estar, é claro, todos os números compartilhando a
   mesma agenda"): as outras linhas usam estas mesmas abas, só sem Fechamento (que é da Parceria). `abas` escolhe. */
export default function AbasParceria({ aba, aoMudar, naoLidas, visitasAbertas, children, abas, rotuloConversas }: {
  aba: AbaDaParceria
  aoMudar: (aba: AbaDaParceria) => void
  naoLidas: number
  visitasAbertas: number
  children?: ReactNode
  /** quais abas mostrar; sem isso, as três da Parceria */
  abas?: AbaDaParceria[]
  /** a dica da aba Conversas (o número da linha) */
  rotuloConversas?: string
}) {
  const mostra = (k: AbaDaParceria) => !abas || abas.includes(k)
  const aba_ = (chave: AbaDaParceria, rotulo: string, Icone: typeof ChatCircleText, contagem: number, titulo: string) => {
    const on = aba === chave
    return (
      <button
        type="button"
        role="tab"
        aria-selected={on}
        onClick={() => aoMudar(chave)}
        title={titulo}
        className={`wa-aba ${on ? 'wa-aba--on' : ''}`}
      >
        <Icone size={20} weight={on ? 'fill' : 'regular'} />
        {rotulo}
        {contagem > 0 && <span className="wa-badge">{contagem > 99 ? '99+' : contagem}</span>}
      </button>
    )
  }

  return (
    <div className="wa-abas">
      <div className="wa-abas__abas" role="tablist" aria-label="Abas da linha">
        {mostra('conversas') && aba_('conversas', 'Conversas', ChatCircleText, naoLidas, rotuloConversas || 'As conversas do WhatsApp da Parceria')}
        {mostra('visitas') && aba_('visitas', 'Visitas agendadas', CalendarCheck, visitasAbertas, 'A agenda de visitas: é uma só para todos os números')}
        {mostra('fechamento') && aba_('fechamento', 'Fechamento', ClipboardText, 0, 'Os checklists de aluguel e venda para o contrato')}
      </div>
      {children}
    </div>
  )
}
