'use client'

/** As visitas da Nay para a aba "Visitas agendadas" da Parceria (ver /api/parceria/visitas). */
import { useCallback, useEffect, useRef, useState } from 'react'
import type { EventoDaVisita, VisitaNaTela } from '@/lib/tiposNay'

const CADA_MS = 60_000

/** `diasAtras`: só as abertas e as fechadas desses últimos dias (a rota sem janela traz a história inteira) */
export function useVisitasParceria(ativo = true, diasAtras?: number) {
  const [visitas, setVisitas] = useState<VisitaNaTela[]>([])
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const vivo = useRef(true)

  const recarregar = useCallback(async () => {
    try {
      const desde = diasAtras != null
        ? new Date(Date.now() - diasAtras * 86_400_000).toLocaleDateString('en-CA', { timeZone: 'America/Manaus' }) : null
      const r = await fetch(desde ? `/api/parceria/visitas?desde=${desde}` : '/api/parceria/visitas')
      const j = await r.json().catch(() => ({}))
      if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`)
      if (vivo.current) { setVisitas(j.visitas || []); setErro(null) }
    } catch (e: any) {
      if (vivo.current) setErro(e?.message || 'Não consegui ler as visitas')
    } finally {
      if (vivo.current) setCarregando(false)
    }
  }, [diasAtras])

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
  if (id < 0) return []           // 513: a visita da Nay Leads não tem o andamento passo a passo da Parceria
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
    // 513: a visita da Nay Leads (id negativo) só aceita o VISITA REALIZADA, com a quem perguntar (edicao.valor)
    if (id < 0) {
      if (acao !== 'realizada') return { ok: false, mensagem: 'A visita do número Leads muda pela conversa: aqui só VISITA REALIZADA.' }
      const r = await fetch(`/api/leads/visitas/${-id}`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ acao, para: edicao?.valor }),
      })
      const j = await r.json().catch(() => ({}))
      return { ok: r.ok && !!j.ok, mensagem: j.mensagem || j.error || `Erro ${r.status}` }
    }
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
