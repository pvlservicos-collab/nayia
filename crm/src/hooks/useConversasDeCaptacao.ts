'use client'

/**
 * As CONVERSAS DE CAPTAÇÃO (ver /api/captacao/conversas; Pedro, 03/11/2026): as dos Cadastros incompletos e as marcadas
 * (custom_attributes.conversa_captacao), com o contexto de cada uma. Uma cópia só para a tela inteira, buscada a cada 3 min
 * e ao voltar para a aba. A marca do próprio lead vale na hora (ehDeCaptacao), sem esperar a próxima busca: true entra,
 * false ("Mandar de volta para os proprietários") sai.
 */
import { useEffect, useState } from 'react'
import type { LeadWithOwner } from '@/lib/types'

export type ContextoDaCaptacao =
  | { fonte: 'cadastro'; tipo: string; codigo: number | null; dados: Record<string, any>; fotos: number; criado_em: string
      atualizado_em: string; faltou: string[]; nota: number | null; humano: boolean; opt_out: boolean }
  | { fonte: 'olx'; olx_id?: string; titulo?: string; url?: string; preco_texto?: string; bairro?: string; anunciante?: string
      chamado_em?: string }

type Copia = { ids: Set<string>; contexto: Record<string, ContextoDaCaptacao> }
let copia: Copia = { ids: new Set(), contexto: {} }
let ultimaBusca = 0
let buscando: Promise<void> | null = null
const ouvintes = new Set<(c: Copia) => void>()
const VAZIA: Copia = { ids: new Set(), contexto: {} }

function recarregar(): Promise<void> {
  if (buscando) return buscando
  buscando = (async () => {
    try {
      const r = await fetch('/api/captacao/conversas')
      const j = await r.json().catch(() => ({}))
      if (r.ok && Array.isArray(j?.ids)) copia = { ids: new Set(j.ids), contexto: j.contexto || {} }
    } catch { /* fica com a última cópia */ } finally {
      ultimaBusca = Date.now()
      buscando = null
      for (const o of ouvintes) o(copia)
    }
  })()
  return buscando
}

export function ehDeCaptacao(l: LeadWithOwner, s: Set<string>): boolean {
  const marca = (l.custom_attributes as any)?.conversa_captacao
  if (marca === false) return false
  return marca === true || s.has(l.id)
}

function useCopia(ativo: boolean): Copia {
  const [c, setC] = useState(copia)
  useEffect(() => {
    if (!ativo) return
    ouvintes.add(setC)
    setC(copia)
    if (Date.now() - ultimaBusca > 60_000) void recarregar()
    const relogio = setInterval(() => { if (document.visibilityState === 'visible') void recarregar() }, 180_000)
    const aoVoltar = () => { if (document.visibilityState === 'visible' && Date.now() - ultimaBusca > 30_000) void recarregar() }
    document.addEventListener('visibilitychange', aoVoltar)
    return () => { ouvintes.delete(setC); clearInterval(relogio); document.removeEventListener('visibilitychange', aoVoltar) }
  }, [ativo])
  return ativo ? c : VAZIA
}

export function useConversasDeCaptacao(ativo = true): Set<string> {
  return useCopia(ativo).ids
}

export function useContextoDaCaptacao(ativo = true): Record<string, ContextoDaCaptacao> {
  return useCopia(ativo).contexto
}

/** depois de marcar uma conversa (abrir pela OLX, mandar de volta): relê a cópia */
export function recarregarCaptacao(): Promise<void> {
  return (buscando || Promise.resolve()).then(() => recarregar())
}
