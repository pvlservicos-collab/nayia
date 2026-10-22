'use client'

/** As visitas da Nay para a aba "Visitas agendadas" da Parceria (ver /api/parceria/visitas). */
import { useCallback, useEffect, useRef, useState } from 'react'
import type { EventoDaVisita, VisitaNaTela } from '@/lib/tiposNay'

const CADA_MS = 60_000

export function useVisitasParceria(ativo = true) {
  const [visitas, setVisitas] = useState<VisitaNaTela[]>([])
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const vivo = useRef(true)

  const recarregar = useCallback(async () => {
    try {
      const r = await fetch('/api/parceria/visitas')
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      if (vivo.current) { setVisitas(j.visitas || []); setErro(null) }
    } catch (e: any) {
      if (vivo.current) setErro(e?.message || 'Não consegui ler as visitas')
    } finally {
      if (vivo.current) setCarregando(false)
    }
  }, [])

  useEffect(() => {
    vivo.current = true
    if (!ativo) return
    void recarregar()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void recarregar() }, CADA_MS)
    return () => { vivo.current = false; clearInterval(t) }
  }, [ativo, recarregar])

  return { visitas, carregando, erro, recarregar }
}

export async function eventosDaVisita(id: number): Promise<EventoDaVisita[]> {
  const r = await fetch(`/api/parceria/visitas/${id}`)
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
  return j.eventos || []
}

/** Mexer na visita pela agenda (29/09): mudar a hora, marcar realizada, excluir. */
export async function mexerNaVisita(
  id: number, acao: 'horario' | 'realizada' | 'excluir' | 'editar' | 'proprietario_ok', quando?: string,
  edicao?: { campo: string; valor: string | null },
): Promise<{ ok: boolean; mensagem: string }> {
  try {
    const r = await fetch(`/api/parceria/visitas/${id}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ acao, ...(quando ? { quando } : {}), ...(edicao ? edicao : {}) }),
    })
    const j = await r.json().catch(() => ({}))
    return { ok: r.ok && !!j.ok, mensagem: j.mensagem || j.error || `Erro ${r.status}` }
  } catch (e: any) {
    return { ok: false, mensagem: e?.message || 'Sem conexão com o CRM.' }
  }
}
