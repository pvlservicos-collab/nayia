'use client'

import { useCallback, useEffect, useState } from 'react'
import { TIPOS_PADRAO, type TipoDeContato } from '@/lib/organizacaoDoLead'

/* uma leitura para a tela inteira (a lista e o cabeçalho usam a mesma); salvar avisa quem está ouvindo */
let guardado: TipoDeContato[] | null = null
const ouvintes = new Set<(t: TipoDeContato[]) => void>()

/** Os tipos de contato personalizados (Pedro, 03/11/2026), de /api/linhas/tipos-de-contato. */
export function useTiposDeContato() {
  const [tipos, setTipos] = useState<TipoDeContato[]>(guardado || TIPOS_PADRAO)
  useEffect(() => {
    ouvintes.add(setTipos)
    if (!guardado) {
      fetch('/api/linhas/tipos-de-contato').then((r) => (r.ok ? r.json() : null)).then((j) => {
        if (Array.isArray(j?.tipos)) { guardado = j.tipos; ouvintes.forEach((f) => f(j.tipos)) }
      }).catch(() => {})
    }
    return () => { ouvintes.delete(setTipos) }
  }, [])
  const salvar = useCallback(async (novos: TipoDeContato[]) => {
    const r = await fetch('/api/linhas/tipos-de-contato', {
      method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tipos: novos }),
    })
    const j = await r.json().catch(() => ({}))
    if (!r.ok) throw new Error(j.error || j.message || 'Não consegui salvar.')
    guardado = j.tipos
    ouvintes.forEach((f) => f(j.tipos))
    return j.tipos as TipoDeContato[]
  }, [])
  return { tipos, salvar }
}
