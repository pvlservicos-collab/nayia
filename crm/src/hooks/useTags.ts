import { useState, useEffect } from 'react'
import { Tag } from '@/lib/types'

export function useTags(organizationId: string | null | undefined, leadId?: string | null) {
  const [allTags, setAllTags] = useState<Tag[]>([])
  const [leadTags, setLeadTags] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<Error | null>(null)

  useEffect(() => {
    if (!organizationId) {
      setAllTags([])
      setLeadTags([])
      setLoading(false)
      return
    }
    fetchTags()
  }, [organizationId, leadId])

  async function fetchTags() {
    setLoading(true)
    try {
      const res = await fetch('/api/tags')
      if (!res.ok) throw new Error('Failed to fetch tags')
      const { data } = await res.json()
      setAllTags(data || [])

      if (leadId) {
        const ltRes = await fetch(`/api/leads/${leadId}/tags`)
        if (ltRes.ok) {
          const { data: ltData } = await ltRes.json()
          setLeadTags(ltData || [])
        }
      } else {
        setLeadTags([])
      }
    } catch (err: any) {
      console.error('Error fetching tags:', err)
      setError(err)
    } finally {
      setLoading(false)
    }
  }

  const addTagToLead = async (tagId: string) => {
    if (!organizationId || !leadId) return
    const tag = allTags.find(t => t.id === tagId)
    if (tag && !leadTags.find(lt => lt.tag_id === tagId)) {
      setLeadTags(prev => [...prev, { tag_id: tagId, tag }])
    }
    try {
      const res = await fetch(`/api/leads/${leadId}/tags`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tag_id: tagId }),
      })
      if (!res.ok) {
        setLeadTags(prev => prev.filter(lt => lt.tag_id !== tagId))
      }
    } catch (err: any) {
      console.error('Error adding tag:', err)
      setLeadTags(prev => prev.filter(lt => lt.tag_id !== tagId))
      setError(err)
    }
  }

  const removeTagFromLead = async (tagId: string) => {
    if (!organizationId || !leadId) return
    const removed = leadTags.find(lt => lt.tag_id === tagId)
    setLeadTags(prev => prev.filter(lt => lt.tag_id !== tagId))
    try {
      const res = await fetch(`/api/leads/${leadId}/tags`, {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ tag_id: tagId }),
      })
      if (!res.ok && removed) {
        setLeadTags(prev => [...prev, removed])
      }
    } catch (err: any) {
      console.error('Error removing tag:', err)
      if (removed) setLeadTags(prev => [...prev, removed])
      setError(err)
    }
  }

  return { allTags, leadTags, addTagToLead, removeTagFromLead, loading, error }
}
