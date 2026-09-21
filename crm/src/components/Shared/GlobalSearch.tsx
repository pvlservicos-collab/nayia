'use client'

import { useState, useRef, useEffect, useCallback } from 'react'
import { MagnifyingGlass, Phone, ChatText, User, SpinnerGap, X } from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'
import { useAuth, useIsMobile } from '@/hooks'
import { useRouter } from 'next/navigation'

interface SearchResult {
  id: string
  type: 'lead' | 'message'
  title: string
  subtitle: string
  leadId: string
}

export default function GlobalSearch() {
  const { organizationId } = useAuth()
  const router = useRouter()
  const isMobile = useIsMobile()
  const [query, setQuery] = useState('')
  const [results, setResults] = useState<SearchResult[]>([])
  const [loading, setLoading] = useState(false)
  const [open, setOpen] = useState(false)
  const [mobileOpen, setMobileOpen] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)
  const mobileInputRef = useRef<HTMLInputElement>(null)
  const debounceRef = useRef<NodeJS.Timeout | null>(null)

  useEffect(() => {
    const handleClick = (e: MouseEvent) => {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', handleClick)
    return () => document.removeEventListener('mousedown', handleClick)
  }, [])

  useEffect(() => {
    if (mobileOpen) {
      requestAnimationFrame(() => mobileInputRef.current?.focus())
    } else {
      setQuery('')
      setResults([])
    }
  }, [mobileOpen])

  const search = useCallback(async (term: string) => {
    if (!organizationId || term.trim().length < 2) { setResults([]); setOpen(false); return }
    setLoading(true)
    try {
      const res = await fetch(`/api/leads?q=${encodeURIComponent(term.trim())}&limit=10`)
      if (!res.ok) return
      const { data } = await res.json()
      const items: SearchResult[] = (data || []).map((lead: any) => ({
        id: `lead-${lead.id}`,
        type: 'lead' as const,
        title: lead.title || lead.phone || 'Sem nome',
        subtitle: lead.phone || lead.email || '',
        leadId: lead.id,
      }))
      setResults(items)
      setOpen(items.length > 0)
    } catch (err) {
      console.error('Search error:', err)
    } finally {
      setLoading(false)
    }
  }, [organizationId])

  const handleChange = (value: string) => {
    setQuery(value)
    if (debounceRef.current) clearTimeout(debounceRef.current)
    if (value.trim().length < 2) { setResults([]); setOpen(false); return }
    debounceRef.current = setTimeout(() => search(value), 300)
  }

  const handleSelect = (result: SearchResult) => {
    setQuery('')
    setResults([])
    setOpen(false)
    setMobileOpen(false)
    router.push(linkDaConversa(result.leadId))
  }

  const leadResults = results.filter(r => r.type === 'lead')
  const messageResults = results.filter(r => r.type === 'message')

  const resultsList = (
    <>
      {leadResults.length > 0 && (
        <div>
          <p className="px-4 pt-3 pb-1.5 text-[10px] font-bold uppercase tracking-wider text-gray-400">Leads</p>
          {leadResults.map((r) => (
            <button key={r.id} onClick={() => handleSelect(r)} className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 transition-colors text-left">
              <div className="w-8 h-8 rounded-full bg-blue-50 flex items-center justify-center flex-shrink-0">
                {r.subtitle && r.subtitle.match(/\d/) ? <Phone size={14} className="text-blue-600" weight="bold" /> : <User size={14} className="text-blue-600" weight="bold" />}
              </div>
              <div className="min-w-0">
                <p className="text-sm font-medium text-gray-900 truncate">{r.title}</p>
                {r.subtitle && <p className="text-xs text-gray-400 truncate">{r.subtitle}</p>}
              </div>
            </button>
          ))}
        </div>
      )}
      {messageResults.length > 0 && (
        <div>
          {leadResults.length > 0 && <div className="h-px bg-gray-100 mx-3" />}
          <p className="px-4 pt-3 pb-1.5 text-[10px] font-bold uppercase tracking-wider text-gray-400">Mensagens</p>
          {messageResults.map((r) => (
            <button key={r.id} onClick={() => handleSelect(r)} className="w-full flex items-center gap-3 px-4 py-2.5 hover:bg-gray-50 transition-colors text-left">
              <div className="w-8 h-8 rounded-full bg-green-50 flex items-center justify-center flex-shrink-0">
                <ChatText size={14} className="text-green-600" weight="bold" />
              </div>
              <div className="min-w-0">
                <p className="text-sm font-medium text-gray-900 truncate">{r.title}</p>
                <p className="text-xs text-gray-400 truncate">{r.subtitle}</p>
              </div>
            </button>
          ))}
        </div>
      )}
      {results.length === 0 && !loading && query.trim().length >= 2 && (
        <div className="px-4 py-6 text-center text-sm text-gray-400">Nenhum resultado encontrado</div>
      )}
    </>
  )

  if (isMobile) {
    return (
      <>
        <button
          onClick={() => setMobileOpen(true)}
          aria-label="Buscar"
          className="app-tap-target w-11 h-11 flex items-center justify-center rounded-lg text-gray-500 dark:text-[#8b949e] hover:bg-gray-100 dark:hover:bg-[#21262d] transition-colors"
        >
          <MagnifyingGlass size={18} />
        </button>
        {mobileOpen && (
          <div className="app-safe-top fixed inset-0 z-[70] bg-white dark:bg-[#0d1117] flex flex-col">
            <div className="flex items-center gap-2 p-3 border-b border-gray-100 dark:border-[#30363d]">
              <button
                onClick={() => setMobileOpen(false)}
                aria-label="Fechar busca"
                className="app-tap-target w-9 h-9 flex-shrink-0 flex items-center justify-center rounded-lg text-gray-500 hover:bg-gray-100 dark:hover:bg-[#21262d] transition-colors"
              >
                <X size={20} />
              </button>
              <div className="relative flex-1">
                <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
                <SpinnerGap className={`absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 animate-spin transition-opacity ${loading ? 'opacity-100' : 'opacity-0'}`} weight="bold" />
                <input
                  ref={mobileInputRef}
                  type="text"
                  value={query}
                  onChange={(e) => handleChange(e.target.value)}
                  placeholder="Buscar leads..."
                  className="w-full pl-9 pr-8 py-2.5 bg-gray-100 dark:bg-[#21262d] border-none rounded-lg text-sm text-gray-700 dark:text-[#e6edf3] placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
            </div>
            <div className="flex-1 overflow-y-auto">{resultsList}</div>
          </div>
        )}
      </>
    )
  }

  return (
    <div className="relative" ref={containerRef}>
      <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" />
      <SpinnerGap className={`absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 animate-spin transition-opacity ${loading ? 'opacity-100' : 'opacity-0'}`} weight="bold" />
      <input
        type="text"
        value={query}
        onChange={(e) => handleChange(e.target.value)}
        onFocus={() => results.length > 0 && setOpen(true)}
        placeholder="Buscar leads..."
        className="w-56 pl-9 pr-8 py-1.5 bg-gray-100 border-none rounded-lg text-sm text-gray-700 placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:bg-white transition-all"
      />
      {open && (
        <div className="absolute right-0 top-full mt-2 w-80 bg-white border border-gray-100 rounded-xl shadow-xl shadow-gray-200/60 z-50 max-h-[400px] overflow-y-auto animate-in fade-in slide-in-from-top-2">
          {resultsList}
        </div>
      )}
    </div>
  )
}
