'use client'

/**
 * Os clientes da OLX e a etapa de cada um (aba Captação, 16/10/2026; ver src/lib/olxClientes.ts). Uma cópia só para a
 * tela inteira, buscada a cada minuto e ao voltar para a aba, como useCaptacaoDonos.
 */
import { useEffect, useState } from 'react'
import type { ClienteOlx, EtapaOlx } from '@/lib/olxClientes'

let clientes: Record<string, ClienteOlx> = {}
let ultimaBusca = 0
let buscando: Promise<void> | null = null
const ouvintes = new Set<(c: Record<string, ClienteOlx>) => void>()

function recarregar(): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch('/api/captacao/olx-clientes')
      const j = await r.json().catch(() => ({}))
      if (r.ok && j?.clientes) clientes = j.clientes
    } catch { /* fica com a última cópia */ } finally {
      ultimaBusca = Date.now()
      buscando = null
      for (const o of ouvintes) o(clientes)
    }
  })()
  return buscando
}

/** A equipe muda a etapa (Proprietários, Fechamento, Finalizados...). Devolve a mensagem de erro, ou null. */
export async function mudarEtapaOlx(telefone: string, etapa: EtapaOlx): Promise<string | null> {
  try {
    const r = await fetch('/api/captacao/olx-clientes', {
      method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ telefone, etapa }),
    })
    const j = await r.json().catch(() => ({}))
    if (!r.ok) return j?.error || `Erro ${r.status}`
    await recarregar()
    return null
  } catch (e: any) {
    return e?.message || 'Não consegui mudar a etapa.'
  }
}

export function useOlxClientes(ativo: boolean): Record<string, ClienteOlx> {
  const [c, setC] = useState(clientes)
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setC)
    setC(clientes)
    if (Date.now() - ultimaBusca > 30_000) void recarregar()
    const relogio = setInterval(() => { if (document.visibilityState === 'visible') void recarregar() }, 60_000)
    const aoVoltar = () => { if (document.visibilityState === 'visible' && Date.now() - ultimaBusca > 20_000) void recarregar() }
    document.addEventListener('visibilitychange', aoVoltar)
    return () => { ouvintes.delete(setC); clearInterval(relogio); document.removeEventListener('visibilitychange', aoVoltar) }
  }, [ativo])
  return ativo ? c : {}
}
