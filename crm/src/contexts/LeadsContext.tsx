'use client'

import React, { createContext, useContext, useState, useEffect, useCallback, useRef, ReactNode } from 'react'
import { LeadWithOwner } from '@/lib/types'
import { useAuth } from '@/hooks'
import { usePusherChannel } from '@/hooks/usePusher'
import { useAtualizacaoPeriodica } from '@/hooks/useAtualizacaoPeriodica'

interface StageStats {
  count: number
  totalValue: number
}

interface LeadsContextType {
  leads: LeadWithOwner[]
  setLeads: React.Dispatch<React.SetStateAction<LeadWithOwner[]>>
  loading: boolean
  error: string | null
  stageStats: Record<string, StageStats>
  moveLeadToStage: (leadId: string, newStageId: string, oldStageId?: string, memberId?: string) => Promise<void>
  /**
   * Recarrega a lista sem piscar a tela.
   *
   * Quem cadastra um lead à mão (a fonte "Indicação", no Pipeline) precisa ver
   * o card aparecer na hora. A entrada por ingestão não passa pelo realtime que
   * atualiza esta lista sozinha, então quem grava avisa daqui.
   */
  refetch: () => Promise<void>
}

const LeadsContext = createContext<LeadsContextType | undefined>(undefined)

/**
 * Que fatia da base esta tela precisa.
 *
 * `conversas` pro Chat, `funil` pro Pipeline, `tudo` pra quem precisar mesmo de
 * tudo. Antes toda tela baixava tudo: 2.366 leads pra desenhar 82 conversas.
 */
export type EscopoLeads = 'conversas' | 'funil' | 'tudo'

export function LeadsProvider({ children, escopo = 'tudo' }: { children: ReactNode; escopo?: EscopoLeads }) {
  const { currentOrganization, permissions } = useAuth()
  const [leads, setLeads] = useState<LeadWithOwner[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [stageStats, setStageStats] = useState<Record<string, StageStats>>({})

  const organizationId = currentOrganization?.organization_id
  // Última lista recebida, pra não redesenhar a tela quando nada mudou — a
  // lista é buscada a cada poucos segundos e quase sempre vem igual.
  const ultimaAssinatura = useRef('')

  async function fetchLeads(showLoading = true) {
    if (!organizationId) { setLoading(false); return }
    try {
      if (showLoading) setLoading(true)
      setError(null)
      const viewOwnOnly = permissions?.leads?.view_own_only
      const memberId = currentOrganization?.id
      // Grupos entram na lista (o Chat precisa deles); quem não quer ver grupo
      // (Pipeline) já filtra por conta própria em PipelineBoard.tsx.
      const params = new URLSearchParams({ returnAll: 'true' })
      if (escopo !== 'tudo') params.set('scope', escopo)
      if (viewOwnOnly && memberId) params.set('owner', memberId)
      const res = await fetch(`/api/leads?${params}`)
      if (!res.ok) throw new Error('Failed to fetch leads')
      const { data } = await res.json()
      const assinatura = JSON.stringify(data || [])
      if (assinatura === ultimaAssinatura.current) return
      ultimaAssinatura.current = assinatura
      setLeads(data || [])

      // Compute stage stats — grupo não conta pra estatística do Pipeline
      const stats: Record<string, StageStats> = {}
      for (const lead of (data || [])) {
        if (!lead.stage_id || lead.is_group) continue
        if (!stats[lead.stage_id]) stats[lead.stage_id] = { count: 0, totalValue: 0 }
        stats[lead.stage_id].count++
        stats[lead.stage_id].totalValue += lead.value || 0
      }
      setStageStats(stats)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch leads')
    } finally {
      if (showLoading) setLoading(false)
    }
  }

  useEffect(() => {
    fetchLeads()
  }, [organizationId, currentOrganization?.id])

  // Real-time via Pusher
  /*
   * Atualização automática: é o que faz a conversa que acabou de receber
   * mensagem subir pro topo sozinha (a lista é ordenada pela última atividade)
   * e conversa nova aparecer sem recarregar.
   *
   * ERA DE 6 EM 6 SEGUNDOS porque o app do Pusher não existia mais e a busca
   * periódica era a única coisa que atualizava. O Tel criou o app em
   * 25/09/2026, então o tempo real voltou a funcionar e a busca vira o que ela
   * deveria ser: uma REDE DE SEGURANÇA, não o mecanismo.
   *
   * Por que isso pesava: `returnAll=true` traz a lista INTEIRA, sem limite, e
   * a cada volta o navegador ainda fazia `JSON.stringify` dela só pra comparar.
   * Dez vezes por minuto, numa máquina de 2 CPUs que também roda a Nay.
   *
   * Sem Pusher configurado, continua nos 6 segundos de antes — nada regride.
   */
  const temPusher = !!process.env.NEXT_PUBLIC_PUSHER_KEY
  useAtualizacaoPeriodica(() => fetchLeads(false), temPusher ? 60000 : 6000,
                          { ativo: !!organizationId })

  usePusherChannel(
    organizationId ? `org-${organizationId}` : '',
    {
      'lead.created': () => fetchLeads(false),
      'lead.updated': () => fetchLeads(false),
      'lead.deleted': (data: any) => {
        if (data?.id) setLeads(prev => prev.filter(l => l.id !== data.id))
      },
      '__reconnected': () => fetchLeads(false),
    }
  )

  const moveLeadToStage = useCallback(
    async (leadId: string, newStageId: string, oldStageId?: string) => {
      setLeads(prev => prev.map(l => l.id === leadId ? { ...l, stage_id: newStageId } : l))
      try {
        const res = await fetch(`/api/leads/${leadId}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ stage_id: newStageId }),
        })
        if (!res.ok) throw new Error('Failed to update lead stage')
      } catch (err) {
        console.error('Failed to update lead stage:', err)
        if (oldStageId) {
          setLeads(prev => prev.map(l => l.id === leadId ? { ...l, stage_id: oldStageId } : l))
        }
        throw err
      }
    },
    [organizationId]
  )

  return (
    <LeadsContext.Provider value={{ leads, setLeads, loading, error, stageStats, moveLeadToStage, refetch: () => fetchLeads(false) }}>
      {children}
    </LeadsContext.Provider>
  )
}

export function useLeadsContext() {
  const context = useContext(LeadsContext)
  if (context === undefined) throw new Error('useLeadsContext must be used within a LeadsProvider')
  return context
}
