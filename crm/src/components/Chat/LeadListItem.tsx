'use client'

import { memo } from 'react'
import { LeadWithOwner, SearchHit } from '@/lib/types'
import { Robot, PushPin } from '@phosphor-icons/react'
import { getInitials, formatPhone, renderSnippet } from '@/lib/utils'
import IntegrationBadge from '@/components/Shared/IntegrationBadge'
import LeadBadges from '@/components/Shared/LeadBadges'
import { PAYMENT_STATUS_META, TONE_STYLES } from '@/lib/orderStatus'
import type { Atendente } from '@/lib/atendentes'

interface LeadListItemProps {
    lead: LeadWithOwner
    isSelected: boolean
    onContextMenu: (e: React.MouseEvent, lead: LeadWithOwner) => void
    timeStr: string
    hit?: SearchHit
    query?: string
    hideReplyHighlight?: boolean
    /**
     * Segunda via do clique.
     *
     * Quem decide normalmente é a lista (delegação em LeadList, que sabe qual
     * linha foi apertada mesmo se a lista se reordenar no meio). Este onClick é
     * rede de segurança: se o evento não chegar lá por qualquer motivo, a
     * conversa abre do mesmo jeito. Abrir duas vezes a mesma não faz mal.
     */
    onClick: (lead: LeadWithOwner) => void
    /** Quem está atendendo — etiqueta colorida com o nome, controle interno. */
    atendente?: Atendente
}

const PAYMENT_METHOD_TAGS: Record<string, { label: string; style: React.CSSProperties }> = {
    pix: { label: 'PIX', style: { backgroundColor: 'rgba(34,197,94,0.15)', color: '#4ade80' } },
    credit_card: { label: 'Cartão', style: { backgroundColor: 'rgba(59,130,246,0.15)', color: '#60a5fa' } },
    boleto: { label: 'Boleto', style: { backgroundColor: 'rgba(251,146,60,0.15)', color: '#fb923c' } },
    dinheiro: { label: 'Dinheiro', style: { backgroundColor: 'rgba(52,211,153,0.15)', color: '#34d399' } },
}

const PAYMENT_STATUS_TAGS: Record<string, { label: string; style: React.CSSProperties }> = Object.fromEntries(
    Object.entries(PAYMENT_STATUS_META).map(([value, meta]) => [value, { label: meta.label, style: TONE_STYLES[meta.tone] }])
)

const LeadListItem = ({ lead, isSelected, onClick, onContextMenu, timeStr, hit, query, hideReplyHighlight, atendente }: LeadListItemProps) => {
    // Conversa importada não tem prévia (a Z-API não traz mensagem antiga).
    // "Ver conversa" prometia um histórico que não existe; dizer de onde ela veio
    // prepara pra tela vazia em vez de surpreender.
    const importada = (lead.custom_attributes as Record<string, unknown> | undefined)?.origem === 'conversa_whatsapp'
    const defaultMsg = importada
      ? 'Conversa do WhatsApp · sem histórico aqui'
      : lead.last_activity_type ? 'Ver conversa' : 'Sem mensagens'
    const lastMsg = lead.last_message_content || defaultMsg

    const orderPaymentMethod = lead.custom_attributes?.last_order_payment_method as string | undefined
    const orderPaymentStatus = lead.custom_attributes?.last_order_payment_status as string | undefined

    let SenderIcon = null
    let iconColor = ''

    if (lead.last_message_sender_type === 'ai' || lead.last_message_sender_type === 'ai_agent') {
        SenderIcon = Robot
        iconColor = 'text-violet-600'
    }

    // Faixa de destaque à esquerda do item. Só o "lead respondeu" continua
    // colorido — é o sinal que importa e o único que precisa saltar. Os dois
    // estados de "você mandou" eram azul e turquesa; viraram dois níveis de
    // cinza claro, que se distinguem entre si sem competir com o verde.
    const unreadGradient = lead.is_unread
        ? (lead.last_message_sender_type === 'lead'
            ? 'linear-gradient(to right, rgba(34,197,94,0.5), transparent 80%)'
            : 'linear-gradient(to right, rgba(255,255,255,0.16), transparent 80%)')
        : (lead.last_message_sender_type === 'human' && !hideReplyHighlight
            ? 'linear-gradient(to right, rgba(255,255,255,0.07), transparent 80%)'
            : undefined)


    return (
        <div className="w-full flex-shrink-0 relative">
            {/* Abrir a conversa é decidido pela lista (LeadList), pela linha que
                estava embaixo do mouse/dedo na hora do toque — ver `aoApertar`. */}
            <button
                type="button"
                data-lead-id={lead.id}
                onClick={() => onClick(lead)}
                onContextMenu={(e) => onContextMenu(e, lead)}
                className={`w-full text-left px-4 py-3 border-b border-[var(--chat-border)] transition-colors ${isSelected
                    ? 'bg-white/[0.07] border-l-[3px] border-l-[var(--chat-accent)]'
                    : 'hover:bg-white/[0.04] border-l-[3px] border-l-transparent'
                    }`}
                style={unreadGradient ? { background: unreadGradient } : undefined}
            >
                <div className="flex items-center gap-3 w-full">
                    {/* Avatar */}
                    <div className="relative flex-shrink-0">
                        {lead.is_pinned && (
                            <div className="absolute -top-1 -left-1 z-10 bg-[var(--chat-bg-base)] rounded-full p-[1px]">
                                <PushPin size={12} weight="fill" className="text-[var(--chat-accent)] -rotate-45" />
                            </div>
                        )}
                        <div className="w-10 h-10 rounded-full bg-[var(--chat-bg-hover)] flex items-center justify-center overflow-hidden border border-[var(--chat-bg-hover)]">
                            {lead.avatar_url ? (
                                <img src={lead.avatar_url} alt={lead.title} className="w-full h-full object-cover" />
                            ) : (
                                <span className="text-sm font-bold text-[var(--chat-accent)]">{getInitials(lead.title)}</span>
                            )}
                        </div>
                        <IntegrationBadge lead={lead} size="sm" />
                    </div>

                    {/* Text Content */}
                    <div className="flex-1 min-w-0 overflow-hidden">
                        <div className="flex items-start justify-between mb-[2px] w-full">
                            <div className="flex items-center gap-1.5 min-w-0 flex-1">
                                <LeadBadges lead={lead} size="sm" />
                                <h3 className={`text-[15px] leading-tight truncate ${lead.is_unread ? 'font-bold text-[var(--chat-text-primary)]' : 'font-medium text-[var(--chat-text-secondary)]'}`}>
                                    {formatPhone(lead.title)}
                                </h3>
                            </div>
                            <div className="flex items-center gap-2 pl-2 flex-shrink-0">
                                {lead.is_unread && (
                                    <div className="w-2 h-2 rounded-full bg-[var(--chat-accent)] flex-shrink-0" />
                                )}
                                <span className={`text-[11px] flex-shrink-0 ${lead.is_unread ? 'text-[var(--chat-accent)] font-bold' : 'text-[var(--chat-text-tertiary)] font-medium'}`}>
                                    {timeStr}
                                </span>
                            </div>
                        </div>

                        {/* Status: se um humano da equipe já respondeu, isso prevalece sobre "só contactado" */}
                        <div className="flex items-center gap-1.5">
                            {atendente && (
                                <span
                                    className="text-[9px] font-bold uppercase tracking-wide px-1.5 py-[1px] rounded-full border flex-shrink-0"
                                    style={{ color: atendente.cor, backgroundColor: atendente.cor + '1F', borderColor: atendente.cor + '66' }}
                                    title={`${atendente.nome} está atendendo`}
                                >
                                    {atendente.nome}
                                </span>
                            )}
                            <span className={`text-[9px] font-bold uppercase tracking-wide ${lead.last_message_sender_type === 'human' ? 'text-teal-500' : 'text-[var(--chat-text-tertiary)]'}`}>
                                {lead.last_message_sender_type === 'human' ? 'Respondeu (humano)' : 'Contactado'}
                            </span>
                        </div>

                        <div className="flex items-center gap-1.5 overflow-hidden w-full">
                            {SenderIcon && <SenderIcon weight="fill" className={`flex-shrink-0 ${iconColor} w-3.5 h-3.5`} />}
                            <p className={`text-[13px] truncate ${lead.is_unread ? 'text-[var(--chat-text-secondary)] font-medium' : (lastMsg ? 'text-[var(--chat-text-muted)]' : 'text-[var(--chat-text-tertiary)] italic')}`}>
                                {lastMsg}
                            </p>
                        </div>

                        {hit?.matchType === 'message' && hit.snippet && (
                            <div className="text-xs text-[var(--chat-text-muted)] italic mt-0.5 line-clamp-1">
                                <span className="text-[var(--chat-accent)] mr-1">↩</span>
                                <span dangerouslySetInnerHTML={{ __html: renderSnippet(hit.snippet, query ?? '') }} />
                            </div>
                        )}

                        {/* Order status tags + lead tags — badges de grupo/canal já saíram daqui, ficam do lado do nome */}
                        {(orderPaymentMethod || (lead.lead_tags && lead.lead_tags.length > 0)) && (
                            <div className="flex flex-wrap gap-1 mt-1.5 items-center">
                                {orderPaymentMethod && PAYMENT_METHOD_TAGS[orderPaymentMethod] && (
                                    <span className="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded-full flex-shrink-0" style={PAYMENT_METHOD_TAGS[orderPaymentMethod].style}>
                                        {PAYMENT_METHOD_TAGS[orderPaymentMethod].label}
                                    </span>
                                )}
                                {orderPaymentStatus && PAYMENT_STATUS_TAGS[orderPaymentStatus] && (
                                    <span className="text-[9px] font-bold uppercase tracking-wide px-1.5 py-0.5 rounded-full flex-shrink-0" style={PAYMENT_STATUS_TAGS[orderPaymentStatus].style}>
                                        {PAYMENT_STATUS_TAGS[orderPaymentStatus].label}
                                    </span>
                                )}
                                {lead.lead_tags && lead.lead_tags.map((lt: any) => {
                                    const tag = lt.tag
                                    if (!tag) return null
                                    const isHex = tag.color?.startsWith('#')
                                    return (
                                        <span
                                            key={lt.tag_id}
                                            className={`text-[9px] font-bold uppercase tracking-wide px-2 py-0.5 rounded-full flex items-center gap-1 ${!isHex ? tag.color : ''}`}
                                            style={isHex ? { backgroundColor: tag.color + '1A', color: tag.color } : {}}
                                        >
                                            {tag.name}
                                        </span>
                                    )
                                })}
                            </div>
                        )}
                    </div>
                </div>
            </button>
        </div>
    )
}

export default memo(LeadListItem, (prevProps, nextProps) => {
    return (
        prevProps.lead.id === nextProps.lead.id &&
        prevProps.lead.updated_at === nextProps.lead.updated_at &&
        prevProps.lead.is_unread === nextProps.lead.is_unread &&
        prevProps.lead.last_message_sender_type === nextProps.lead.last_message_sender_type &&
        prevProps.lead.integration_id === nextProps.lead.integration_id &&
        prevProps.lead.integration?.type === nextProps.lead.integration?.type &&
        prevProps.lead.is_group === nextProps.lead.is_group &&
        prevProps.lead.custom_attributes?.last_order_payment_status === nextProps.lead.custom_attributes?.last_order_payment_status &&
        prevProps.lead.custom_attributes?.last_order_payment_method === nextProps.lead.custom_attributes?.last_order_payment_method &&
        prevProps.isSelected === nextProps.isSelected &&
        prevProps.hideReplyHighlight === nextProps.hideReplyHighlight &&
        prevProps.atendente?.id === nextProps.atendente?.id &&
        prevProps.atendente?.cor === nextProps.atendente?.cor &&
        prevProps.timeStr === nextProps.timeStr &&
        prevProps.query === nextProps.query &&
        prevProps.hit?.matchType === nextProps.hit?.matchType &&
        prevProps.hit?.snippet === nextProps.hit?.snippet
    )
})
