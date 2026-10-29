'use client'

/**
 * RESPOSTAS TEL (Pedro, 29/10/2026): "pega todas as dúvidas que ainda falta o Tel responder de conversas, e faz um painel
 * Respostas Tel ... só com as dúvidas da Nay, a pergunta do cliente, e um campo para o Tel responder, igual Tinder
 * passando para o lado para ele responder todas as dúvidas acumuladas".
 *
 * Um cartão por vez. Arrastar para a direita (ou "Enviar") manda a resposta; para a esquerda (ou "Pular") deixa para
 * depois, no fim da pilha. "Descartar" tira a dúvida sem responder. Quem leva a resposta ao cliente é o banco
 * (crm_tel_responder, 527): na Leads a Nay Leads entrega; na Parceria sai pela caixa da Nay.
 */
import { useCallback, useEffect, useRef, useState } from 'react'
import { ArrowLeft, ArrowRight, ChatTeardropText, Trash, CheckCircle } from '@phosphor-icons/react'

interface Duvida {
  fonte: 'fila' | 'duvida'; id: number; linha: string; estado: string
  cliente: string | null; telefone: string | null; codigo: number | null; imovel: string | null
  pergunta: string; detalhe: string | null; criada_em: string; cliente_disse: string | null
}

const ARRASTO = 120

function formatarTelefone(v: string | null) {
  const d = (v || '').replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  if (d.length === 11) return `${d.slice(0, 2)} ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `${d.slice(0, 2)} ${d.slice(2, 6)}-${d.slice(6)}`
  return v || ''
}

function quando(iso: string) {
  const d = new Date(iso)
  return d.toLocaleString('pt-BR', { timeZone: 'America/Manaus', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
}

const ESTADO: Record<string, string> = {
  fila: 'esperando o Tel', perguntada: 'perguntada no PV do Tel', agente: 'com o agente', com_o_tel: 'esperando o Tel',
}

export default function RespostasTelPage() {
  const [pilha, setPilha] = useState<Duvida[] | null>(null)
  const [semMigracao, setSemMigracao] = useState(false)
  const [respostas, setRespostas] = useState<Record<string, string>>({})
  const [enviando, setEnviando] = useState(false)
  const [erro, setErro] = useState('')
  const [feitas, setFeitas] = useState(0)
  const [dx, setDx] = useState(0)
  const [saindo, setSaindo] = useState<'dir' | 'esq' | null>(null)
  const inicio = useRef<number | null>(null)

  const carregar = useCallback(() => {
    fetch('/api/respostas-tel').then((r) => r.json()).then((j) => {
      setPilha(j.duvidas || [])
      setSemMigracao(!!j.semMigracao)
    }).catch(() => setErro('Não consegui ler as dúvidas.'))
  }, [])
  useEffect(() => { carregar() }, [carregar])

  const atual = pilha?.[0]
  const chave = atual ? `${atual.fonte}-${atual.id}` : ''
  const texto = respostas[chave] || ''

  function animarSaida(lado: 'dir' | 'esq', depois: () => void) {
    setSaindo(lado)
    setTimeout(() => { depois(); setSaindo(null); setDx(0) }, 260)
  }

  function pular() {
    if (!pilha || pilha.length < 2) { setDx(0); return }
    setErro('')
    animarSaida('esq', () => setPilha((p) => (p && p.length ? [...p.slice(1), p[0]] : p)))
  }

  async function mandar(acao: 'responder' | 'descartar') {
    if (!atual || enviando) return
    if (acao === 'responder' && !texto.trim()) { setErro('Escreva a resposta antes de enviar.'); setDx(0); return }
    if (acao === 'descartar' && !confirm('Descartar esta dúvida sem responder?')) return
    setEnviando(true); setErro('')
    try {
      const r = await fetch('/api/respostas-tel', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ fonte: atual.fonte, id: atual.id, acao, texto }),
      })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || !j.ok) {
        setErro(j.mensagem || j.error || 'Não consegui.'); setDx(0)
        if (r.status === 409) carregar()   // alguém já respondeu pelo PV: a pilha volta como está no banco
        return
      }
      animarSaida('dir', () => {
        setPilha((p) => (p ? p.filter((d) => !(d.fonte === atual.fonte && d.id === atual.id)) : p))
        setFeitas((n) => n + 1)
      })
    } finally {
      setEnviando(false)
    }
  }

  // o arrasto: só pelo cartão, fora do campo de texto
  function comecar(e: React.PointerEvent) {
    if ((e.target as HTMLElement).closest('textarea, button')) return
    inicio.current = e.clientX
    ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
  }
  function mover(e: React.PointerEvent) {
    if (inicio.current !== null) setDx(e.clientX - inicio.current)
  }
  function soltar() {
    if (inicio.current === null) return
    inicio.current = null
    if (dx > ARRASTO) mandar('responder')
    else if (dx < -ARRASTO) pular()
    else setDx(0)
  }

  const desloc = saindo === 'dir' ? 700 : saindo === 'esq' ? -700 : dx
  const estiloCartao: React.CSSProperties = {
    transform: `translateX(${desloc}px) rotate(${desloc / 25}deg)`,
    transition: inicio.current !== null ? 'none' : 'transform 0.26s ease, opacity 0.26s ease',
    opacity: saindo ? 0 : 1,
    touchAction: 'pan-y',
  }

  return (
    <div className="p-4 md:p-6 max-w-[640px] mx-auto">
      <h1 className="text-xl md:text-2xl font-bold text-ink flex items-center gap-2">
        <ChatTeardropText size={24} weight="fill" className="text-accent" /> Respostas Tel
      </h1>
      <p className="text-sm text-muted mt-1">
        As dúvidas que a Nay está esperando você responder. Arraste para a direita para enviar, para a esquerda para pular.
      </p>

      {semMigracao && (
        <div className="panel rounded-xl border border-line p-3 mt-4 text-sm">O banco da Nay ainda não tem o Respostas Tel (migração 527).</div>
      )}

      {pilha === null && !erro && <div className="mt-8 text-sm text-muted">Carregando…</div>}

      {pilha && pilha.length === 0 && !semMigracao && (
        <div className="panel rounded-xl border border-line p-8 mt-6 text-center">
          <CheckCircle size={40} weight="fill" className="mx-auto text-emerald-500" />
          <div className="mt-2 font-semibold text-ink">Nenhuma dúvida esperando</div>
          {feitas > 0 && <div className="text-sm text-muted mt-1">{feitas} respondida{feitas > 1 ? 's' : ''} agora.</div>}
        </div>
      )}

      {atual && (
        <>
          <div className="flex items-center justify-between mt-4 mb-2 text-xs text-muted">
            <span>{pilha!.length} esperando{feitas > 0 ? ` · ${feitas} respondida${feitas > 1 ? 's' : ''} agora` : ''}</span>
            <span>{quando(atual.criada_em)}</span>
          </div>

          <div className="relative">
            {pilha!.length > 1 && (
              <div className="absolute inset-x-3 -bottom-2 h-full rounded-2xl border border-line panel opacity-60" aria-hidden />
            )}
            <div
              key={chave}
              className="relative panel rounded-2xl border border-line p-4 md:p-5 shadow-lg select-none"
              style={estiloCartao}
              onPointerDown={comecar} onPointerMove={mover} onPointerUp={soltar} onPointerCancel={soltar}
            >
              {dx > 30 && <div className="absolute top-3 right-3 text-xs font-bold text-emerald-500 border border-emerald-500 rounded px-2 py-0.5">ENVIAR</div>}
              {dx < -30 && <div className="absolute top-3 left-3 text-xs font-bold text-amber-500 border border-amber-500 rounded px-2 py-0.5">PULAR</div>}

              <div className="flex flex-wrap items-center gap-2">
                <span className={`text-[11px] font-semibold rounded-full px-2 py-0.5 ${atual.linha === 'parceria' ? 'bg-sky-500/15 text-sky-600 dark:text-sky-300' : 'bg-violet-500/15 text-violet-600 dark:text-violet-300'}`}>
                  {atual.linha === 'parceria' ? 'Parceria' : 'Leads'}
                </span>
                <span className="text-[11px] text-muted">{ESTADO[atual.estado] || atual.estado}</span>
              </div>

              <div className="mt-2 font-semibold text-ink">{atual.cliente || 'Sem nome'}</div>
              <div className="text-xs text-muted">{formatarTelefone(atual.telefone)}</div>

              {(atual.codigo || atual.imovel) && (
                <div className="mt-3 text-sm text-ink">
                  {atual.codigo ? <span className="font-semibold">#{atual.codigo}</span> : null}
                  {atual.imovel ? <span className="text-ink"> · {atual.imovel}</span> : null}
                </div>
              )}

              <div className="mt-3">
                <div className="text-[11px] font-semibold uppercase tracking-wide text-muted">A Nay pergunta</div>
                <div className="mt-1 text-[15px] text-ink whitespace-pre-wrap">{atual.pergunta}</div>
              </div>

              {atual.cliente_disse && (
                <div className="mt-3">
                  <div className="text-[11px] font-semibold uppercase tracking-wide text-muted">O cliente disse</div>
                  <div className="mt-1 text-sm text-ink whitespace-pre-wrap border-l-2 border-line pl-2">{atual.cliente_disse}</div>
                </div>
              )}

              {atual.detalhe && atual.detalhe !== atual.pergunta && (
                <div className="mt-3 text-xs text-muted whitespace-pre-wrap">{atual.detalhe}</div>
              )}

              <textarea
                value={texto}
                onChange={(e) => setRespostas((r) => ({ ...r, [chave]: e.target.value }))}
                placeholder="Sua resposta (vai ao cliente pela Nay)"
                rows={3}
                className="mt-4 w-full rounded-lg border border-line bg-transparent p-2 text-sm text-ink focus:outline-none focus:border-accent"
              />

              {erro && <div className="mt-2 text-sm text-red-500">{erro}</div>}

              <div className="mt-3 flex items-center gap-2">
                <button onClick={() => mandar('descartar')} disabled={enviando} title="Descartar sem responder"
                  className="h-10 px-3 rounded-lg border border-line text-muted hover:text-red-500 hover:border-red-400 disabled:opacity-50">
                  <Trash size={18} />
                </button>
                <button onClick={pular} disabled={enviando || pilha!.length < 2}
                  className="h-10 px-3 rounded-lg border border-line text-ink flex items-center gap-1.5 disabled:opacity-40">
                  <ArrowLeft size={16} /> Pular
                </button>
                <button onClick={() => mandar('responder')} disabled={enviando || !texto.trim()}
                  className="ml-auto h-10 px-4 rounded-lg bg-accent text-white font-semibold flex items-center gap-1.5 disabled:opacity-50">
                  {enviando ? 'Enviando…' : 'Enviar resposta'} <ArrowRight size={16} />
                </button>
              </div>
            </div>
          </div>
        </>
      )}

      {!atual && erro && <div className="mt-4 text-sm text-red-500">{erro}</div>}
    </div>
  )
}
