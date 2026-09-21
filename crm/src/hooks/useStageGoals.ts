'use client'

import { useEffect, useState } from 'react'
import { StageGoal } from '@/lib/types'

export function useStageGoals(organizationId: string) {
  const [goals] = useState<Record<string, StageGoal>>({})
  const [loading, setLoading] = useState(false)
  const [error] = useState<string | null>(null)

  useEffect(() => {
    setLoading(false)
  }, [organizationId])

  return { goals, loading, error }
}
