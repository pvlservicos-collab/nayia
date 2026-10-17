'use client'

/**
 * Quem é dono de imóvel no cadastro, entre os contatos da Captação (16/10/2026: "no CRM número captação pôr a aba
 * proprietário também"; migração 397). Os 8 últimos dígitos, numa cópia só para a tela, buscada a cada 2 min.
 */
import { useEffect, useState } from 'react'

let fins = new Set<string>()
let ultimaBusca = 0
let buscando: Promise<void> | null = null
const ouvintes = new Set<(f: Set<string>) => void>()

function recarregar(): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch('/api/captacao/donos-do-cadastro')
      const j = await r.json().catch(() => ({}))
      if (r.ok && Array.isArray(j?.fins)) fins = new Set(j.fins)
    } catch { /* fica com a última cópia */ } finally {
      ultimaBusca = Date.now()
      buscando = null
      for (const o of ouvintes) o(fins)
    }
  })()
  return buscando
}

const VAZIO = new Set<string>()

export function useDonosDoCadastro(ativo: boolean): Set<string> {
  const [f, setF] = useState(fins)
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setF)
    setF(fins)
    if (Date.now() - ultimaBusca > 60_000) void recarregar()
    const relogio = setInterval(() => { if (document.visibilityState === 'visible') void recarregar() }, 120_000)
    return () => { ouvintes.delete(setF); clearInterval(relogio) }
  }, [ativo])
  return ativo ? f : VAZIO
}
