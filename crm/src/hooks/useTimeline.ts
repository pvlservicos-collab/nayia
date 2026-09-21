'use client'

import { useEffect, useState, useCallback } from 'react'
import { LeadActivityWithActor } from '@/lib/types'

export function useTimeline(leadId: string) {
  const [activities, setActivities] = useState<LeadActivityWithActor[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!leadId) return
    fetchActivities()
  }, [leadId])

  async function fetchActivities() {
    try {
      setLoading(true)
      setError(null)
      const res = await fetch(`/api/leads/${leadId}/activities`)
      if (!res.ok) throw new Error('Failed to fetch activities')
      const { data } = await res.json()
      setActivities(data || [])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch activities')
    } finally {
      setLoading(false)
    }
  }

  const addActivity = useCallback(
    async (
      organizationId: string,
      type: 'whatsapp' | 'note' | 'call' | 'email' | 'system',
      content: string,
      actorMemberId: string,
      metadata?: Record<string, any>
    ) => {
      try {
        const res = await fetch(`/api/leads/${leadId}/activities`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ type, content, metadata }),
        })
        if (!res.ok) throw new Error('Failed to add activity')
        const { data } = await res.json()
        setActivities(prev => [...prev, data as LeadActivityWithActor])
        return data
      } catch (err) {
        console.error('Failed to add activity:', err)
        throw err
      }
    },
    [leadId]
  )

  return { activities, loading, error, addActivity }
}
