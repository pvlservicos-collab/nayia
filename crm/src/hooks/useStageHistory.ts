'use client'

import { useEffect, useState } from 'react'
import { LeadStageHistory } from '@/lib/types'

export function useStageHistory(leadId: string) {
  const [history, setHistory] = useState<LeadStageHistory[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    if (!leadId) { setLoading(false); return }
    // Trocou de conversa no meio da busca: a resposta da anterior é descartada,
    // senão o histórico de uma pessoa aparecia no perfil de outra.
    let valendo = true
    setHistory([])
    setLoading(true)
    ;(async () => {
      try {
        const res = await fetch(`/api/leads/${leadId}/stage-history`)
        const data = res.ok ? (await res.json()).data : []
        if (valendo) setHistory(data || [])
      } catch (err) {
        console.error('Failed to fetch stage history:', err)
      } finally {
        if (valendo) setLoading(false)
      }
    })()
    return () => { valendo = false }
  }, [leadId])

  return { history, loading }
}
