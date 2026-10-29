'use client'

/**
 * ENCAMINHAR MENSAGEM (Pedro, 29/10/2026: "fazer encaminhar mensagem no CRM"). Como no WhatsApp: o botão ao lado de
 * "Responder" abre esta janela, a pessoa escolhe um ou mais contatos e o texto (ou a mídia com a legenda) sai por cada
 * conversa, pela linha dela (a mesma rota de mensagens do CRM). Os destinos vêm da busca de leads, em todos os números.
 */
import { useEffect, useRef, useState } from 'react'
import { X, MagnifyingGlass, Check, CircleNotch, ArrowBendUpRight } from '@phosphor-icons/react'
import type { LeadActivityWithActor, SearchHit } from '@/lib/types'

type Resultado = { ok: boolean; erro?: string }

export default function EncaminharMensagem({ activity, onClose }: { activity: LeadActivityWithActor; onClose: () => void }) {
  const [q, setQ] = useState('')
  const [achados, setAchados] = useState<SearchHit[]>([])
  const [buscando, setBuscando] = useState(false)
  const [escolhidos, setEscolhidos] = useState<Record<string, { id: string; nome: string }>>({})
  const [enviando, setEnviando] = useState(false)
  const [resultados, setResultados] = useState<Record<string, Resultado>>({})
  const ctl = useRef<AbortController | null>(null)

  const m: any = activity.metadata || {}
  const texto = (activity.content || '').trim()
  const temMidia = !!m.media_url
  const previa = texto || (temMidia ? `[${m.media_type || 'mídia'}]` : '')

  useEffect(() => {
    const termo = q.trim()
    if (termo.length < 2) { setAchados([]); return }
    const t = setTimeout(async () => {
      ctl.current?.abort()
      const c = new AbortController()
      ctl.current = c
      setBuscando(true)
      try {
        const r = await fetch('/api/leads/search', {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, signal: c.signal,
          body: JSON.stringify({ q: termo, limit: 20 }),
        })
        const j = await r.json().catch(() => ({}))
        setAchados(Array.isArray(j?.results) ? j.results : Array.isArray(j?.hits) ? j.hits : Array.isArray(j) ? j : [])
      } catch { /* busca cancelada ou falhou: a lista fica como está */ } finally { setBuscando(false) }
    }, 250)
    return () => clearTimeout(t)
  }, [q])

  const alternar = (id: string, nome: string) =>
    setEscolhidos((e) => { const n = { ...e }; if (n[id]) delete n[id]; else n[id] = { id, nome }; return n })

  const enviar = async () => {
    const ids = Object.keys(escolhidos)
    if (!ids.length || enviando) return
    setEnviando(true)
    const novos: Record<string, Resultado> = {}
    for (const id of ids) {
      if (resultados[id]?.ok) { novos[id] = resultados[id]; continue }   // quem já recebeu não recebe de novo
      try {
        const body: any = { content: previa, type: 'whatsapp', source: 'human', direction: 'outbound' }
        if (temMidia) {
          body.media_url = m.media_url
          body.media_type = m.media_type
          body.media_filename = m.media_filename
          body.caption = texto
        }
        const r = await fetch(`/api/leads/${id}/messages`, {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
        })
        if (!r.ok) {
          const j = await r.json().catch(() => ({}))
          novos[id] = { ok: false, erro: j?.error || `erro ${r.status}` }
        } else novos[id] = { ok: true }
      } catch (e: any) {
        novos[id] = { ok: false, erro: e?.message || 'falhou' }
      }
      setResultados({ ...novos })
    }
    setEnviando(false)
    if (Object.values(novos).every((x) => x.ok)) setTimeout(onClose, 900)
  }

  const feitos = Object.keys(resultados).length > 0

  return (
    <div className="fixed inset-0 z-[80] flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,.45)' }} onClick={onClose}>
      <div className="w-full max-w-md rounded-xl shadow-2xl flex flex-col max-h-[80vh]" style={{ background: 'var(--wa-menu, #fff)', color: 'var(--wa-text, #111)' }}
           onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center gap-2 px-4 py-3" style={{ borderBottom: '1px solid var(--wa-divider, #ddd)' }}>
          <ArrowBendUpRight size={18} weight="bold" />
          <h3 className="flex-1 text-[15px] font-semibold">Encaminhar mensagem</h3>
          <button onClick={onClose} title="Fechar"><X size={18} /></button>
        </div>
        <div className="px-4 py-2 text-[13px] opacity-80 truncate" title={previa}>“{previa.slice(0, 120)}”</div>
        <div className="px-4 pb-2">
          <div className="flex items-center gap-2 rounded-lg px-3 py-2" style={{ border: '1px solid var(--wa-divider, #ddd)' }}>
            <MagnifyingGlass size={16} />
            <input autoFocus value={q} onChange={(e) => setQ(e.target.value)} placeholder="Nome ou telefone do contato"
                   className="flex-1 bg-transparent outline-none text-[14px]" />
            {buscando && <CircleNotch size={14} className="animate-spin" />}
          </div>
        </div>
        <div className="flex-1 overflow-y-auto px-2 min-h-[120px]">
          {achados.map((h) => {
            const l: any = h.lead
            const marcado = !!escolhidos[l.id]
            const r = resultados[l.id]
            return (
              <button key={l.id} onClick={() => alternar(l.id, l.title || l.phone)} disabled={enviando}
                      className="w-full flex items-center gap-3 px-3 py-2 rounded-lg text-left hover:bg-black/5">
                <span className="w-5 h-5 rounded-full flex items-center justify-center shrink-0"
                      style={{ background: marcado ? 'var(--wa-green, #25d366)' : 'transparent', border: '1px solid var(--wa-divider, #bbb)' }}>
                  {marcado && <Check size={12} weight="bold" className="text-white" />}
                </span>
                <span className="flex-1 min-w-0">
                  <span className="block text-[14px] truncate">{l.title || l.phone}</span>
                  <span className="block text-[12px] opacity-60 truncate">{l.phone}</span>
                </span>
                {r && <span className="text-[12px]" style={{ color: r.ok ? 'var(--wa-green, #25d366)' : '#dc2626' }}>{r.ok ? 'enviado' : r.erro}</span>}
              </button>
            )
          })}
          {q.trim().length >= 2 && !buscando && achados.length === 0 && <p className="px-3 py-4 text-[13px] opacity-60">Ninguém encontrado.</p>}
        </div>
        <div className="flex items-center gap-2 px-4 py-3" style={{ borderTop: '1px solid var(--wa-divider, #ddd)' }}>
          <span className="flex-1 text-[13px] opacity-70">{Object.keys(escolhidos).length ? `${Object.keys(escolhidos).length} escolhido(s)` : 'Escolha quem recebe'}</span>
          <button onClick={enviar} disabled={!Object.keys(escolhidos).length || enviando || !previa}
                  className="px-4 py-1.5 rounded-lg text-[14px] font-medium text-white disabled:opacity-40" style={{ background: 'var(--wa-green, #25d366)' }}>
            {enviando ? 'Enviando…' : feitos ? 'Enviar de novo os que falharam' : 'Encaminhar'}
          </button>
        </div>
      </div>
    </div>
  )
}
