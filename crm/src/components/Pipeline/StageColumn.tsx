'use client'

import { useDroppable } from '@dnd-kit/core'
import { SortableContext, verticalListSortingStrategy } from '@dnd-kit/sortable'
import { PipelineStage, LeadWithOwner, StageGoal } from '@/lib/types'
import { getStageColor } from '@/lib/stageColors'
import LeadCard from './LeadCard'
import { useMemo, useRef, useState, useEffect } from 'react'

interface StageColumnProps {
  stage: PipelineStage
  leads: LeadWithOwner[]
  organizationId: string
  totalLeads: number
  isGoalsEnabled: boolean
  stageStats?: { count: number; totalValue: number }
  /** Mobile: abre o seletor de "mover para" em vez de depender de arrastar. */
  onLeadClick?: (lead: LeadWithOwner) => void
  /** Botão "ⓘ" do card — abre os detalhes do lead (funciona em mobile e desktop, mesmo quando onLeadClick já está sendo usado pra outra coisa). */
  onLeadInfoClick?: (lead: LeadWithOwner) => void
  /** Lead a destacar — o card dele pisca. Vem do clique num minicard da coluna "Fonte:". */
  highlightedLeadId?: string | null
}

const INITIAL_DISPLAY = 30
const DISPLAY_INCREMENT = 40

export default function StageColumn({
  stage,
  leads,
  organizationId,
  totalLeads,
  isGoalsEnabled,
  stageStats,
  onLeadClick,
  onLeadInfoClick,
  highlightedLeadId,
}: StageColumnProps) {
  const { setNodeRef } = useDroppable({ id: stage.id })
  const fallbackColor = getStageColor(stage.rank)
  const stageColor = stage.color || fallbackColor.bar

  // Use DB stats for header display; fallback to loaded leads for backwards compatibility
  const displayCount = stageStats?.count ?? leads.length
  const displayValue = stageStats?.totalValue ?? leads.reduce((sum, lead) => sum + (lead.value || 0), 0)

  // Use target_volume from database or fallback to 0
  const goalLeads = stage.target_volume || 0
  const progressPercentage = goalLeads > 0 ? Math.min((displayCount / goalLeads) * 100, 100) : 0

  // Cada coluna rola (e "carrega mais") por conta própria — antes era um número
  // compartilhado por todas as colunas, escutando o scroll da página inteira; agora
  // cada uma tem seu próprio scroll interno, então cada uma cuida do seu próprio
  // limite. Mesmo padrão de LeadList.tsx (ref na própria div que rola). Sem pegadinha
  // de timing tipo a que existia na Pipeline antes: essa coluna só monta depois que os
  // dados já carregaram, então a ref já existe desde o primeiro render.
  const scrollContainerRef = useRef<HTMLDivElement>(null)
  const [displayLimit, setDisplayLimit] = useState(INITIAL_DISPLAY)

  useEffect(() => {
    const el = scrollContainerRef.current
    if (!el) return

    const onScroll = () => {
      const { scrollTop, scrollHeight, clientHeight } = el
      if (scrollHeight - scrollTop - clientHeight < 300) {
        setDisplayLimit((prev) => prev + DISPLAY_INCREMENT)
      }
    }

    el.addEventListener('scroll', onScroll, { passive: true })
    return () => el.removeEventListener('scroll', onScroll)
  }, [])

  // Slice leads to respect the per-stage display limit
  const visibleLeads = leads.slice(0, displayLimit)

  // Memoize item ids to prevent SortableContext from infinite re-rendering
  const itemIds = useMemo(() => visibleLeads.map((l) => l.id), [visibleLeads])

  return (
    <div
      ref={setNodeRef}
      className="glass-sunken rounded-2xl flex-shrink-0 w-full md:w-[280px] h-full min-h-0 flex flex-col p-2"
    >
      {/* Stage Header */}
      <div className="mb-3 px-2 pt-1">
        <div className="flex items-center justify-between mb-0.5">
          <h3
            className="uppercase font-bold text-[12.5px] tracking-wider transition-colors"
            style={{ color: stageColor }}
          >
            {stage.name}
          </h3>
          <button className="btn-icon w-6 h-6 rounded-md focus:outline-none">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
              <circle cx="8" cy="3" r="1.5" />
              <circle cx="8" cy="8" r="1.5" />
              <circle cx="8" cy="13" r="1.5" />
            </svg>
          </button>
        </div>

        <div className="flex items-baseline gap-1 text-[11px] text-muted font-medium">
          <span className="text-[17px] font-black text-ink leading-none">
            {displayCount.toString().padStart(2, '0')}
          </span>
          <span>
            leads • R$ {displayValue.toLocaleString('pt-BR')}
          </span>
        </div>
        {/* Progress bar / Underline */}
        {isGoalsEnabled && goalLeads > 0 ? (
          <div className="w-full h-[3px] bg-black/40 rounded-full overflow-hidden mt-3 mb-1 ring-1 ring-white/5">
            <div
              className="h-full rounded-full transition-all duration-500 ease-out"
              style={{
                width: `${progressPercentage}%`,
                background: `linear-gradient(90deg, ${stageColor}99, ${stageColor})`,
              }}
            />
          </div>
        ) : (
          <div
            className="w-full h-[2px] rounded-full mt-3 mb-1"
            style={{ background: `linear-gradient(90deg, ${stageColor}55, ${stageColor}11)` }}
          />
        )}
      </div>

      {/* Leads List */}
      <SortableContext
        items={itemIds}
        strategy={verticalListSortingStrategy}
      >
        <div
          ref={scrollContainerRef}
          className="space-y-3 flex-1 min-h-0 px-1 pb-1 overflow-y-auto scrollbar-hide"
        >
          {visibleLeads.length === 0 ? (
            <div className="text-center py-8 text-muted text-sm">
              Sem leads
            </div>
          ) : (
            visibleLeads.map((lead) => (
              <LeadCard
                key={lead.id}
                lead={lead}
                organizationId={organizationId}
                stageColor={stageColor}
                isHighlighted={highlightedLeadId === lead.id}
                onClick={onLeadClick ? () => onLeadClick(lead) : undefined}
                onInfoClick={onLeadInfoClick ? () => onLeadInfoClick(lead) : undefined}
              />
            ))
          )}
        </div>
      </SortableContext>
    </div>
  )
}
