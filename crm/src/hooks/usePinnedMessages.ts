'use client'

import { useState, useEffect, useCallback } from 'react'
import { useSession } from 'next-auth/react'
import { PinnedMessage, LeadActivityWithActor } from '@/lib/types'
import { usePusherChannel } from './usePusher'

export function usePinnedMessages(leadId: string) {
  const { data: session } = useSession()
  const [pinned, setPinned] = useState<PinnedMessage[]>([])
  const [loading, setLoading] = useState(true)

  const fetchPinned = useCallback(async () => {
    if (!leadId || !session) return
    try {
      const res = await fetch(`/api/leads/${leadId}/pinned-messages`)
      if (!res.ok) throw new Error('Falha ao carregar mensagens fixadas')
      const json = await res.json()
      setPinned(json.data || [])
    } catch (err) {
      console.error('Failed to load pinned messages', err)
    } finally {
      setLoading(false)
    }
  }, [leadId, session])

  useEffect(() => {
    fetchPinned()
  }, [fetchPinned])

  usePusherChannel(`lead-${leadId}`, {
    'pin.created': () => fetchPinned(),
    'pin.deleted': () => fetchPinned(),
    '__reconnected': () => fetchPinned(),
  })

  const pinnedActivityIds = new Set(pinned.map((p) => p.activity_id))

  const togglePin = useCallback(async (activity: LeadActivityWithActor) => {
    const isPinned = pinnedActivityIds.has(activity.id)
    try {
      if (isPinned) {
        setPinned((prev) => prev.filter((p) => p.activity_id !== activity.id))
        await fetch(`/api/leads/${leadId}/pinned-messages/${activity.id}`, { method: 'DELETE' })
      } else {
        const optimistic: PinnedMessage = {
          id: `temp-${Date.now()}`,
          activity_id: activity.id,
          pinned_by_member_id: null,
          pinned_at: new Date().toISOString(),
          activity,
        }
        setPinned((prev) => [optimistic, ...prev])
        await fetch(`/api/leads/${leadId}/pinned-messages`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ activity_id: activity.id }),
        })
      }
      fetchPinned()
    } catch (err) {
      console.error('Failed to toggle pin', err)
      fetchPinned()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [leadId, pinned, fetchPinned])

  return { pinned, pinnedActivityIds, loading, togglePin }
}
