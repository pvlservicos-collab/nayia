'use client'

import { useEffect, useRef, useState } from 'react'
import { useLeadsContext } from '@/contexts/LeadsContext'
import type { LeadWithOwner, SearchHit } from '@/lib/types'

const MIN_SERVER_CHARS = 3
const DEBOUNCE_MS = 250

// Mirror SQL norm_text: strip accents + lowercase.
const norm = (s: string | null | undefined) =>
  (s ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase()

const digits = (s: string | null | undefined) => (s ?? '').replace(/\D/g, '')

interface UseLeadSearchResult {
  results: SearchHit[]
  loading: boolean
  error: Error | null
  mode: 'client' | 'server'
}

export function useLeadSearch(query: string): UseLeadSearchResult {
  const { leads } = useLeadsContext()
  const [serverHits, setServerHits] = useState<SearchHit[] | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<Error | null>(null)

  const requestIdRef = useRef(0)
  const abortRef = useRef<AbortController | null>(null)

  const trimmed = query.trim()

  useEffect(() => {
    if (trimmed.length < MIN_SERVER_CHARS) {
      setServerHits(null)
      setError(null)
      setLoading(false)
      abortRef.current?.abort()
      return
    }

    const myRequestId = ++requestIdRef.current
    abortRef.current?.abort()
    const ctl = new AbortController()
    abortRef.current = ctl

    setLoading(true)
    const timer = setTimeout(async () => {
      try {
        const res = await fetch('/api/leads/search', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ q: trimmed }),
          signal: ctl.signal,
        })
        if (!res.ok) throw new Error(`search failed (${res.status})`)
        const { hits } = (await res.json()) as { hits: SearchHit[] }
        if (requestIdRef.current !== myRequestId) return
        setServerHits(hits)
        setError(null)
      } catch (err) {
        if ((err as { name?: string }).name === 'AbortError') return
        if (requestIdRef.current !== myRequestId) return
        setError(err as Error)
        setServerHits(null)
      } finally {
        if (requestIdRef.current === myRequestId) setLoading(false)
      }
    }, DEBOUNCE_MS)

    return () => {
      clearTimeout(timer)
      ctl.abort()
    }
  }, [trimmed])

  // Empty query → return full list with a synthetic matchType='title' so the
  // downstream component can render unchanged.
  if (trimmed.length === 0) {
    const results: SearchHit[] = leads.map((lead: LeadWithOwner) => ({ lead, matchType: 'title' as const }))
    return { results, loading: false, error: null, mode: 'client' }
  }

  // Client-side path: 1–2 chars OR no server response yet OR server errored.
  if (trimmed.length < MIN_SERVER_CHARS || serverHits === null) {
    const nq = norm(trimmed)
    const dq = digits(trimmed)
    const results: SearchHit[] = []
    for (const lead of leads) {
      if (norm(lead.title).includes(nq)) { results.push({ lead, matchType: 'title' }); continue }
      if (norm(lead.email).includes(nq)) { results.push({ lead, matchType: 'email' }); continue }
      if (dq.length >= 3 && digits(lead.phone).includes(dq)) { results.push({ lead, matchType: 'phone' }); continue }
    }
    return { results, loading, error, mode: 'client' }
  }

  return { results: serverHits, loading, error, mode: 'server' }
}
