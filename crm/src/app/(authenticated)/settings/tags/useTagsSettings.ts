import { useState, useEffect, useCallback } from 'react'
import { Tag } from '@/lib/types'

export interface TagWithStats extends Tag {
  activeLeadsCount: number
}

export function useTagsSettings(organizationId: string | null | undefined) {
  const [tags, setTags] = useState<TagWithStats[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  const fetchTags = useCallback(async () => {
    if (!organizationId) { setTags([]); setLoading(false); return }
    setLoading(true)
    try {
      const res = await fetch('/api/tags')
      if (!res.ok) throw new Error('Failed to fetch tags')
      const { data } = await res.json()
      const formattedTags: TagWithStats[] = (data || []).map((tag: any) => ({ ...tag, activeLeadsCount: 0 }))
      setTags(formattedTags)
    } catch (err: any) {
      console.error('Error fetching tags settings:', err)
      setError(err)
    } finally {
      setLoading(false)
    }
  }, [organizationId])

  useEffect(() => { fetchTags() }, [fetchTags])

  const createTag = async (data: { name: string; color: string }) => {
    if (!organizationId) throw new Error('No organization selected')
    const res = await fetch('/api/tags', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...data, source: 'settings' }),
    })
    if (!res.ok) throw new Error('Failed to create tag')
    const { data: newTag } = await res.json()
    setTags(prev => [{ ...newTag, activeLeadsCount: 0 }, ...prev])
    return newTag
  }

  const updateTag = async (id: string, data: { name: string; color: string }) => {
    if (!organizationId) throw new Error('No organization selected')
    const res = await fetch(`/api/tags?id=${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    })
    if (!res.ok) throw new Error('Failed to update tag')
    const { data: updatedTag } = await res.json()
    setTags(prev => prev.map(tag => tag.id === id ? { ...tag, ...updatedTag } : tag))
    return updatedTag
  }

  const deleteTag = async (id: string) => {
    if (!organizationId) throw new Error('No organization selected')
    const res = await fetch(`/api/tags?id=${id}`, { method: 'DELETE' })
    if (!res.ok) throw new Error('Failed to delete tag')
    setTags(prev => prev.filter(tag => tag.id !== id))
  }

  return { tags, loading, error, createTag, updateTag, deleteTag, refreshTags: fetchTags }
}
