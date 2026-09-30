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

export default function AbasParceria({ aba, aoMudar, naoLidas, visitasAbertas, children }: {
  aba: AbaDaParceria
  aoMudar: (aba: AbaDaParceria) => void
  naoLidas: number
  visitasAbertas: number
  children?: ReactNode
}) {
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
      <div className="wa-abas__abas" role="tablist" aria-label="Abas da Parceria">
        {aba_('conversas', 'Conversas', ChatCircleText, naoLidas, 'As conversas do WhatsApp da Parceria')}
        {aba_('visitas', 'Visitas agendadas', CalendarCheck, visitasAbertas, 'As visitas que a Nay agendou, com o andamento e as datas')}
        {aba_('fechamento', 'Fechamento', ClipboardText, 0, 'Os checklists de aluguel e venda para o contrato')}
      </div>
      {children}
    </div>
  )
}
