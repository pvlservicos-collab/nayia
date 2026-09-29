'use client'

/**
 * O dono de cada conversa da captação (ver /api/captacao/donos), para a lista
 * mostrar "Evandro Prop Kopenhagen" (Pedro, 29/09/2026). Uma cópia só para a
 * tela inteira, buscada a cada 2 min e ao voltar para a aba.
 */
import { useEffect, useState } from 'react'
import type { DonoNaLista } from '@/lib/tiposNay'

export type { DonoNaLista }

let donos: Record<string, DonoNaLista> = {}
let ultimaBusca = 0
let buscando: Promise<void> | null = null
const ouvintes = new Set<(d: Record<string, DonoNaLista>) => void>()

function recarregar(): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch('/api/captacao/donos')
      const j = await r.json().catch(() => ({}))
      if (r.ok && j?.donos) donos = j.donos
    } catch { /* fica com a última cópia */ } finally {
      ultimaBusca = Date.now()
      buscando = null
      for (const o of ouvintes) o(donos)
    }
  })()
  return buscando
}

export function useCaptacaoDonos(ativo: boolean): Record<string, DonoNaLista> {
  const [d, setD] = useState(donos)
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setD)
    setD(donos)
    if (Date.now() - ultimaBusca > 60_000) void recarregar()
    const relogio = setInterval(() => { if (document.visibilityState === 'visible') void recarregar() }, 120_000)
    const aoVoltar = () => { if (document.visibilityState === 'visible' && Date.now() - ultimaBusca > 30_000) void recarregar() }
    document.addEventListener('visibilitychange', aoVoltar)
    return () => { ouvintes.delete(setD); clearInterval(relogio); document.removeEventListener('visibilitychange', aoVoltar) }
  }, [ativo])
  return ativo ? d : {}
}
