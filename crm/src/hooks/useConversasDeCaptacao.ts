'use client'

/**
 * As CONVERSAS DE CAPTAÇÃO (ver /api/captacao/conversas; Pedro, 03/11/2026): as dos Cadastros incompletos e as marcadas
 * (custom_attributes.conversa_captacao). Uma cópia só para a tela inteira, buscada a cada 3 min e ao voltar para a aba.
 * A marca do próprio lead vale na hora (ehDeCaptacao), sem esperar a próxima busca.
 */
import { useEffect, useState } from 'react'
import type { LeadWithOwner } from '@/lib/types'

let ids = new Set<string>()
let ultimaBusca = 0
let buscando: Promise<void> | null = null
const ouvintes = new Set<(s: Set<string>) => void>()
const VAZIO = new Set<string>()

function recarregar(): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch('/api/captacao/conversas')
      const j = await r.json().catch(() => ({}))
      if (r.ok && Array.isArray(j?.ids)) ids = new Set(j.ids)
    } catch { /* fica com a última cópia */ } finally {
      ultimaBusca = Date.now()
      buscando = null
      for (const o of ouvintes) o(ids)
    }
  })()
  return buscando
}

export function ehDeCaptacao(l: LeadWithOwner, s: Set<string>): boolean {
  return s.has(l.id) || (l.custom_attributes as any)?.conversa_captacao === true
}

export function useConversasDeCaptacao(ativo = true): Set<string> {
  const [s, setS] = useState(ids)
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setS)
    setS(ids)
    if (Date.now() - ultimaBusca > 60_000) void recarregar()
    const relogio = setInterval(() => { if (document.visibilityState === 'visible') void recarregar() }, 180_000)
    const aoVoltar = () => { if (document.visibilityState === 'visible' && Date.now() - ultimaBusca > 30_000) void recarregar() }
    document.addEventListener('visibilitychange', aoVoltar)
    return () => { ouvintes.delete(setS); clearInterval(relogio); document.removeEventListener('visibilitychange', aoVoltar) }
  }, [ativo])
  return ativo ? s : VAZIO
}
