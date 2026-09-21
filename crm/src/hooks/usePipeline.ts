'use client'

import { useEffect, useState } from 'react'
import { Pipeline, PipelineStage } from '@/lib/types'

const EMPTY_ARRAY: PipelineStage[] = []

// Dedup fetches de /api/pipelines quando mais de um componente monta usePipeline()
// pro mesmo org ao mesmo tempo (ex: Navbar + PipelineBoard em /pipeline) — o segundo
// reaproveita a mesma promise em vez de disparar outra requisição idêntica.
const inFlightPipelinesRequests = new Map<string, Promise<any>>()

function fetchPipelinesDeduped(organizationId: string): Promise<any> {
  const existing = inFlightPipelinesRequests.get(organizationId)
  if (existing) return existing

  const promise = fetch('/api/pipelines')
    .then(res => {
      if (!res.ok) throw new Error('Failed to fetch pipelines')
      return res.json()
    })
    .finally(() => inFlightPipelinesRequests.delete(organizationId))

  inFlightPipelinesRequests.set(organizationId, promise)
  return promise
}

export function usePipeline(organizationId: string) {
  const [pipelines, setPipelines] = useState<Pipeline[]>([])
  const [stages, setStages] = useState<Record<string, PipelineStage[]>>({})
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedPipelineId, setSelectedPipelineId] = useState<string | null>(null)

  useEffect(() => {
    if (!organizationId) return
    fetchPipelines()
  }, [organizationId])

  async function fetchPipelines() {
    try {
      setLoading(true)
      setError(null)
      const { data } = await fetchPipelinesDeduped(organizationId)
      setPipelines(data || [])
      if (data && data.length > 0) {
        setSelectedPipelineId(data[0].id)
        const stagesMap: Record<string, PipelineStage[]> = {}
        for (const p of data) {
          stagesMap[p.id] = p.stages || []
        }
        setStages(stagesMap)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch pipelines')
    } finally {
      setLoading(false)
    }
  }

  async function fetchStages(pipelineId: string) {
    try {
      const res = await fetch(`/api/pipelines/${pipelineId}/stages`)
      if (!res.ok) return
      const { data } = await res.json()
      setStages(prev => ({ ...prev, [pipelineId]: data || [] }))
    } catch (err) {
      console.error('Failed to fetch stages:', err)
    }
  }

  async function selectPipeline(pipelineId: string) {
    setSelectedPipelineId(pipelineId)
    if (!stages[pipelineId]) await fetchStages(pipelineId)
  }

  async function createPipeline(name: string) {
    try {
      const res = await fetch('/api/pipelines', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, source: 'manual' }),
      })
      if (!res.ok) throw new Error('Failed to create pipeline')
      const { data } = await res.json()
      setPipelines(prev => [...prev, data])
      setSelectedPipelineId(data.id)
      setStages(prev => ({ ...prev, [data.id]: [] }))
      return data
    } catch (err) {
      console.error('Failed to create pipeline:', err)
      throw err
    }
  }

  async function updatePipeline(pipelineId: string, updates: Partial<Pipeline>) {
    try {
      const res = await fetch(`/api/pipelines/${pipelineId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updates),
      })
      if (!res.ok) throw new Error('Failed to update pipeline')
      const { data } = await res.json()
      setPipelines(prev => prev.map(p => p.id === pipelineId ? data : p))
      return data
    } catch (err) {
      console.error('Failed to update pipeline:', err)
      throw err
    }
  }

  async function updatePipelineSettings(pipelineId: string, settings: any) {
    return updatePipeline(pipelineId, { settings } as any)
  }

  async function deletePipeline(pipelineId: string) {
    try {
      const res = await fetch(`/api/pipelines/${pipelineId}`, { method: 'DELETE' })
      if (!res.ok) {
        const { error } = await res.json()
        throw new Error(error || 'Não é possível excluir um pipeline que contém leads ativos.')
      }
      setPipelines(prev => prev.filter(p => p.id !== pipelineId))
      if (selectedPipelineId === pipelineId) setSelectedPipelineId(null)
    } catch (err) {
      console.error('Failed to delete pipeline:', err)
      throw err
    }
  }

  async function createStage(pipelineId: string, name: string) {
    try {
      const currentStages = stages[pipelineId] || []
      const rank = currentStages.length > 0 ? Math.max(...currentStages.map(s => s.rank)) + 10 : 1000
      const res = await fetch(`/api/pipelines/${pipelineId}/stages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, rank }),
      })
      if (!res.ok) throw new Error('Failed to create stage')
      const { data } = await res.json()
      setStages(prev => ({ ...prev, [pipelineId]: [...(prev[pipelineId] || []), data] }))
      return data
    } catch (err) {
      console.error('Failed to create stage:', err)
      throw err
    }
  }

  async function updateStage(stageId: string, pipelineId: string, updates: Partial<PipelineStage>) {
    try {
      const res = await fetch(`/api/pipelines/stages/${stageId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updates),
      })
      if (!res.ok) throw new Error('Failed to update stage')
      const { data } = await res.json()
      setStages(prev => ({
        ...prev,
        [pipelineId]: prev[pipelineId]?.map(s => s.id === stageId ? data : s) || [],
      }))
      return data
    } catch (err) {
      console.error('Failed to update stage:', err)
      throw err
    }
  }

  async function deleteStage(stageId: string, pipelineId: string) {
    try {
      const res = await fetch(`/api/pipelines/stages/${stageId}`, { method: 'DELETE' })
      if (!res.ok) {
        const { error } = await res.json()
        throw new Error(error || 'Não é possível excluir uma etapa que contém leads.')
      }
      setStages(prev => ({ ...prev, [pipelineId]: prev[pipelineId]?.filter(s => s.id !== stageId) || [] }))
    } catch (err) {
      console.error('Failed to delete stage:', err)
      throw err
    }
  }

  async function reorderStages(pipelineId: string, newStages: PipelineStage[]) {
    setStages(prev => ({ ...prev, [pipelineId]: newStages }))
    try {
      await Promise.all(
        newStages.map(stage =>
          fetch(`/api/pipelines/stages/${stage.id}`, {
            method: 'PATCH',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ rank: stage.rank }),
          })
        )
      )
    } catch (err) {
      console.error('Failed to reorder stages:', err)
      await fetchStages(pipelineId)
      throw err
    }
  }

  return {
    pipelines,
    stages: selectedPipelineId ? stages[selectedPipelineId] || EMPTY_ARRAY : EMPTY_ARRAY,
    stagesMap: stages,
    selectedPipelineId,
    selectPipeline,
    createPipeline,
    updatePipeline,
    deletePipeline,
    updatePipelineSettings,
    createStage,
    updateStage,
    deleteStage,
    reorderStages,
    fetchPipelines,
    loading,
    error,
  }
}
