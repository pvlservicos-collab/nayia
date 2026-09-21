'use client'

import { memo, useCallback, useEffect, useRef } from 'react'

import { useSortable } from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { Info, ShoppingBag, InstagramLogo } from '@phosphor-icons/react'
import { LeadWithOwner } from '@/lib/types'
import { formatPhone } from '@/lib/utils'
import Avatar from '@/components/Shared/Avatar'
import IntegrationBadge from '@/components/Shared/IntegrationBadge'

interface LeadCardProps {
  lead: LeadWithOwner
  organizationId: string
  isDragOverlay?: boolean
  stageColor?: string
  onClick?: () => void
  /** Abre os detalhes do lead — separado do onClick porque no mobile o card inteiro já
   * é usado pra abrir "mover para etapa" (arrastar é ruim no touch); esse botão dá um
   * jeito de ver/editar informações sem competir com aquele clique. */
  onInfoClick?: () => void
  /** Pisca o card — usado ao clicar no minicard deste lead na coluna "Fonte:". */
  isHighlighted?: boolean
}

const LeadCard = ({ lead, isDragOverlay, stageColor, onClick, onInfoClick, isHighlighted }: LeadCardProps) => {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({
    id: lead.id,
  })

  // Rolar até o card destacado — sem isso o piscar não serve pra nada quando o
  // lead está fora da parte visível da coluna, que é o caso comum numa coluna
  // com dezenas de leads. O ref é composto porque o dnd-kit também precisa do
  // seu (setNodeRef é um callback ref, então dá pra chamar os dois).
  const nodeRef = useRef<HTMLDivElement | null>(null)
  const setRefs = useCallback((node: HTMLDivElement | null) => {
    nodeRef.current = node
    setNodeRef(node)
  }, [setNodeRef])

  useEffect(() => {
    if (!isHighlighted) return
    nodeRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })
  }, [isHighlighted])

  // Produto(s) comprados pelo lead. Vem denormalizado em custom_attributes
  // (gravado por syncLeadLastOrderAttributes quando o pedido é criado ou tem o
  // pagamento atualizado) — o Pipeline carrega centenas de leads e não toca na
  // tabela de pedidos, então juntar orders + order_items por card sairia caro.
  //
  // A etiqueta só aparece com o pagamento em 'paid'. Um pedido existe desde o
  // momento em que é montado, ainda pendente — e quem só tem pedido pendente
  // NÃO comprou, então não pode carregar a etiqueta de produto comprado.
  const boughtProducts = (() => {
    if (lead.custom_attributes?.last_order_payment_status !== 'paid') return []
    const value = lead.custom_attributes?.last_order_products
    if (!Array.isArray(value)) return []
    return value.filter((name): name is string => typeof name === 'string' && name.trim() !== '')
  })()

  // Format phone if it falls back to it
  const formattedPhone = lead.phone ? formatPhone(lead.phone) : ''
  const description = lead.last_message_content || lead.ai_next_action_short || lead.email || formattedPhone || ''



  const style = isDragOverlay
    ? undefined
    : {
      transform: CSS.Transform.toString(transform),
      transition,
      opacity: isDragging ? 0.4 : 1,
      '--stage-color': stageColor,
    } as React.CSSProperties & { '--stage-color'?: string }

  return (
    <div
      ref={setRefs}
      {...listeners}
      {...attributes}
      onClick={onClick}
      style={style}
      className={`
        panel glass-hover rounded-xl p-4 relative overflow-hidden
        ${isHighlighted ? 'lead-card-flash' : ''}
        outline-none focus:outline-none focus-visible:outline-none
        ${isDragOverlay
          ? 'rotate-2 scale-105 cursor-grabbing shadow-glass-lg'
          : 'cursor-grab active:cursor-grabbing group'
        }
      `}
    >
      {/* Left colored border on hover - 4px width */}
      {!isDragOverlay && stageColor && (
        <div
          className="absolute left-0 top-0 bottom-0 w-1 opacity-0 group-hover:opacity-100 transition-opacity duration-200"
          style={{ background: `linear-gradient(180deg, ${stageColor}, ${stageColor}33)` }}
        />
      )}

      <div className="flex gap-3 relative z-10 w-full">
        {/* Avatar */}
        <Avatar
          name={lead.title || 'Unknown'}
          imageUrl={lead.avatar_url}
          size="sm"
          className="flex-shrink-0 mt-0.5"
          badge={<IntegrationBadge lead={lead} size="sm" />}
        />

        {/* Detail Column */}
        <div className="flex-1 min-w-0 flex flex-col pt-0.5">
          {/* Header row */}
          <div className="flex items-start justify-between mb-0.5">
            <h4 className="font-semibold text-sm text-ink truncate pr-2">
              {formatPhone(lead.title)}
            </h4>
            {onInfoClick && !isDragOverlay && (
              <button
                type="button"
                onClick={(e) => {
                  e.stopPropagation()
                  onInfoClick()
                }}
                onPointerDown={(e) => e.stopPropagation()}
                className="btn-icon w-6 h-6 rounded-full flex-shrink-0"
                title="Ver detalhes do lead"
              >
                <Info size={16} />
              </button>
            )}
          </div>

          {/* @usuário do Instagram — só quando o lead veio de lá (ver custom_attributes
              em src/app/api/webhooks/facebook/route.ts) */}
          {lead.custom_attributes?.instagram_username && (
            <div className="flex items-center gap-1 text-[11px] text-muted mb-1 truncate">
              <InstagramLogo size={11} className="flex-shrink-0" />
              <span className="truncate">@{lead.custom_attributes.instagram_username}</span>
            </div>
          )}

          {/* Last message row */}
          <div className="text-[12px] text-muted mb-2 truncate">
            {description}
          </div>

          {/* Etiquetas: produto comprado primeiro (sinal mais forte do card),
              depois as tags manuais. Verde e o icone separam uma da outra. */}
          {(boughtProducts.length > 0 || (lead.lead_tags && lead.lead_tags.length > 0)) && (
            <div className="flex flex-wrap gap-1.5 mt-auto">
              {boughtProducts.map((name) => (
                <span
                  key={name}
                  className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[9px] font-bold uppercase tracking-wide bg-emerald-500/12 border border-emerald-500/30 text-emerald-300 max-w-full"
                  title={`Comprou: ${name}`}
                >
                  <ShoppingBag size={10} weight="fill" className="flex-shrink-0" />
                  <span className="truncate">{name}</span>
                </span>
              ))}
              {lead.lead_tags?.slice(0, 3).map((lt) => (
                <span
                  key={lt.tag_id}
                  className="px-2 py-0.5 rounded-full text-[9px] font-bold uppercase tracking-wide"
                  style={{
                    backgroundColor: lt.tag.color + '1A',
                    color: lt.tag.color,
                  }}
                >
                  {lt.tag.name}
                </span>
              ))}
              {(lead.lead_tags?.length ?? 0) > 3 && (
                <span className="text-[10px] text-muted self-center">
                  +{(lead.lead_tags?.length ?? 0) - 3}
                </span>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

export default memo(LeadCard, (prevProps, nextProps) => {
  return (
    prevProps.lead.id === nextProps.lead.id &&
    prevProps.lead.updated_at === nextProps.lead.updated_at &&
    prevProps.lead.custom_attributes?.last_order_products ===
      nextProps.lead.custom_attributes?.last_order_products &&
    prevProps.lead.custom_attributes?.last_order_payment_status ===
      nextProps.lead.custom_attributes?.last_order_payment_status &&
    prevProps.lead.custom_attributes?.instagram_username ===
      nextProps.lead.custom_attributes?.instagram_username &&
    prevProps.isDragOverlay === nextProps.isDragOverlay &&
    prevProps.isHighlighted === nextProps.isHighlighted &&
    prevProps.stageColor === nextProps.stageColor &&
    prevProps.lead.stage_id === nextProps.lead.stage_id
  )
})
