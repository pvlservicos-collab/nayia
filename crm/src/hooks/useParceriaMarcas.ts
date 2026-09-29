'use client'

/**
 * As marcas da Nay para as conversas da Parceria (proprietário, corretor,
 * visita aberta, o Tel com a conversa) -- ver /api/parceria/marcas.
 *
 * Uma cópia só para a tela inteira: a lista (filtros e marcas de cada linha)
 * e o card do lado leem daqui, e a busca acontece uma vez por minuto (e ao
 * voltar para a aba), não uma por componente.
 */
import { useEffect, useState } from 'react'
import type { EstadoDaNay, MarcaDaNay } from '@/lib/tiposNay'

type Estado = { marcas: Record<string, MarcaDaNay>; nay: EstadoDaNay | null; carregado: boolean; erro: string | null }

let estado: Estado = { marcas: {}, nay: null, carregado: false, erro: null }
const ouvintes = new Set<(e: Estado) => void>()
let buscando: Promise<void> | null = null
let relogio: ReturnType<typeof setInterval> | null = null
let ultimaBusca = 0
const CADA_MS = 60_000

function avisar() {
  for (const o of ouvintes) o(estado)
}

export function recarregarMarcasDaParceria(fresco = false): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch(`/api/parceria/marcas${fresco ? '?fresco=1' : ''}`)
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      estado = { marcas: j.marcas || {}, nay: j.nay ?? null, carregado: true, erro: null }
    } catch (e: any) {
      estado = { ...estado, carregado: true, erro: e?.message || 'Não consegui ler a Nay' }
    } finally {
      ultimaBusca = Date.now()
      buscando = null
      avisar()
    }
  })()
  return buscando
}

function aoVoltar() {
  if (document.visibilityState === 'visible' && Date.now() - ultimaBusca > 20_000) void recarregarMarcasDaParceria()
}

export function useParceriaMarcas(ativo = true) {
  const [e, setE] = useState<Estado>(estado)
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setE)
    setE(estado)
    if (!estado.carregado || Date.now() - ultimaBusca > CADA_MS) void recarregarMarcasDaParceria()
    if (!relogio) {
      relogio = setInterval(() => {
        if (document.visibilityState === 'visible') void recarregarMarcasDaParceria()
      }, CADA_MS)
      document.addEventListener('visibilitychange', aoVoltar)
    }
    return () => {
      ouvintes.delete(setE)
      if (ouvintes.size === 0 && relogio) {
        clearInterval(relogio)
        relogio = null
        document.removeEventListener('visibilitychange', aoVoltar)
      }
    }
  }, [ativo])
  return { marcas: e.marcas, nay: e.nay, carregado: e.carregado, erro: e.erro, recarregar: recarregarMarcasDaParceria }
}
