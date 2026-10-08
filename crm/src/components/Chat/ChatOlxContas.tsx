'use client'

/**
 * A ABA CHAT OLX (Pedro, 08/10/2026): "serão 2 contas, esse chat olx vai ser 2 abas, aba Conta proprietários
 * e aba Conta corretores ... quero responder o chat da olx pelo meu crm, enviar e receber mensagens".
 *
 * Em cima, as duas contas. Cada uma tem a sua faixa de estado (conectada à OLX? recebendo mensagens?), a
 * lista de conversas à esquerda e a conversa à direita, com a caixa de resposta. A conversa chega pelo webhook
 * oficial da OLX e a resposta sai por /autoservice/v1/chat/send (ver crm/docs/olx/chat-da-olx.md).
 *
 * A resposta só aparece como enviada quando a OLX aceita. Se ela recusar, o texto continua na caixa e a
 * faixa vermelha diz o motivo.
 *
 * O botão "Consultas do bot" mostra o que o bot da OLX consultou (ChatOlx.tsx, migração 309): não é conta,
 * por isso fica à parte das duas abas.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ArrowClockwise, ArrowLeft, ArrowSquareOut, ChatsCircle, CheckCircle, CircleNotch, MagnifyingGlass, PaperPlaneRight,
  PlugsConnected, Robot, User, WarningCircle, X,
} from '@phosphor-icons/react'
import { CONTAS_OLX, NOME_DA_CONTA_OLX, type ChatOlxNaLista, type ContaOlx, type EstadoDaContaOlx, type MensagemOlx } from '@/lib/olxChatTipos'
import ChatOlx from './ChatOlx'

type Visao = ContaOlx | 'bot'

const FUSO = 'America/Manaus'
const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
const diaDe = (iso: string) => new Date(iso).toLocaleDateString('en-CA', { timeZone: FUSO })
const horaDe = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' })
function quandoCurto(iso: string | null) {
  if (!iso) return ''
  return diaDe(iso) === diaDe(new Date().toISOString())
    ? horaDe(iso)
    : new Date(iso).toLocaleDateString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit' })
}
const quandoInteiro = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
const nomeDe = (c: ChatOlxNaLista) => c.nome || 'Sem nome'
/** o anúncio na OLX pelo identificador (o formato que a própria OLX usa nas notificações dela) */
const linkDoAnuncio = (listId: string | null) => (listId && /^\d{5,}$/.test(listId) ? `https://www.olx.com.br/vi/${listId}.htm` : null)

async function pedir<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, init)
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j?.error || j?.erro || `Erro ${r.status}`)
  return j as T
}

/* ── a faixa de estado da conta ── */
function EstadoDaConta({ conta, estado, aoLigar, ligando }: {
  conta: ContaOlx; estado: EstadoDaContaOlx | null; aoLigar: () => void; ligando: boolean
}) {
  if (!estado) return null
  const nome = NOME_DA_CONTA_OLX[conta].toLowerCase()
  const linha = 'px-4 py-2 text-[13px] flex flex-wrap items-center gap-x-3 gap-y-1.5'
  if (estado.conectada && estado.webhookAtivo) {
    return (
      <div className={linha} style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)', color: 'var(--wa-text-2)' }}>
        <CheckCircle size={16} weight="fill" style={{ color: 'var(--wa-green)' }} />
        <span>
          Conectada à OLX{estado.olxNome ? ` como ${estado.olxNome}` : ''}{estado.olxEmail ? ` (${estado.olxEmail})` : ''}. Recebendo as mensagens do chat
          {estado.conectadaEm ? ` desde ${quandoInteiro(estado.conectadaEm)}` : ''}.
        </span>
      </div>
    )
  }
  return (
    <div className={linha} style={{ background: '#FEF3C7', color: '#78350F' }}>
      <WarningCircle size={16} weight="fill" />
      {!estado.aplicativoCadastrado ? (
        <span className="flex-1 min-w-[220px]">
          Falta cadastrar no servidor o aplicativo da OLX (client_id e client_secret). Sem isso não dá para conectar a {nome}.
        </span>
      ) : !estado.conectada ? (
        <>
          <span className="flex-1 min-w-[220px]">
            A {nome} ainda não está conectada à OLX. Antes de clicar, entre na OLX <b>com esta conta</b> neste navegador: vale a conta que estiver aberta lá.
          </span>
          <a href={`/api/olx/conectar?conta=${conta}`} className="wa-chip wa-chip--on inline-flex items-center gap-1.5">
            <PlugsConnected size={15} /> Conectar a conta
          </a>
        </>
      ) : (
        <>
          <span className="flex-1 min-w-[220px]">
            A conta está conectada, mas a OLX não ligou o recebimento das mensagens{estado.webhookResposta ? ` (${estado.webhookResposta})` : ''}.
          </span>
          <button type="button" disabled={ligando} onClick={aoLigar} className="wa-chip wa-chip--on inline-flex items-center gap-1.5">
            {ligando ? <CircleNotch size={15} className="animate-spin" /> : <PlugsConnected size={15} />} Ligar o recebimento
          </button>
        </>
      )}
    </div>
  )
}

/* ── uma conta: lista, conversa e resposta ── */
function ContaOlxAba({ conta }: { conta: ContaOlx }) {
  const [estado, setEstado] = useState<EstadoDaContaOlx | null>(null)
  const [chats, setChats] = useState<ChatOlxNaLista[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [selId, setSelId] = useState<number | null>(null)
  const [msgs, setMsgs] = useState<MensagemOlx[] | null>(null)
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const [aviso, setAviso] = useState<{ texto: string; erro?: boolean } | null>(null)
  const [ligando, setLigando] = useState(false)
  const fim = useRef<HTMLDivElement>(null)

  const carregar = useCallback(() => {
    pedir<{ estado: EstadoDaContaOlx; chats: ChatOlxNaLista[] }>(`/api/olx/chat?conta=${conta}`)
      .then((d) => { setEstado(d.estado); setChats(d.chats); setErro(null) })
      .catch((e) => setErro(e.message))
  }, [conta])
  useEffect(() => { carregar(); const t = setInterval(carregar, 15_000); return () => clearInterval(t) }, [carregar])

  const lerConversa = useCallback((id: number) => {
    pedir<{ mensagens: MensagemOlx[] }>(`/api/olx/chat/${id}?conta=${conta}`)
      .then((d) => setMsgs(d.mensagens))
      .catch((e) => setAviso({ texto: e.message, erro: true }))
  }, [conta])
  useEffect(() => {
    setMsgs(null); setTexto(''); setAviso(null)
    if (!selId) return
    lerConversa(selId)
    const t = setInterval(() => lerConversa(selId), 8_000)
    return () => clearInterval(t)
  }, [selId, lerConversa])
  // a conversa desce até a última mensagem quando chega uma nova
  const quantas = msgs?.length ?? 0
  useEffect(() => { fim.current?.scrollIntoView({ block: 'end' }) }, [quantas, selId])

  const filtrados = useMemo(() => {
    const q = sem(busca.trim())
    return (chats || []).filter((c) => !q || sem([c.nome, c.email, c.telefone, c.ultimaTexto, c.listId].filter(Boolean).join(' ')).includes(q))
  }, [chats, busca])
  const sel = useMemo(() => (chats || []).find((c) => c.id === selId) || null, [chats, selId])
  const podeResponder = !!estado?.conectada

  async function mandar() {
    const t = texto.trim()
    if (!t || !selId || enviando) return
    setEnviando(true); setAviso(null)
    try {
      await pedir(`/api/olx/chat/${selId}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ conta, texto: t }) })
      setTexto('')
      lerConversa(selId); carregar()
    } catch (e: any) {
      setAviso({ texto: e.message, erro: true })
    } finally {
      setEnviando(false)
    }
  }

  async function ligarRecebimento() {
    setLigando(true); setAviso(null)
    try {
      const r = await pedir<{ ok: boolean; resposta: string }>('/api/olx/conectar', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ conta }),
      })
      setAviso({ texto: `Recebimento ligado na OLX (${r.resposta}).` })
    } catch (e: any) {
      setAviso({ texto: e.message, erro: true })
    } finally {
      setLigando(false); carregar()
    }
  }

  const lista = (
    <div className="h-full min-h-0 flex flex-col" style={{ background: 'var(--wa-panel)' }}>
      <div className="px-3 pb-2 pt-2 flex items-center gap-2">
        <label className="wa-busca flex-1"><MagnifyingGlass size={18} />
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Procurar conversa" aria-label="Procurar conversa" />
          {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} /></button>}
        </label>
        <button type="button" className="wa-icone-btn" onClick={carregar} title="Atualizar agora"><ArrowClockwise size={20} /></button>
      </div>
      <div className="flex-1 overflow-y-auto wa-rolagem">
        {!chats && !erro && (
          <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}>
            <CircleNotch size={18} className="animate-spin" /> Lendo as conversas…
          </p>
        )}
        {erro && <p className="text-center text-[14px] mt-10 px-6 text-red-500">{erro}</p>}
        {filtrados.map((c) => (
          <button key={c.id} type="button" onClick={() => setSelId(c.id)} className={`wa-linha w-full text-left ${selId === c.id ? 'wa-linha--sel' : ''}`}>
            <span className="w-[49px] h-[49px] mx-2 rounded-full grid place-items-center flex-shrink-0"
                  style={{ background: 'var(--wa-chip-bg)', color: 'var(--wa-icon)' }}><User size={24} /></span>
            <span className="flex-1 min-w-0 py-2.5 pr-3" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
              <span className="flex items-center gap-2">
                <span className="flex-1 truncate text-[15.5px]" style={{ color: 'var(--wa-text)' }}>{nomeDe(c)}</span>
                <span className="text-[11.5px] flex-shrink-0" style={{ color: c.naoLidas ? 'var(--wa-green)' : 'var(--wa-text-2)' }}>{quandoCurto(c.ultimaEm)}</span>
              </span>
              <span className="flex items-center gap-1.5 mt-0.5">
                <span className="flex-1 truncate text-[13px]" style={{ color: 'var(--wa-text-2)' }}>
                  {c.ultimaDe === 'nos' ? 'Você: ' : ''}{c.ultimaTexto || '—'}
                </span>
                {c.naoLidas > 0 && <span className="wa-badge">{c.naoLidas > 99 ? '99+' : c.naoLidas}</span>}
              </span>
            </span>
          </button>
        ))}
        {chats && !filtrados.length && (
          <p className="text-center text-[14px] mt-8 px-6" style={{ color: 'var(--wa-text-2)' }}>
            {chats.length ? 'Nenhuma conversa assim.'
              : estado?.conectada && estado.webhookAtivo ? 'Nenhuma mensagem chegou ainda. Quando alguém escrever no chat da OLX desta conta, a conversa aparece aqui.'
              : 'As conversas aparecem aqui depois que a conta for conectada à OLX.'}
          </p>
        )}
      </div>
    </div>
  )

  const anuncio = sel ? linkDoAnuncio(sel.listId) : null
  const conversa = !sel ? (
    <div className="h-full flex flex-col items-center justify-center gap-2 px-8 text-center" style={{ background: 'var(--wa-conv-bg)' }}>
      <ChatsCircle size={48} style={{ color: 'var(--wa-text-2)' }} />
      <p className="text-[15px]" style={{ color: 'var(--wa-text)' }}>Escolha uma conversa da {NOME_DA_CONTA_OLX[conta].toLowerCase()}.</p>
      <p className="text-[13px] max-w-md" style={{ color: 'var(--wa-text-2)' }}>O que você responder aqui sai no chat da OLX, pela conta conectada.</p>
    </div>
  ) : (
    <div className="h-full min-h-0 flex flex-col" style={{ background: 'var(--wa-conv-bg)' }}>
      <div className="wa-topo gap-2">
        <button type="button" className="wa-icone-btn md:hidden" onClick={() => setSelId(null)} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <div className="flex-1 min-w-0">
          <p className="truncate text-[16px] font-semibold" style={{ color: 'var(--wa-text)' }}>{nomeDe(sel)}</p>
          <p className="text-[12.5px] truncate" style={{ color: 'var(--wa-text-2)' }}>
            {[sel.telefone, sel.email, sel.listId ? `anúncio ${sel.listId}` : null].filter(Boolean).join(' · ') || 'sem telefone nem e-mail'}
          </p>
        </div>
        {anuncio && (
          <a href={anuncio} target="_blank" rel="noopener noreferrer" className="wa-chip inline-flex items-center gap-1.5 flex-shrink-0" title="Abre o anúncio na OLX, em outra aba">
            <ArrowSquareOut size={15} /> Ver o anúncio
          </a>
        )}
      </div>
      {aviso && (
        <div className="px-4 py-2 text-[13px] flex items-start gap-2" style={{ background: aviso.erro ? '#FEE2E2' : '#DCFCE7', color: aviso.erro ? '#7F1D1D' : '#14532D' }}>
          <span className="flex-1">{aviso.texto}</span><button type="button" onClick={() => setAviso(null)} aria-label="Fechar"><X size={14} /></button>
        </div>
      )}
      <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-3 flex flex-col gap-1.5">
        {msgs === null && <p className="text-center text-[13px]" style={{ color: 'var(--wa-text-2)' }}>carregando…</p>}
        {msgs?.map((m) => m.de === 'sistema' ? (
          <p key={m.id} className="self-center max-w-[80%] text-center text-[12.5px] rounded-lg px-3 py-1.5" style={{ background: 'var(--wa-panel)', color: 'var(--wa-text-2)' }}>
            {m.texto} <span className="opacity-70">· {quandoInteiro(m.quando)}</span>
          </p>
        ) : (
          <div key={m.id} className={`max-w-[78%] rounded-lg px-2.5 py-1.5 text-[14px] shadow-sm ${m.de === 'nos' ? 'self-end' : 'self-start'}`}
               style={{ background: m.de === 'nos' ? 'var(--wa-out)' : 'var(--wa-in)', color: m.de === 'nos' ? 'var(--wa-out-ink)' : 'var(--wa-in-ink)' }}>
            <p className="whitespace-pre-wrap break-words">{m.texto}</p>
            <p className="mt-0.5 text-right text-[11px] opacity-70">
              {m.de === 'nos' && m.enviadaPor ? `${m.enviadaPor} · ` : ''}{quandoInteiro(m.quando)}
            </p>
          </div>
        ))}
        <div ref={fim} />
      </div>
      <div className="px-3 py-2 flex items-end gap-2" style={{ background: 'var(--wa-panel)', borderTop: '1px solid var(--wa-divider)' }}>
        <textarea
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); void mandar() } }}
          disabled={!podeResponder || enviando}
          rows={Math.min(5, Math.max(1, texto.split('\n').length))}
          maxLength={2000}
          placeholder={podeResponder ? 'Responder pelo chat da OLX' : 'Conecte a conta à OLX para responder por aqui'}
          aria-label="Mensagem"
          className="flex-1 resize-none rounded-lg px-3 py-2 text-[14.5px] outline-none"
          style={{ background: 'var(--wa-app)', color: 'var(--wa-text)', border: '1px solid var(--wa-divider)' }}
        />
        <button type="button" onClick={() => void mandar()} disabled={!podeResponder || enviando || !texto.trim()}
                className="wa-icone-btn !w-10 !h-10 disabled:opacity-40" title="Enviar" aria-label="Enviar">
          {enviando ? <CircleNotch size={20} className="animate-spin" /> : <PaperPlaneRight size={20} weight="fill" style={{ color: 'var(--wa-green)' }} />}
        </button>
      </div>
    </div>
  )

  return (
    <div className="flex-1 min-h-0 flex flex-col">
      <EstadoDaConta conta={conta} estado={estado} aoLigar={() => void ligarRecebimento()} ligando={ligando} />
      {aviso && !sel && (
        <div className="px-4 py-2 text-[13px] flex items-start gap-2" style={{ background: aviso.erro ? '#FEE2E2' : '#DCFCE7', color: aviso.erro ? '#7F1D1D' : '#14532D' }}>
          <span className="flex-1">{aviso.texto}</span><button type="button" onClick={() => setAviso(null)} aria-label="Fechar"><X size={14} /></button>
        </div>
      )}
      <div className="flex flex-1 min-h-0">
        <div className={`flex-shrink-0 h-full min-h-0 ${selId ? 'hidden md:block' : 'w-full md:w-auto'}`}
             style={{ flexBasis: 'clamp(300px, 32%, 440px)', borderRight: '1px solid var(--wa-divider)' }}>
          {lista}
        </div>
        <div className={`flex-1 min-w-0 h-full min-h-0 ${selId ? '' : 'hidden md:block'}`}>{conversa}</div>
      </div>
    </div>
  )
}

export default function ChatOlxContas() {
  const [visao, setVisao] = useState<Visao>('proprietarios')
  const [aviso, setAviso] = useState<string | null>(null)

  // ?conta= e ?aviso= (a volta da OLX). Lido do window, não do useSearchParams: o hook obrigaria a envolver
  // a página em <Suspense> (o mesmo motivo do LoginForm).
  useEffect(() => {
    const q = new URLSearchParams(window.location.search)
    const conta = q.get('conta')
    if (conta && (CONTAS_OLX as readonly string[]).includes(conta)) setVisao(conta as ContaOlx)
    const a = q.get('aviso')
    if (a) {
      setAviso(a.slice(0, 400))
      // o aviso não fica na barra de endereço (recarregar a página não o repete)
      window.history.replaceState(null, '', window.location.pathname + (conta ? `?conta=${encodeURIComponent(conta)}` : ''))
    }
  }, [])

  return (
    <div className="flex flex-col flex-1 min-h-0 h-full">
      <div className="flex items-center gap-1.5 px-3 py-2 flex-wrap" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        <span className="text-[15px] font-semibold flex items-center gap-2 mr-2" style={{ color: 'var(--wa-text)' }}><ChatsCircle size={20} /> Chat OLX</span>
        {CONTAS_OLX.map((c) => (
          <button key={c} type="button" onClick={() => setVisao(c)} className={`wa-chip ${visao === c ? 'wa-chip--on' : ''}`}>{NOME_DA_CONTA_OLX[c]}</button>
        ))}
        <button type="button" onClick={() => setVisao('bot')} title="Os anúncios que o bot da OLX consultou e a mensagem que saiu para cada um"
                className={`wa-chip inline-flex items-center gap-1.5 ml-auto ${visao === 'bot' ? 'wa-chip--on' : ''}`}>
          <Robot size={15} /> Consultas do bot
        </button>
      </div>
      {aviso && (
        <div className="px-4 py-2 text-[13px] flex items-start gap-2" style={{ background: 'var(--wa-chip-on-bg)', color: 'var(--wa-chip-on-ink)' }}>
          <span className="flex-1">{aviso}</span><button type="button" onClick={() => setAviso(null)} aria-label="Fechar"><X size={14} /></button>
        </div>
      )}
      {visao === 'bot' ? <ChatOlx /> : <ContaOlxAba key={visao} conta={visao} />}
    </div>
  )
}
