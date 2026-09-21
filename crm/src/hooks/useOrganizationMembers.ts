'use client'

import { useEffect, useState } from 'react'
import { OrganizationMemberWithProfile } from '@/lib/types'

export function useOrganizationMembers(organizationId: string) {
  const [members, setMembers] = useState<OrganizationMemberWithProfile[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!organizationId) return
    fetchMembers()
  }, [organizationId])

  async function fetchMembers() {
    try {
      setLoading(true)
      setError(null)
      const res = await fetch('/api/users')
      if (!res.ok) throw new Error(`Failed to fetch: ${res.statusText}`)
      const data = await res.json()
      setMembers(Array.isArray(data) ? data : (data.data || []))
    } catch (err: any) {
      console.warn('[useOrganizationMembers] Fetch failed:', err)
      setMembers([])
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  return { members, loading, error, refetch: fetchMembers }
}
