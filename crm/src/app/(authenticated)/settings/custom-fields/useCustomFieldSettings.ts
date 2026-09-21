import { useState, useCallback } from 'react'
import { useAuth } from '@/hooks/useAuth'
import { CustomFieldDefinition } from '@/lib/types'

export interface CustomFieldCategory {
  id: string
  organization_id: string
  name: string
  rank: number
  created_at: string
  updated_at: string
}

export function useCustomFieldSettings() {
  const { organizationId } = useAuth()
  const [categories, setCategories] = useState<CustomFieldCategory[]>([])
  const [fields, setFields] = useState<CustomFieldDefinition[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<Error | null>(null)

  const fetchData = useCallback(async () => {
    if (!organizationId) return
    setLoading(true)
    setError(null)
    try {
      const res = await fetch('/api/custom-fields')
      if (!res.ok) throw new Error('Failed to fetch custom fields')
      const { categories: cats, definitions: defs } = await res.json()
      setCategories(cats || [])
      setFields(defs || [])
    } catch (err: any) {
      console.error('Error fetching custom fields settings:', err)
      setError(err)
    } finally {
      setLoading(false)
    }
  }, [organizationId])

  const createCategory = async (name: string) => {
    if (!organizationId) return
    const res = await fetch('/api/custom-fields', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ type: 'category', name, rank: categories.length }),
    })
    if (!res.ok) throw new Error('Failed to create category')
    const { data } = await res.json()
    setCategories(prev => [...prev, data])
    return data
  }

  const updateCategory = async (id: string, updates: Partial<CustomFieldCategory>) => {
    const res = await fetch(`/api/custom-fields/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...updates, type: 'category' }),
    })
    if (!res.ok) throw new Error('Failed to update category')
    setCategories(prev => prev.map(c => c.id === id ? { ...c, ...updates } : c))
  }

  const deleteCategory = async (id: string) => {
    const res = await fetch(`/api/custom-fields/${id}?type=category`, { method: 'DELETE' })
    if (!res.ok) throw new Error('Failed to delete category')
    setCategories(prev => prev.filter(c => c.id !== id))
    setFields(prev => prev.map(f => (f as any).category_id === id ? { ...f, category_id: undefined } as any : f))
  }

  const createField = async (payload: { name: string; field_type: string; category_id?: string | null; required?: boolean; description?: string; options?: any[] }) => {
    if (!organizationId) return
    const res = await fetch('/api/custom-fields', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...payload, rank: fields.length * 1000 }),
    })
    if (!res.ok) throw new Error('Failed to create field')
    const { data } = await res.json()
    setFields(prev => [...prev, data])
    return data
  }

  const updateField = async (id: string, payload: any) => {
    const res = await fetch(`/api/custom-fields/${id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    })
    if (!res.ok) throw new Error('Failed to update field')
    const { data } = await res.json()
    setFields(prev => prev.map(f => f.id === id ? data : f))
    return data
  }

  const updateFieldRanks = async (updates: { id: string; rank: number }[]) => {
    setFields(prev => {
      const map = new Map(updates.map(u => [u.id, u.rank]))
      return prev.map(f => map.has(f.id) ? { ...f, rank: map.get(f.id)! } : f).sort((a, b) => (a.rank as any) - (b.rank as any))
    })
    await Promise.all(updates.map(u =>
      fetch(`/api/custom-fields/${u.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ rank: u.rank }),
      })
    ))
  }

  const deleteField = async (id: string) => {
    const res = await fetch(`/api/custom-fields/${id}`, { method: 'DELETE' })
    if (!res.ok) throw new Error('Failed to delete field')
    setFields(prev => prev.filter(f => f.id !== id))
  }

  return { categories, fields, loading, error, fetchData, createCategory, updateCategory, deleteCategory, createField, updateField, updateFieldRanks, deleteField }
}
