'use client'

/**
 * CHAT CAPTAÇÃO (Pedro, 03/11/2026): "cria um item no menu, Captação, lá tu coloca todos os chats que estão em cadastro
 * incompleto"; e a conversa aberta pela tela Imóveis captar OLX ("deve abrir uma conversa pelo número Parceria e essa
 * conversa ficar no proprietário Parceria e na aba Captação, já que é uma conversa de captação").
 *
 * Quem entra: /api/captacao/conversas (os donos dos Cadastros incompletos, na linha por onde falavam) e as conversas
 * marcadas (custom_attributes.conversa_captacao). A tela é a ChatJuntado (a cara do Leads, com a lupa); cada conversa
 * responde pelo número dela. O botão direito tira a marca de captação (o cadastro incompleto sai quando o cadastro sai de lá).
 */
import { useCallback } from 'react'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { useConversasDeCaptacao, ehDeCaptacao } from '@/hooks/useConversasDeCaptacao'
import type { LeadWithOwner } from '@/lib/types'
import ChatJuntado from './ChatJuntado'
import { organizar } from './OrganizarConversa'

export default function ChatCaptacao() {
  const { setLeads } = useLeadsContext()
  const ids = useConversasDeCaptacao()
  const pertence = useCallback((l: LeadWithOwner) => ehDeCaptacao(l, ids), [ids])

  const tirar = async (l: LeadWithOwner) => {
    try {
      const o = await organizar(l.id, { captacao: false })
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, custom_attributes: o.custom_attributes } : x)))
    } catch (e: any) { window.alert(e?.message || 'Não consegui tirar da Captação.') }
  }

  return (
    <ChatJuntado titulo="Captação" subtitulo="Cadastros incompletos e donos chamados pela OLX · cada conversa responde pelo número dela"
                 pertence={pertence} chaveAbas="crm:abas-captacao" vazio="Nenhuma conversa de captação agora."
                 menu={(lead, fechar) => (lead.custom_attributes as any)?.conversa_captacao === true ? (
                   <button type="button" className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)]"
                           title="A conversa continua no número dela; só sai desta tela (e perde a etiqueta Captação)"
                           onClick={() => { fechar(); void tirar(lead) }}>
                     Tirar da Captação
                   </button>
                 ) : (
                   <div className="px-4 py-2 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
                     Cadastro incompleto: sai daqui quando o cadastro for concluído ou descartado.
                   </div>
                 )} />
  )
}
