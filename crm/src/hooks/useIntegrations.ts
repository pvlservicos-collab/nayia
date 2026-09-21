'use client'

import { useEffect, useState } from 'react'
import { Integration } from '@/lib/types'

export function useIntegrations(organizationId: string) {
  const [integrations, setIntegrations] = useState<Integration[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!organizationId) { setLoading(false); return }
    fetchIntegrations()
  }, [organizationId])

  async function fetchIntegrations() {
    try {
      setLoading(true)
      setError(null)
      const res = await fetch('/api/integrations')
      if (!res.ok) { setIntegrations([]); return }
      const { data } = await res.json()
      setIntegrations((data as Integration[]) || [])
    } catch (err) {
      console.warn('[useIntegrations] Fetch failed:', err)
      setIntegrations([])
    } finally {
      setLoading(false)
    }
  }

  return { integrations, loading, error }
}
