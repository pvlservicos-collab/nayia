'use client'

import type { ReactNode } from 'react'
import { ChatCircleText, CalendarCheck, ClipboardText, TreeStructure, Kanban } from '@phosphor-icons/react'

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
/* 24/10 (Pedro): 'arquitetura', ao lado da agenda, só na linha WhatsApp Leads: o fluxograma dos agentes da Nay */
/* 24/10 (Pedro): 'pipeline', ao lado de Visitas na linha WhatsApp Leads: cada lead que chegou e até onde foi */
export type AbaDaParceria = 'conversas' | 'visitas' | 'pipeline' | 'fechamento' | 'arquitetura'

/* 18/10 (Pedro: "a agenda não está lá no número de captação; precisa estar, é claro, todos os números compartilhando a
   mesma agenda"): as outras linhas usam estas mesmas abas, só sem Fechamento (que é da Parceria). `abas` escolhe. */
export default function AbasParceria({ aba, aoMudar, naoLidas, visitasAbertas, children, abas, rotuloConversas, rotuloPipeline }: {
  aba: AbaDaParceria
  aoMudar: (aba: AbaDaParceria) => void
  naoLidas: number
  visitasAbertas: number
  children?: ReactNode
  /** quais abas mostrar; sem isso, as três da Parceria */
  abas?: AbaDaParceria[]
  /** a dica da aba Conversas (o número da linha) */
  rotuloConversas?: string
  /** 29/10: o nome da aba Pipeline (na Leads é o pipeline dos leads; nas outras, o funil do número) */
  rotuloPipeline?: string
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
        {abas?.includes('pipeline') && aba_('pipeline', rotuloPipeline || 'Pipeline dos leads', Kanban, 0,
          rotuloPipeline ? 'O funil deste número, só com as conversas dele' : 'Cada lead que chegou na aba Leads, com a data e até onde foi')}
        {mostra('fechamento') && aba_('fechamento', 'Fechamento', ClipboardText, 0, 'Os checklists de aluguel e venda para o contrato')}
        {abas?.includes('arquitetura') && aba_('arquitetura', 'Arquitetura', TreeStructure, 0, 'Os agentes da Nay Leads: cada etapa num fluxograma, com os números')}
      </div>
      {children}
    </div>
  )
}
