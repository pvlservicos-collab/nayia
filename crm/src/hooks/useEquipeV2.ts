'use client'

/**
 * Quem é quem na equipe, para a v2 do CRM (lib/versaoDoCrm.ts): o id do membro (o que vem em autores_manuais) -> o nome e a
 * cor de quem atende. Uma cópia só para a tela inteira (/api/users), lida uma vez por carga da página.
 */
import { useEffect, useState } from 'react'
import { pessoaV2, type QuemAtende } from '@/lib/versaoDoCrm'

let equipe: Record<string, QuemAtende> | null = null
let buscando: Promise<void> | null = null
const ouvintes = new Set<(e: Record<string, QuemAtende>) => void>()

function ler(): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch('/api/users')
      const j = await r.json().catch(() => ({}))
      const m: Record<string, QuemAtende> = {}
      for (const x of (j?.data || []) as any[]) {
        const p = pessoaV2(x?.profiles?.full_name)
        if (p && x?.id) m[x.id] = p
      }
      equipe = m
    } catch { equipe = equipe || {} } finally {
      buscando = null
      for (const o of ouvintes) o(equipe || {})
    }
  })()
  return buscando
}

export function useEquipeV2(ativo = true): Record<string, QuemAtende> {
  const [e, setE] = useState<Record<string, QuemAtende>>(equipe || {})
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setE)
    if (equipe) setE(equipe); else void ler()
    return () => { ouvintes.delete(setE) }
  }, [ativo])
  return e
}
