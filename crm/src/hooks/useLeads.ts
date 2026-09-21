'use client'

/**
 * useLeads — substitui queries diretas ao Supabase
 * Busca leads via API route + Pusher para realtime
 */
import { useEffect, useState, useCallback } from 'react'
import { useSession } from 'next-auth/react'
import { LeadWithOwner } from '@/lib/types'
import { usePusherChannel } from './usePusher'

export function useLeads(
  organizationId: string,
  options?: { stageId?: string; memberId?: string; viewOwnOnly?: boolean; excludeGroups?: boolean }
) {
  const { data: session } = useSession()
  const [leads, setLeads] = useState<LeadWithOwner[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchLeads = useCallback(async () => {
    if (!organizationId || !session) return
    try {
      setLoading(true)
      const params = new URLSearchParams()
      if (options?.stageId) params.set('stage_id', options.stageId)
      if (options?.viewOwnOnly && options?.memberId) params.set('owner', options.memberId)
      if (options?.excludeGroups) params.set('exclude_groups', 'true')
      params.set('returnAll', 'true')

      const res = await fetch(`/api/leads?${params}`)
      if (!res.ok) throw new Error('Falha ao carregar leads')
      const json = await res.json()
      setLeads(json.data || [])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Erro desconhecido')
    } finally {
      setLoading(false)
    }
  }, [organizationId, session, options?.stageId, options?.viewOwnOnly, options?.memberId, options?.excludeGroups])

  useEffect(() => {
    fetchLeads()
  }, [fetchLeads])

  // Realtime: assinar canal da org via Pusher
  usePusherChannel(`org-${organizationId}`, {
    'lead.created': fetchLeads,
    'lead.updated': fetchLeads,
    'lead.deleted': fetchLeads,
    '__reconnected': fetchLeads,
  })

  if (options?.stageId) {
    usePusherChannel(`stage-${options.stageId}`, {
      'lead.updated': fetchLeads,
    })
  }

  const moveLeadToStage = async (leadId: string, newStageId: string) => {
    try {
      setLeads((prev) =>
        prev.map((l) => (l.id === leadId ? { ...l, stage_id: newStageId } : l))
      )
      const res = await fetch(`/api/leads/${leadId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ stage_id: newStageId, source: 'frontend_drag' }),
      })
      if (!res.ok) await fetchLeads()
    } catch {
      await fetchLeads()
    }
  }

  const updateLead = async (leadId: string, updates: Partial<LeadWithOwner>) => {
    const res = await fetch(`/api/leads/${leadId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...updates, source: 'frontend' }),
    })
    if (res.ok) await fetchLeads()
  }

  return { leads, loading, error, moveLeadToStage, updateLead, refresh: fetchLeads }
}
