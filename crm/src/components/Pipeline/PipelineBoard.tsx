'use client'

import { useState, useMemo, useCallback, useEffect, useRef } from 'react'
import { useSearchParams, useRouter } from 'next/navigation'
import {
  DndContext,
  DragOverlay,
  DragStartEvent,
  DragEndEvent,
  DragOverEvent,
  PointerSensor,
  useSensor,
  useSensors,
  pointerWithin,
  rectIntersection,
  CollisionDetection,
} from '@dnd-kit/core'
import { arrayMove } from '@dnd-kit/sortable'
import { usePipeline, useAuth, useIsMobile, useStageHistory } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePipelineFilters } from '@/contexts/FilterContext'
import { LeadWithOwner } from '@/lib/types'
import { getStageColor } from '@/lib/stageColors'
import FilterButton, { FilterState } from '@/components/Shared/FilterButton'
import StageColumn from './StageColumn'
import SourceRail from './SourceRail'
import NovoLeadImobEasy from './NovoLeadImobEasy'
import LeadCard from './LeadCard'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import { LeadDetailsSidebar } from '@/components/Chat'
import { X, Plus } from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'
import { diaEmManaus, diaEmManausMais } from '@/lib/fusoDeManaus'
import { conversaEstaNaLinha } from '@/lib/leadChannel'
import { useCaptacaoDonos } from '@/hooks/useCaptacaoDonos'
import PainelContatoParceria from '@/components/Chat/PainelContatoParceria'
import PainelContatoCaptacao from '@/components/Chat/PainelContatoCaptacao'
import EnviarImovelPelaCaptacao from '@/components/Chat/EnviarImovelPelaCaptacao'

const ORDEM_DO_FUNIL: Record<string, number> = { oficial: 0, parceria: 1, captacao: 2 }
function rotuloDoFunil(p: { name: string; settings?: any }) {
  const linha = p.settings?.linha
  return linha === 'oficial' ? 'API Oficial' : linha === 'parceria' ? 'Parceria' : linha === 'captacao' ? 'Captação' : p.name
}

// A coluna "Fonte:" não é uma etapa, então no celular ela precisa de um id
// próprio pra virar uma aba junto com as etapas de verdade. Prefixo improvável de
// colidir com um uuid do banco.
const SOURCE_TAB_ID = '__source_rail__'

interface PipelineBoardProps {
  organizationId: string
  filters?: FilterState
}

export default function PipelineBoard({ organizationId, filters }: PipelineBoardProps) {
  const searchParams = useSearchParams()
  const router = useRouter()
  const pipelineIdFromUrl = searchParams.get('pipelineId')

  const { pipelines, stages, selectedPipelineId, selectPipeline, loading } =
    usePipeline(organizationId)

  const { currentOrganization, permissions } = useAuth()

  const { leads: globalLeads, moveLeadToStage, setLeads, stageStats, refetch } = useLeadsContext()
  const { setFilters } = usePipelineFilters()

  // Apply pipeline-specific filters in memory
  const leads = useMemo(() => {
    return globalLeads.filter(l => {
      // Exclude groups from pipeline
      if (l.is_group) return false

      // Filter by permissions if needed
      if (permissions?.leads?.view_own_only && currentOrganization?.id) {
        if (l.owner_member_id !== currentOrganization.id) return false
      }

      return true
    })
  }, [globalLeads, permissions, currentOrganization])

  console.log('[PipelineBoard] pipelines length:', pipelines?.length, 'stages length:', stages?.length, 'selectedPipelineId:', selectedPipelineId);

  const activePipeline = pipelines.find(p => p.id === selectedPipelineId)
  // as abas: Oficial, Parceria, Captação (settings.linha, migração 0127) e o resto depois
  const abasDosFunis = useMemo(() => [...pipelines].sort((a, b) =>
    (ORDEM_DO_FUNIL[a.settings?.linha] ?? 9) - (ORDEM_DO_FUNIL[b.settings?.linha] ?? 9)), [pipelines])
  const trocarDeFunil = useCallback((id: string) => {
    selectPipeline(id)
    router.replace(`/pipeline?pipelineId=${id}`)
  }, [selectPipeline, router])
  const isGoalsEnabled = activePipeline?.settings?.goals_enabled || false
  const [activeLead, setActiveLead] = useState<LeadWithOwner | null>(null)
  const [activeLeadOriginalStage, setActiveLeadOriginalStage] = useState<string | null>(null)

  const isMobile = useIsMobile()
  const [activeMobileStageId, setActiveMobileStageId] = useState<string | null>(null)
  const [movingLead, setMovingLead] = useState<LeadWithOwner | null>(null)
  const [detailLead, setDetailLead] = useState<LeadWithOwner | null>(null)
  /* OS FILTROS À VISTA (Pedro, 20/10/2026: "na pipeline quero todas as etapas e tags por lá filtrando, e também filtrar
     por tempo, dia"). Etapas e etiquetas: várias marcadas = qualquer uma. Quando: pela última movimentação do lead
     (ou a criação), no dia de Manaus. Somam com o filtro do botão. */
  const [etapasSel, setEtapasSel] = useState<string[]>([])
  const [tagsSel, setTagsSel] = useState<string[]>([])
  const [quando, setQuando] = useState<'' | 'hoje' | 'ontem' | 'semana' | 'mes' | 'dia'>('')
  const [diaSel, setDiaSel] = useState('')
  const donosDaCaptacao = useCaptacaoDonos(true)

  // Lead aceso pelo clique num minicard da coluna "Fonte:". Limpa sozinho depois
  // da animação (3 pulsos de 0,75s em globals.css) — senão clicar de novo no
  // mesmo minicard não repetiria o efeito, já que a prop não mudaria de valor.
  const [highlightedLeadId, setHighlightedLeadId] = useState<string | null>(null)
  const highlightTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const handleHighlightLead = useCallback((leadId: string) => {
    if (highlightTimerRef.current) clearTimeout(highlightTimerRef.current)
    setHighlightedLeadId(null)
    // rAF garante um render com null no meio, senão o React vê o mesmo valor e
    // a animação CSS não reinicia.
    requestAnimationFrame(() => {
      setHighlightedLeadId(leadId)
      highlightTimerRef.current = setTimeout(() => setHighlightedLeadId(null), 2400)
    })
  }, [])

  useEffect(() => () => {
    if (highlightTimerRef.current) clearTimeout(highlightTimerRef.current)
  }, [])
  const { history: detailStageHistory, loading: detailHistoryLoading } = useStageHistory(detailLead?.id || '')

  // Sync URL pipelineId with selected pipeline
  useEffect(() => {
    if (pipelineIdFromUrl && pipelineIdFromUrl !== selectedPipelineId) {
      selectPipeline(pipelineIdFromUrl)
    }
  }, [pipelineIdFromUrl, selectedPipelineId, selectPipeline])

  // Mobile: garante que sempre haja uma etapa selecionada pra mostrar (a primeira, por padrão)
  useEffect(() => {
    if (stages.length === 0) return
    // Abre na PRIMEIRA ETAPA. Antes abria na coluna "Fonte:", que saiu em
    // 26/09 -- sem esta troca o celular abriria numa aba que nao existe mais
    // e a tela ficaria vazia.
    const isValid = stages.some(s => s.id === activeMobileStageId)
    if (!isValid) setActiveMobileStageId(stages[0].id)
  }, [stages, activeMobileStageId])

  /* ADICIONAR LEAD À MÃO (Tel, 26/09/2026). O botão vive no topo do quadro,
     junto do filtro, porque é de lá que se olha o funil inteiro. */
  const [abrirNovoLead, setAbrirNovoLead] = useState(false)

  const sensors = useSensors(
    useSensor(PointerSensor, {
      activationConstraint: { distance: 8 },
    })
  )

  // Filter leads to only those belonging to the selected pipeline's stages
  const stageIds = useMemo(() => new Set(stages.map((s) => s.id)), [stages])

  // Helper function to check if lead matches date filter
  const matchesDateFilter = useCallback((lead: LeadWithOwner, dateRange: FilterState['dateRange']) => {
    const leadDate = new Date(lead.created_at)
    const now = new Date()

    switch (dateRange.type) {
      case 'all':
        return true // No date filtering

      case 'today':
        const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        return leadDate >= todayStart

      case 'this_week':
        const weekStart = new Date(now)
        weekStart.setDate(now.getDate() - now.getDay()) // Start of week (Sunday)
        weekStart.setHours(0, 0, 0, 0)
        return leadDate >= weekStart

      case 'this_month':
        const monthStart = new Date(now.getFullYear(), now.getMonth(), 1)
        return leadDate >= monthStart

      case 'custom':
        if (!dateRange.startDate || !dateRange.endDate) return true
        const start = new Date(dateRange.startDate)
        const end = new Date(dateRange.endDate)
        end.setHours(23, 59, 59, 999) // Include the end date
        return leadDate >= start && leadDate <= end

      default:
        return true
    }
  }, [])

  const pipelineLeads = useMemo(() => {
    let filtered = leads.filter((l) => l.stage_id && stageIds.has(l.stage_id))

    // Apply filters only if they are explicitly set
    if (filters) {
      // 1. Filter by integrations
      if (filters.integrations && filters.integrations.length > 0) {
        filtered = filtered.filter((l) =>
          l.integration_id && filters.integrations.includes(l.integration_id)
        )
      }

      // 2. Filter by sellers (owner_member_id)
      if (filters.sellers && filters.sellers.length > 0) {
        filtered = filtered.filter((l) =>
          l.owner_member_id && filters.sellers.includes(l.owner_member_id)
        )
      }

      // 3. Filter by stages
      if (filters.stages && filters.stages.length > 0) {
        filtered = filtered.filter((l) =>
          l.stage_id && filters.stages.includes(l.stage_id)
        )
      }

      // 4. Filter by date range
      if (filters.dateRange) {
        filtered = filtered.filter((l) => matchesDateFilter(l, filters.dateRange))
      }
    }

    return filtered
  }, [leads, stageIds, filters, matchesDateFilter])

  // 20/10: as etiquetas que os leads deste funil têm (as "Nay: ..." são da Nay e não entram)
  const etiquetasDoFunil = useMemo(() => {
    const m = new Map<string, { id: string; nome: string; cor: string; n: number }>()
    for (const l of pipelineLeads) for (const lt of ((l as any).lead_tags || []) as any[]) {
      const nome = String(lt.tag?.name || '')
      if (!nome || nome.startsWith('Nay:')) continue
      const x = m.get(lt.tag_id) || { id: lt.tag_id, nome, cor: lt.tag?.color || '#64748b', n: 0 }
      x.n++
      m.set(lt.tag_id, x)
    }
    return [...m.values()].sort((a, b) => b.n - a.n || a.nome.localeCompare(b.nome, 'pt-BR'))
  }, [pipelineLeads])

  const diaDoLead = (l: LeadWithOwner) => {
    const t = new Date((l as any).last_activity_at || l.created_at)
    return Number.isNaN(t.getTime()) ? '' : diaEmManaus(t)
  }
  const passaNoQuando = useCallback((l: LeadWithOwner) => {
    if (!quando) return true
    const d = diaDoLead(l)
    if (!d) return false
    const hoje = diaEmManaus()
    if (quando === 'hoje') return d === hoje
    if (quando === 'ontem') return d === diaEmManausMais(-1)
    if (quando === 'semana') return d >= diaEmManausMais(-6) && d <= hoje
    if (quando === 'mes') return d.slice(0, 7) === hoje.slice(0, 7)
    return !!diaSel && d === diaSel
  }, [quando, diaSel])  // eslint-disable-line react-hooks/exhaustive-deps

  const leadsFiltrados = useMemo(() => pipelineLeads.filter((l) =>
    (!tagsSel.length || ((l as any).lead_tags || []).some((lt: any) => tagsSel.includes(lt.tag_id))) && passaNoQuando(l)
  ), [pipelineLeads, tagsSel, passaNoQuando])
  const etapasVisiveis = useMemo(() => (etapasSel.length ? stages.filter((s2) => etapasSel.includes(s2.id)) : stages), [stages, etapasSel])
  const contaDaEtapa = (id: string) => leadsFiltrados.filter((l) => l.stage_id === id).length

  const leadsByStage = useMemo(() => {
    return stages.reduce(
      (acc, stage) => {
        acc[stage.id] = leadsFiltrados.filter((l) => l.stage_id === stage.id)
        return acc
      },
      {} as Record<string, LeadWithOwner[]>
    )
  }, [stages, leadsFiltrados])

  // Nome e cor de cada etapa, pro minicard da coluna "Fonte:" conseguir mostrar
  // em que status o lead está sem ter que carregar as etapas por conta própria.
  const stageNameById = useMemo(
    () => Object.fromEntries(stages.map((s) => [s.id, s.name])) as Record<string, string>,
    [stages]
  )
  const stageColorById = useMemo(
    () => Object.fromEntries(
      stages.map((s, i) => [s.id, s.color || getStageColor(i).bar])
    ) as Record<string, string>,
    [stages]
  )

  // Find which stage a lead belongs to
  const findStageForLead = useCallback(
    (leadId: string): string | undefined => {
      const lead = pipelineLeads.find((l) => l.id === leadId)
      return lead?.stage_id || undefined
    },
    [pipelineLeads]
  )

  // Custom collision detection: prefer pointerWithin, fallback to rectIntersection
  const collisionDetection: CollisionDetection = useCallback(
    (args) => {
      // First try pointerWithin — most accurate for the pointer position
      const pointerCollisions = pointerWithin(args)
      if (pointerCollisions.length > 0) {
        return pointerCollisions
      }
      // Fallback to rectIntersection for edge cases
      return rectIntersection(args)
    },
    []
  )

  function handleDragStart(event: DragStartEvent) {
    const leadId = event.active.id as string
    const lead = pipelineLeads.find((l) => l.id === leadId) || null
    setActiveLead(lead)
    setActiveLeadOriginalStage(lead?.stage_id || null)
  }

  function handleDragOver(event: DragOverEvent) {
    const { active, over } = event
    if (!over) return

    const activeId = active.id as string
    const overId = over.id as string

    // Determine the stage of the active item and the over item
    const activeStageId = findStageForLead(activeId)
    let overStageId: string | undefined

    if (stageIds.has(overId)) {
      // Over a stage column directly
      overStageId = overId
    } else {
      // Over another lead card
      overStageId = findStageForLead(overId)
    }

    if (!activeStageId || !overStageId) return

    // If dragging within the same stage, handle reordering
    if (activeStageId === overStageId && !stageIds.has(overId)) {
      setLeads((prev) => {
        const oldIndex = prev.findIndex((l) => l.id === activeId)
        const newIndex = prev.findIndex((l) => l.id === overId)

        if (oldIndex === -1 || newIndex === -1) return prev

        return arrayMove(prev, oldIndex, newIndex)
      })
      return
    }

    // Cross-stage move: update stage_id in local state (real-time visual feedback)
    if (activeStageId !== overStageId) {
      setLeads((prev) =>
        prev.map((l) =>
          l.id === activeId ? { ...l, stage_id: overStageId! } : l
        )
      )
    }
  }

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event

    if (!over) {
      // Cancelled — revert to original stage
      if (activeLead && activeLeadOriginalStage) {
        setLeads((prev) =>
          prev.map((l) =>
            l.id === activeLead.id ? { ...l, stage_id: activeLeadOriginalStage } : l
          )
        )
      }
      setActiveLead(null)
      setActiveLeadOriginalStage(null)
      return
    }

    const leadId = active.id as string
    const overId = over.id as string

    // Determine target stage
    let targetStageId: string
    if (stageIds.has(overId)) {
      targetStageId = overId
    } else {
      const targetLead = pipelineLeads.find((l) => l.id === overId)
      if (!targetLead?.stage_id) {
        setActiveLead(null)
        setActiveLeadOriginalStage(null)
        return
      }
      targetStageId = targetLead.stage_id
    }

    // If dropped in same stage as original, no DB update needed (already moved in state via onDragOver)
    if (targetStageId === activeLeadOriginalStage) {
      // Just reorder within the same stage — already handled by SortableContext visually
      setActiveLead(null)
      setActiveLeadOriginalStage(null)
      return
    }

    // Persist cross-stage move to database
    if (activeLeadOriginalStage) {
      moveLeadToStage(leadId, targetStageId, activeLeadOriginalStage)
    }

    setActiveLead(null)
    setActiveLeadOriginalStage(null)
  }

  const handleMoveLead = (targetStageId: string) => {
    if (!movingLead || !movingLead.stage_id) return
    moveLeadToStage(movingLead.id, targetStageId, movingLead.stage_id)
    setMovingLead(null)
  }

  // Handlers do painel "Detalhes do contato" aberto a partir de um card — mesma lógica
  // já usada pelo Chat (chat/page.tsx), só trocando selectedLead/setSelectedLead por
  // detailLead/setDetailLead e reaproveitando moveLeadToStage/setLeads que a Pipeline
  // já busca de useLeadsContext().
  const handleDetailStageChange = useCallback(async (newStageId: string) => {
    if (!detailLead) return
    const oldStageId = detailLead.stage_id
    setDetailLead((prev) => (prev ? { ...prev, stage_id: newStageId } : prev))
    try {
      await moveLeadToStage(detailLead.id, newStageId, oldStageId)
    } catch {
      setDetailLead((prev) => (prev ? { ...prev, stage_id: oldStageId } : prev))
    }
  }, [detailLead, moveLeadToStage])

  const handleDetailPipelineChange = useCallback(async (newPipelineId: string) => {
    if (!detailLead) return
    try {
      const stagesRes = await fetch(`/api/pipelines/${newPipelineId}/stages`)
      if (!stagesRes.ok) return
      const { data: newStages } = await stagesRes.json()
      if (!newStages || newStages.length === 0) return
      await handleDetailStageChange(newStages[0].id)
    } catch (err) {
      console.error('Failed to change pipeline:', err)
    }
  }, [detailLead, handleDetailStageChange])

  const handleDetailTagsChange = useCallback((targetLeadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => {
    const applyTags = (tags: any[] | undefined) => {
      let newTags = [...(tags || [])]
      if (action === 'add') {
        if (!newTags.find((t) => t.tag_id === tagId)) newTags.push({ tag_id: tagId, tag: tagObj })
      } else {
        newTags = newTags.filter((t) => t.tag_id !== tagId)
      }
      return newTags
    }
    setLeads((prev) => prev.map((l) => (l.id === targetLeadId ? { ...l, lead_tags: applyTags(l.lead_tags) } : l)))
    setDetailLead((prev) => (prev && prev.id === targetLeadId ? { ...prev, lead_tags: applyTags(prev.lead_tags) } : prev))
  }, [setLeads])

  const handleDetailUpdateLead = useCallback((leadId: string, updates: Partial<LeadWithOwner>) => {
    setLeads((prev) => prev.map((l) => (l.id === leadId ? { ...l, ...updates } : l)))
    setDetailLead((prev) => (prev && prev.id === leadId ? { ...prev, ...updates } : prev))
  }, [setLeads])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-screen">
        <LoadingSpinner text="Carregando pipeline..." size="lg" />
      </div>
    )
  }

  return (
    <div className="flex-1 flex flex-col h-full min-h-0">
      {/* Kanban Board — largura rola no desktop (várias colunas lado a lado), altura
          é travada aqui e repassada pra baixo; quem rola de verdade é a lista de cards
          dentro de cada StageColumn, não essa página inteira. */}
      {/* Barra do quadro: um funil por número em abas (Pedro, 29/09: "vai ter uma
          pipeline para cada número, podendo serem alteradas por abas lá em cima")
          e adicionar lead à mão */}
      <div className="px-4 pt-3 flex flex-wrap items-center gap-2 flex-shrink-0">
        {abasDosFunis.length > 1 && (
          <div className="flex items-center gap-0.5 p-0.5 rounded-lg border border-line bg-panel" role="tablist" aria-label="Funil de cada número">
            {abasDosFunis.map((p) => (
              <button
                key={p.id}
                type="button"
                role="tab"
                aria-selected={p.id === selectedPipelineId}
                onClick={() => trocarDeFunil(p.id)}
                className={`px-3 py-1.5 rounded-md text-xs font-semibold transition-colors whitespace-nowrap ${p.id === selectedPipelineId
                  ? 'bg-accent/15 text-accent'
                  : 'text-ink-2 hover:text-ink hover:bg-graphite-6/40'}`}
              >
                {rotuloDoFunil(p)}
              </button>
            ))}
          </div>
        )}
        <button
          type="button"
          onClick={() => setAbrirNovoLead(true)}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold
                     bg-accent/15 border border-accent/40 text-accent hover:bg-accent/25 transition-colors"
        >
          <Plus size={14} weight="bold" /> Adicionar lead
        </button>
      </div>

      {/* 20/10: os filtros à vista -- etapas, etiquetas e quando */}
      <div className="px-4 pt-2 flex flex-col gap-1.5 flex-shrink-0 text-xs">
        <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5">
          <span className="text-muted font-semibold flex-shrink-0 w-[62px]">Etapas</span>
          <button type="button" onClick={() => setEtapasSel([])}
                  className={`flex-shrink-0 px-2.5 py-1 rounded-full border ${!etapasSel.length ? 'bg-accent/15 border-accent/40 text-accent' : 'border-line text-ink-2'}`}>
            Todas <span className="opacity-70">({leadsFiltrados.length})</span>
          </button>
          {stages.map((st) => {
            const on = etapasSel.includes(st.id)
            return (
              <button key={st.id} type="button" aria-pressed={on}
                      onClick={() => setEtapasSel((l) => (on ? l.filter((x) => x !== st.id) : [...l, st.id]))}
                      className={`flex-shrink-0 px-2.5 py-1 rounded-full border whitespace-nowrap ${on ? 'bg-accent/15 border-accent/40 text-accent' : 'border-line text-ink-2'}`}>
                {st.name} <span className="opacity-70">({contaDaEtapa(st.id)})</span>
              </button>
            )
          })}
        </div>
        {etiquetasDoFunil.length > 0 && (
          <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5">
            <span className="text-muted font-semibold flex-shrink-0 w-[62px]">Etiquetas</span>
            {etiquetasDoFunil.map((t) => {
              const on = tagsSel.includes(t.id)
              return (
                <button key={t.id} type="button" aria-pressed={on}
                        onClick={() => setTagsSel((l) => (on ? l.filter((x) => x !== t.id) : [...l, t.id]))}
                        className="flex-shrink-0 inline-flex items-center gap-1 px-2.5 py-1 rounded-full border whitespace-nowrap"
                        style={on ? { background: t.cor, borderColor: t.cor, color: '#fff' } : { borderColor: 'var(--line)' }}>
                  <span className="w-2 h-2 rounded-full" style={{ background: on ? '#fff' : t.cor }} />
                  {t.nome} <span className="opacity-70">({t.n})</span>
                </button>
              )
            })}
            {tagsSel.length > 0 && (
              <button type="button" onClick={() => setTagsSel([])} className="flex-shrink-0 px-2 py-1 text-accent font-semibold">Limpar</button>
            )}
          </div>
        )}
        <div className="flex items-center gap-1.5 overflow-x-auto pb-0.5">
          <span className="text-muted font-semibold flex-shrink-0 w-[62px]">Quando</span>
          {([['', 'Sempre'], ['hoje', 'Hoje'], ['ontem', 'Ontem'], ['semana', 'Últimos 7 dias'], ['mes', 'Este mês'], ['dia', 'Um dia']] as const).map(([k, r]) => (
            <button key={k || 'sempre'} type="button" aria-pressed={quando === k}
                    onClick={() => { setQuando(k); if (k === 'dia' && !diaSel) setDiaSel(diaEmManaus()) }}
                    className={`flex-shrink-0 px-2.5 py-1 rounded-full border ${quando === k ? 'bg-accent/15 border-accent/40 text-accent' : 'border-line text-ink-2'}`}>
              {r}
            </button>
          ))}
          {quando === 'dia' && (
            <input type="date" value={diaSel} onChange={(e) => setDiaSel(e.target.value)} aria-label="O dia"
                   className="flex-shrink-0 px-2 py-0.5 rounded-md border border-line bg-transparent text-ink" style={{ colorScheme: 'light dark' }} />
          )}
          <span className="text-muted flex-shrink-0">pela última movimentação</span>
        </div>
      </div>

      {abrirNovoLead && (
        <NovoLeadImobEasy
          etapas={stages.map((s2) => ({ id: s2.id, name: s2.name }))}
          onClose={() => setAbrirNovoLead(false)}
          onCriado={() => { if (typeof refetch === 'function') refetch() }}
        />
      )}

      <div className="flex-1 min-h-0 p-4 overflow-x-auto">
        <DndContext
          sensors={sensors}
          collisionDetection={collisionDetection}
          onDragStart={handleDragStart}
          onDragOver={handleDragOver}
          onDragEnd={handleDragEnd}
        >
          {stages.length === 0 ? (
            <div className="flex flex-col items-center justify-center h-[calc(100vh-200px)] w-full -mt-8 text-center text-muted">
              <div className="glass p-8 rounded-2xl max-w-md">
                <h3 className="text-xl font-bold text-ink mb-3">Seu pipeline está vazio</h3>
                <p className="mb-6 text-sm">Não há etapas configuradas para este pipeline. Acesse as configurações para adicionar as colunas do seu funil de vendas.</p>
                <a href="/settings/pipelines" className="btn btn-primary">
                  Configurar Funil
                </a>
              </div>
            </div>
          ) : isMobile ? (
            <div className="flex flex-col h-full min-h-0">
              {/* Filtro — some do topo desktop no celular, então reaparece aqui */}
              <div className="mb-3 flex-shrink-0">
                <FilterButton organizationId={organizationId} onFilterChange={setFilters} />
              </div>

              {/* Seletor de etapa — abas roláveis horizontalmente */}
              <div className="flex gap-2 overflow-x-auto pb-3 -mx-1 px-1 flex-shrink-0">
                {etapasVisiveis.map(stage => {
                  const count = leadsByStage[stage.id]?.length ?? 0
                  const isActive = stage.id === activeMobileStageId
                  return (
                    <button
                      key={stage.id}
                      onClick={() => setActiveMobileStageId(stage.id)}
                      className={`pill flex-shrink-0 px-3.5 py-2 text-sm ${isActive ? 'pill-active' : ''}`}
                    >
                      {stage.name} <span className="opacity-70">({count})</span>
                    </button>
                  )
                })}
              </div>

              {/* Uma etapa por vez — arrastar entre etapas não funciona bem no toque,
                  então mover um lead é feito clicando no card (abre "mover para"). */}
              <div className="flex-1 min-h-0">
                {stages.filter(s => s.id === activeMobileStageId).map(stage => (
                  <StageColumn
                    key={stage.id}
                    stage={stage}
                    leads={leadsByStage[stage.id] || []}
                    organizationId={organizationId}
                    totalLeads={leadsFiltrados.length}
                    isGoalsEnabled={isGoalsEnabled}
                    stageStats={stageStats[stage.id]}
                    highlightedLeadId={highlightedLeadId}
                    onLeadClick={setMovingLead}
                    onLeadInfoClick={setDetailLead}
                  />
                ))}
              </div>
            </div>
          ) : (
            <div className="flex gap-4 pb-4 h-full">
              {/* A coluna "Fonte:" saiu (Tel, 26/09/2026): "pode retirar aquilo
                  de fontes de dados, da pipeline era de outro projeto". As
                  fontes eram agenda_ascensao, site_evento e indicacao -- nada
                  da Imob Easy. O SourceRail continua no repositório, então
                  voltar é só recolocar estas linhas. */}
              {etapasVisiveis.map((stage) => (
                <StageColumn
                  key={stage.id}
                  stage={stage}
                  leads={leadsByStage[stage.id] || []}
                  organizationId={organizationId}
                  totalLeads={leadsFiltrados.length}
                  isGoalsEnabled={isGoalsEnabled}
                  stageStats={stageStats[stage.id]}
                  highlightedLeadId={highlightedLeadId}
                  onLeadClick={setDetailLead}
                  onLeadInfoClick={setDetailLead}
                />
              ))}
            </div>
          )}

          <DragOverlay
            dropAnimation={{
              duration: 200,
              easing: 'cubic-bezier(0.4, 0, 0.2, 1)',
            }}
          >
            {activeLead ? (
              <LeadCard
                lead={activeLead}
                organizationId={organizationId}
                isDragOverlay
              />
            ) : null}
          </DragOverlay>
        </DndContext>

      </div>

      {/* Mobile: "mover para" — alternativa ao arrastar entre etapas */}
      {movingLead && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 bg-black/55 backdrop-blur-sm">
          <div className="glass-raised rounded-2xl w-full max-w-sm">
            <div className="relative flex items-center justify-between p-5">
              <div>
                <h2 className="text-base font-bold text-ink">Mover lead</h2>
                <p className="text-xs text-muted mt-0.5 truncate">{movingLead.title}</p>
              </div>
              <button onClick={() => setMovingLead(null)} className="btn-icon w-9 h-9" aria-label="Fechar">
                <X size={20} />
              </button>
              <div className="absolute bottom-0 left-0 right-0 h-px hairline-x" />
            </div>
            <div className="p-2 max-h-[60vh] overflow-y-auto">
              {stages.map(stage => (
                <button
                  key={stage.id}
                  onClick={() => handleMoveLead(stage.id)}
                  disabled={stage.id === movingLead.stage_id}
                  className={`w-full text-left px-4 py-3 rounded-lg text-sm transition-colors border border-transparent ${
                    stage.id === movingLead.stage_id
                      ? 'text-muted cursor-default opacity-60'
                      : 'text-ink hover:bg-white/[0.06] hover:border-glass-edge'
                  }`}
                >
                  {stage.name}{stage.id === movingLead.stage_id ? ' (etapa atual)' : ''}
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Detalhes do lead — clicar num card (desktop) ou no "ⓘ" (qualquer tela) */}
      {detailLead && (
        <div className="fixed inset-0 z-50 bg-black/55 backdrop-blur-sm flex items-stretch sm:items-center sm:justify-end" onClick={() => setDetailLead(null)}>
          <div className="chat-theme flex ml-auto h-full sm:h-[92vh] sm:my-auto sm:mr-4 sm:rounded-2xl overflow-hidden shadow-2xl w-full sm:w-auto" onClick={(e) => e.stopPropagation()}>
            {/* 20/10 (Pedro: "o card lateral que abre do lead do pipeline não está igual o que está dentro do chat, deixa
                igual"): a mesma escolha do ChatWhatsApp -- Parceria, dono da captação (ou dono na Oficial) e o genérico */}
            {conversaEstaNaLinha(detailLead, 'parceria') ? (
              <PainelContatoParceria key={detailLead.id} lead={detailLead} modo="lateral" aoFechar={() => setDetailLead(null)}
                                     onTagsChange={handleDetailTagsChange} onUpdateLead={handleDetailUpdateLead} />
            ) : conversaEstaNaLinha(detailLead, 'captacao') || (conversaEstaNaLinha(detailLead, 'oficial') && donosDaCaptacao[detailLead.id]) ? (
              <PainelContatoCaptacao key={detailLead.id} lead={detailLead} modo="lateral" aoFechar={() => setDetailLead(null)}
                                     oficial={conversaEstaNaLinha(detailLead, 'oficial')} onTagsChange={handleDetailTagsChange} />
            ) : (
            <LeadDetailsSidebar
              lead={detailLead}
              stages={stages}
              stageHistory={detailStageHistory}
              stageHistoryLoading={detailHistoryLoading}
              onStageChange={handleDetailStageChange}
              onTagsChange={handleDetailTagsChange}
              onUpdateLead={handleDetailUpdateLead}
              pipelines={pipelines}
              currentPipelineId={selectedPipelineId ?? undefined}
              onPipelineChange={handleDetailPipelineChange}
              onClose={() => setDetailLead(null)}
              onGoToConversation={() => {
                setDetailLead(null)
                router.push(linkDaConversa(detailLead.id))
              }}
              extra={conversaEstaNaLinha(detailLead, 'oficial') ? (
                <div>
                  <p className="text-[11px] font-semibold uppercase tracking-wider mb-2 text-[var(--chat-text-muted)]">Enviar imóvel</p>
                  <EnviarImovelPelaCaptacao leadId={detailLead.id} telefone={detailLead.phone} oficial />
                </div>
              ) : undefined}
            />
            )}
          </div>
        </div>
      )}
    </div>
  )
}
