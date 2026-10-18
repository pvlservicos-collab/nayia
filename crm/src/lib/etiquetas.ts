'use client'

/**
 * AS ETIQUETAS DA EQUIPE (Pedro, 17/10/2026: "um conjunto de tags que eu crio com cor diferente ... nos 2 números um
 * iconezinho ... no card do lead eu posso pôr uma tag ... se eu clico nesse ícone eu posso filtrar pelas tags ou criar
 * novas no mesmo menu ... pode ser uma pranchetinha").
 *
 * Uma lista só para a prancheta da lista de conversas e para o card do lead (Parceria e Captação): quem cria ou muda uma
 * etiqueta avisa os outros na hora. As "Nay: ..." são da Nay (etapa) e não aparecem aqui.
 */
import { useEffect, useState } from 'react'

export interface Etiqueta { id: string; name: string; color: string }

/** As cores para escolher ao criar (fortes o bastante para o texto colorido no tema claro e no escuro). */
export const CORES_DE_ETIQUETA = ['#e11d48', '#ea580c', '#ca8a04', '#16a34a', '#0d9488', '#2563eb', '#7c3aed', '#c026d3', '#64748b']

let lista: Etiqueta[] | null = null
let pedido: Promise<Etiqueta[]> | null = null
const ouvintes = new Set<(l: Etiqueta[]) => void>()

const ordenar = (l: Etiqueta[]) => [...l].sort((a, b) => a.name.localeCompare(b.name, 'pt-BR'))
const daEquipe = (t: { name?: string }) => !String(t?.name || '').startsWith('Nay:')

function avisar() { const l = lista || []; ouvintes.forEach((f) => f(l)) }

export function carregarEtiquetas(forcar = false): Promise<Etiqueta[]> {
  if (lista && !forcar) return Promise.resolve(lista)
  if (!pedido || forcar) {
    pedido = fetch('/api/tags').then((r) => r.json()).then((j) => {
      lista = ordenar(((j?.data || []) as any[]).filter(daEquipe).map((t) => ({ id: t.id, name: t.name, color: t.color || '#64748b' })))
      avisar()
      return lista
    }).catch(() => { pedido = null; return lista || [] })
  }
  return pedido
}

/** A lista das etiquetas da equipe, que se atualiza quando alguém cria, muda ou apaga. */
export function useEtiquetas(): Etiqueta[] {
  const [l, setL] = useState<Etiqueta[]>(lista || [])
  useEffect(() => {
    ouvintes.add(setL)
    void carregarEtiquetas()
    return () => { ouvintes.delete(setL) }
  }, [])
  return l
}

export async function criarEtiqueta(nome: string, cor: string): Promise<Etiqueta> {
  const limpo = nome.trim().slice(0, 40)
  const igual = (lista || []).find((t) => t.name.toLowerCase() === limpo.toLowerCase())
  if (igual) return igual
  const r = await fetch('/api/tags', { method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name: limpo, color: cor, source: 'crm' }) })
  const j = await r.json().catch(() => ({}))
  if (!r.ok || !j?.data?.id) throw new Error(j?.error || 'não consegui criar a etiqueta')
  const t = { id: j.data.id, name: j.data.name, color: j.data.color || cor }
  lista = ordenar([...(lista || []), t])
  avisar()
  return t
}

export async function mudarCorDaEtiqueta(id: string, cor: string): Promise<void> {
  const r = await fetch(`/api/tags?id=${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ color: cor }) })
  if (!r.ok) throw new Error('não consegui mudar a cor')
  lista = (lista || []).map((t) => (t.id === id ? { ...t, color: cor } : t))
  avisar()
}

export async function apagarEtiqueta(id: string): Promise<void> {
  const r = await fetch(`/api/tags?id=${id}`, { method: 'DELETE' })
  if (!r.ok) throw new Error('não consegui apagar a etiqueta')
  lista = (lista || []).filter((t) => t.id !== id)
  avisar()
}

/** Pôr ou tirar a etiqueta de um lead (a gravação; a tela atualiza antes, pelo onTagsChange). */
export async function marcarEtiqueta(leadId: string, tagId: string, por: boolean): Promise<void> {
  const r = await fetch(`/api/leads/${leadId}/tags`, {
    method: por ? 'POST' : 'DELETE', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tag_id: tagId }),
  })
  if (!r.ok) throw new Error('não salvou')
}
