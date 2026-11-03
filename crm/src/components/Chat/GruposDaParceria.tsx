'use client'

/**
 * OS GRUPOS DA PARCERIA (Pedro, 03/10/2026: "preciso criar um painel com os grupos... ver, editar, mandar
 * msg, ler, tirar dados, do número parceria").
 *
 * À esquerda, os grupos do número da Parceria (mais recentes primeiro), com quantos participantes e as
 * marcas da casa: admin (o número da Parceria pode editar), disparo (o publicador manda imóvel ali),
 * corretores (os membros viram corretores que a Nay atende). Ao abrir um grupo:
 *   - Mensagens: as que foram GUARDADAS (a Z-API não entrega histórico) e a caixa para mandar;
 *   - Participantes: telefone, nome que a casa conhece, admin, corretor; planilha; e, se for admin,
 *     adicionar, remover, promover e rebaixar;
 *   - Configurações: nome, descrição, quem pode mandar/editar/adicionar (só admin muda).
 * Toda edição relê o grupo: a Z-API responde "ok" até quando nada mudou. Ver src/lib/gruposParceria.ts.
 */
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react'
import {
  ArrowClockwise, ArrowLeft, BellSlash, CircleNotch, Crown, DownloadSimple, Gear, MagnifyingGlass,
  Megaphone, PaperPlaneRight, UserMinus, UserPlus, UsersThree, ChatCircleText, X, Copy,
} from '@phosphor-icons/react'
import type { DadosDoGrupo, GrupoNaLista, Participante } from '@/lib/gruposParceria'
import TextoComLinks from './TextoComLinks'

type Aba = 'mensagens' | 'participantes' | 'config'
type Filtro = 'todos' | 'admin' | 'disparo' | 'corretores'
interface Msg { id: string; de_mim?: boolean; remetente?: string; remetente_nome?: string; tipo: string; texto?: string; midia_url?: string; quando: string }

const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
function fone(t: string) {
  const d = t.replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  if (d.length === 11) return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`
  if (d.length === 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`
  return t
}
const hora = (iso: string | number) => new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Manaus', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
const ICONE_TIPO: Record<string, string> = { imagem: '📷 Foto', video: '🎥 Vídeo', audio: '🎤 Áudio', documento: '📄 Documento', figurinha: 'Figurinha', outro: 'Mensagem' }

async function pedir<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, init)
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j?.error || `Erro ${r.status}`)
  return j as T
}

function Selo({ children, cor, titulo }: { children: ReactNode; cor: string; titulo?: string }) {
  return <span title={titulo} className="inline-flex items-center gap-1 rounded-full px-1.5 py-[1px] text-[11px] font-semibold"
               style={{ background: cor + '22', color: cor }}>{children}</span>
}

export default function GruposDaParceria() {
  const [lista, setLista] = useState<GrupoNaLista[] | null>(null)
  const [erroLista, setErroLista] = useState<string | null>(null)
  const [avisoLista, setAvisoLista] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [filtro, setFiltro] = useState<Filtro>('todos')
  const [selId, setSelId] = useState<string | null>(null)
  const [dados, setDados] = useState<DadosDoGrupo | null>(null)
  const [erroDados, setErroDados] = useState<string | null>(null)
  const [aba, setAba] = useState<Aba>('mensagens')
  const [aviso, setAviso] = useState<{ texto: string; erro?: boolean } | null>(null)
  const [ocupado, setOcupado] = useState(false)

  const carregarLista = useCallback(() => {
    setErroLista(null)
    pedir<{ grupos: GrupoNaLista[]; aviso?: string }>('/api/parceria/grupos')
      .then((d) => { setLista(d.grupos); setAvisoLista(d.aviso || null) })
      .catch((e) => setErroLista(e.message))
  }, [])
  useEffect(() => { carregarLista() }, [carregarLista])

  const carregarDados = useCallback((id: string, fresco = false) => {
    setErroDados(null)
    pedir<DadosDoGrupo>(`/api/parceria/grupos/${encodeURIComponent(id)}${fresco ? '?fresco=1' : ''}`)
      .then(setDados)
      .catch((e) => setErroDados(e.message))
  }, [])
  useEffect(() => { setDados(null); setAviso(null); if (selId) carregarDados(selId) }, [selId, carregarDados])

  const filtrados = useMemo(() => {
    const q = sem(busca.trim())
    return (lista || []).filter((g) =>
      (!q || sem(g.nome).includes(q)) &&
      (filtro === 'todos' || (filtro === 'admin' && g.souAdmin) || (filtro === 'disparo' && g.casa.disparo) ||
       (filtro === 'corretores' && g.casa.corretores)))
  }, [lista, busca, filtro])
  const conta = (f: Filtro) => (lista || []).filter((g) => f === 'admin' ? g.souAdmin : f === 'disparo' ? g.casa.disparo : g.casa.corretores).length

  async function editar(corpo: Record<string, unknown>, pergunta?: string) {
    if (!selId || ocupado) return
    if (pergunta && !window.confirm(pergunta)) return
    setOcupado(true); setAviso(null)
    try {
      const r = await pedir<{ grupo: DadosDoGrupo; conferido: boolean }>(`/api/parceria/grupos/${encodeURIComponent(selId)}`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo),
      })
      setDados(r.grupo)
      setAviso(r.conferido ? { texto: 'Feito.' }
        : { texto: 'A Z-API aceitou, mas a mudança ainda não aparece no grupo. Atualize em alguns segundos para conferir.', erro: true })
      carregarLista()
    } catch (e: any) {
      setAviso({ texto: e.message, erro: true })
    } finally {
      setOcupado(false)
    }
  }

  const listaHtml = (
    <div className="h-full min-h-0 flex flex-col" style={{ background: 'var(--wa-panel)' }}>
      <div className="wa-topo justify-between gap-2">
        <span className="text-[16px] font-semibold flex items-center gap-2" style={{ color: 'var(--wa-text)' }}>
          <UsersThree size={22} /> Grupos {lista && <span className="text-[13px] font-normal" style={{ color: 'var(--wa-text-2)' }}>{lista.length}</span>}
        </span>
        <div className="flex items-center gap-1">
          <a className="wa-icone-btn" href="/api/parceria/grupos/participantes" title="Planilha com as pessoas de todos os grupos (demora uns segundos)">
            <DownloadSimple size={20} />
          </a>
          <button type="button" className="wa-icone-btn" onClick={() => { setLista(null); carregarLista() }} title="Atualizar a lista">
            <ArrowClockwise size={20} />
          </button>
        </div>
      </div>
      <div className="px-3 pb-2 pt-2">
        <label className="wa-busca"><MagnifyingGlass size={18} />
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Procurar grupo" aria-label="Procurar grupo" />
          {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} /></button>}
        </label>
        <div className="flex flex-wrap gap-1.5 mt-2">
          {([['todos', 'Todos'], ['admin', 'Sou admin'], ['disparo', 'Disparo'], ['corretores', 'Corretores']] as [Filtro, string][]).map(([f, r]) => (
            <button key={f} type="button" onClick={() => setFiltro(f)} className={`wa-chip ${filtro === f ? 'wa-chip--on' : ''}`}>
              {r}{f !== 'todos' && lista ? ` ${conta(f)}` : ''}
            </button>
          ))}
        </div>
      </div>
      <div className="flex-1 overflow-y-auto wa-rolagem">
        {!lista && !erroLista && (
          <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}>
            <CircleNotch size={18} className="animate-spin" /> Lendo os grupos na Z-API…
          </p>
        )}
        {erroLista && <p className="text-center text-[14px] mt-10 px-6 text-red-500">{erroLista}</p>}
        {avisoLista && <p className="text-[12.5px] px-4 py-2" style={{ color: 'var(--wa-text-2)' }}>{avisoLista}</p>}
        {filtrados.map((g) => (
          <button key={g.id} type="button" onClick={() => { setSelId(g.id); setAba('mensagens') }}
                  className={`wa-linha w-full text-left ${selId === g.id ? 'wa-linha--sel' : ''}`}>
            <span className="w-[49px] h-[49px] mx-2 rounded-full grid place-items-center flex-shrink-0"
                  style={{ background: 'var(--wa-chip-bg)', color: 'var(--wa-icon)' }}><UsersThree size={24} /></span>
            <span className="flex-1 min-w-0 py-2.5 pr-3" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
              <span className="flex items-center gap-2">
                <span className="flex-1 truncate text-[15.5px]" style={{ color: 'var(--wa-text)' }}>{g.nome}</span>
                {g.ultimaEm && <span className="text-[11.5px] flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}>{hora(g.ultimaEm)}</span>}
              </span>
              <span className="flex items-center gap-1.5 mt-0.5 flex-wrap">
                <span className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
                  {g.participantes != null ? `${g.participantes} participantes` : '…'}
                </span>
                {g.souAdmin && <Selo cor="#16a34a" titulo="O número da Parceria é admin: dá para editar"><Crown size={11} weight="fill" />admin</Selo>}
                {g.casa.disparo && <Selo cor="#7c3aed" titulo="O publicador manda imóvel neste grupo"><Megaphone size={11} weight="fill" />disparo</Selo>}
                {g.casa.corretores && <Selo cor="#0284c7" titulo="Os membros viram corretores que a Nay atende">corretores</Selo>}
                {g.silenciado && <BellSlash size={13} style={{ color: 'var(--wa-text-2)' }} />}
                {g.naoLidas > 0 && <span className="wa-badge ml-auto">{g.naoLidas > 99 ? '99+' : g.naoLidas}</span>}
              </span>
            </span>
          </button>
        ))}
        {lista && !filtrados.length && <p className="text-center text-[14px] mt-8" style={{ color: 'var(--wa-text-2)' }}>Nenhum grupo assim.</p>}
      </div>
    </div>
  )

  const detalhe = !selId ? (
    <div className="h-full flex flex-col items-center justify-center gap-2 px-8 text-center" style={{ background: 'var(--wa-conv-bg)' }}>
      <UsersThree size={48} style={{ color: 'var(--wa-text-2)' }} />
      <p className="text-[15px]" style={{ color: 'var(--wa-text)' }}>Escolha um grupo para ver as mensagens, os participantes e as configurações.</p>
      <p className="text-[13px] max-w-md" style={{ color: 'var(--wa-text-2)' }}>
        Editar (nome, descrição, participantes) só funciona nos grupos em que o número da Parceria é admin.
      </p>
    </div>
  ) : (
    <div className="h-full min-h-0 flex flex-col" style={{ background: 'var(--wa-conv-bg)' }}>
      <div className="wa-topo gap-2">
        <button type="button" className="wa-icone-btn md:hidden" onClick={() => setSelId(null)} aria-label="Voltar"><ArrowLeft size={20} /></button>
        <div className="flex-1 min-w-0">
          <p className="truncate text-[16px] font-semibold" style={{ color: 'var(--wa-text)' }}>{dados?.nome || lista?.find((g) => g.id === selId)?.nome}</p>
          <p className="text-[12.5px] truncate" style={{ color: 'var(--wa-text-2)' }}>
            {dados ? `${dados.participantes.length} participantes` : 'lendo o grupo…'}
            {dados && (dados.souAdmin ? ' · o número da Parceria é admin' : ' · só leitura (não é admin)')}
          </p>
        </div>
        <a className="wa-icone-btn" href={`/api/parceria/grupos/${encodeURIComponent(selId)}/participantes`} title="Planilha dos participantes"><DownloadSimple size={20} /></a>
        <button type="button" className="wa-icone-btn" title="Ler o grupo de novo na Z-API" onClick={() => { setDados(null); carregarDados(selId, true) }}><ArrowClockwise size={20} /></button>
      </div>
      <div className="flex gap-1.5 px-3 py-2" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        {([['mensagens', 'Mensagens', ChatCircleText], ['participantes', 'Participantes', UsersThree], ['config', 'Configurações', Gear]] as [Aba, string, typeof Gear][]).map(([k, r, I]) => (
          <button key={k} type="button" onClick={() => setAba(k)} className={`wa-chip inline-flex items-center gap-1.5 ${aba === k ? 'wa-chip--on' : ''}`}><I size={15} />{r}</button>
        ))}
      </div>
      {aviso && (
        <div className="px-4 py-2 text-[13px] flex items-start gap-2" style={{ background: aviso.erro ? '#FEF3C7' : '#DCFCE7', color: aviso.erro ? '#78350F' : '#14532D' }}>
          <span className="flex-1">{aviso.texto}</span><button type="button" onClick={() => setAviso(null)} aria-label="Fechar"><X size={14} /></button>
        </div>
      )}
      {erroDados && <p className="text-center text-[14px] mt-10 px-6 text-red-500">{erroDados}</p>}
      {!dados && !erroDados && (
        <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}>
          <CircleNotch size={18} className="animate-spin" /> Lendo o grupo…
        </p>
      )}
      {dados && aba === 'mensagens' && <AbaMensagens grupo={dados} aoAvisar={setAviso} />}
      {dados && aba === 'participantes' && <AbaParticipantes grupo={dados} ocupado={ocupado} editar={editar} />}
      {dados && aba === 'config' && <AbaConfig grupo={dados} ocupado={ocupado} editar={editar} />}
    </div>
  )

  return (
    <div className="flex flex-1 min-h-0 h-full">
      <div className={`flex-shrink-0 h-full min-h-0 ${selId ? 'hidden md:block' : 'w-full md:w-auto'}`}
           style={{ width: undefined, flexBasis: 'clamp(300px, 32%, 440px)', borderRight: '1px solid var(--wa-divider)' }}>
        {listaHtml}
      </div>
      <div className={`flex-1 min-w-0 h-full min-h-0 ${selId ? '' : 'hidden md:block'}`}>{detalhe}</div>
    </div>
  )
}

/* ── Mensagens: as guardadas e a caixa para mandar ── */
function AbaMensagens({ grupo, aoAvisar }: { grupo: DadosDoGrupo; aoAvisar: (a: { texto: string; erro?: boolean }) => void }) {
  const [msgs, setMsgs] = useState<Msg[] | null>(null)
  const [texto, setTexto] = useState('')
  const [enviando, setEnviando] = useState(false)
  const ler = useCallback(() => {
    pedir<{ mensagens: Msg[] }>(`/api/parceria/grupos/${encodeURIComponent(grupo.id)}/mensagens`)
      .then((d) => setMsgs(d.mensagens)).catch(() => setMsgs([]))
  }, [grupo.id])
  useEffect(() => { ler(); const t = setInterval(ler, 15_000); return () => clearInterval(t) }, [ler])

  async function mandar() {
    const t = texto.trim()
    if (!t || enviando) return
    if (!window.confirm(`Mandar esta mensagem no grupo "${grupo.nome}"?\n\nVai para ${grupo.participantes.length} pessoas, pelo número da Parceria.`)) return
    setEnviando(true)
    try {
      await pedir(`/api/parceria/grupos/${encodeURIComponent(grupo.id)}/mensagens`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ texto: t }),
      })
      setTexto('')
      aoAvisar({ texto: 'Mensagem enviada no grupo.' })
      setTimeout(ler, 4000)
    } catch (e: any) {
      aoAvisar({ texto: e.message, erro: true })
    } finally {
      setEnviando(false)
    }
  }

  const bloqueado = grupo.config.soAdminMandaMensagem && !grupo.souAdmin
  return (
    <>
      <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-3 flex flex-col-reverse gap-1.5">
        {msgs === null && <p className="text-center text-[13px]" style={{ color: 'var(--wa-text-2)' }}>carregando…</p>}
        {msgs && !msgs.length && (
          <div className="m-auto max-w-md text-center text-[13.5px] rounded-xl px-4 py-3" style={{ background: 'var(--wa-panel)', color: 'var(--wa-text-2)' }}>
            Nenhuma mensagem guardada deste grupo ainda. A Z-API não entrega o histórico: só aparece aqui o que
            chegar depois que a guarda das mensagens de grupo for ligada.
          </div>
        )}
        {msgs?.map((m) => (
          <div key={m.id} className={`max-w-[78%] rounded-lg px-2.5 py-1.5 text-[14px] shadow-sm ${m.de_mim ? 'self-end' : 'self-start'}`}
               style={{ background: m.de_mim ? 'var(--wa-out)' : 'var(--wa-in)', color: m.de_mim ? 'var(--wa-out-ink)' : 'var(--wa-in-ink)' }}>
            {!m.de_mim && (
              <p className="text-[12.5px] font-semibold" style={{ color: 'var(--wa-green)' }}>
                {m.remetente_nome || (m.remetente ? fone(m.remetente) : 'alguém')}
              </p>
            )}
            {m.tipo !== 'texto' && (
              m.midia_url
                ? <a href={m.midia_url} target="_blank" rel="noreferrer" className="underline text-[13px]">{ICONE_TIPO[m.tipo] || 'Mídia'}</a>
                : <p className="text-[13px] opacity-80">{ICONE_TIPO[m.tipo] || 'Mídia'}</p>
            )}
            {m.texto && <p className="whitespace-pre-wrap break-words"><TextoComLinks texto={m.texto} /></p>}
            <p className="text-[11px] text-right opacity-70">{hora(m.quando)}</p>
          </div>
        ))}
      </div>
      <div className="flex items-end gap-2 px-3 py-2" style={{ background: 'var(--wa-panel)', borderTop: '1px solid var(--wa-divider)' }}>
        {bloqueado ? (
          <p className="flex-1 text-[13px] py-2 text-center" style={{ color: 'var(--wa-text-2)' }}>
            Só os admins mandam mensagem neste grupo, e o número da Parceria não é admin.
          </p>
        ) : (
          <>
            <textarea value={texto} onChange={(e) => setTexto(e.target.value)} rows={1} maxLength={4000}
                      onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); mandar() } }}
                      placeholder="Mensagem para o grupo" aria-label="Mensagem para o grupo"
                      className="flex-1 resize-none rounded-lg px-3 py-2 text-[15px] outline-none max-h-40"
                      style={{ background: 'var(--wa-input)', color: 'var(--wa-text)' }} />
            <button type="button" onClick={mandar} disabled={!texto.trim() || enviando} className="wa-icone-btn disabled:opacity-40" aria-label="Mandar">
              {enviando ? <CircleNotch size={22} className="animate-spin" /> : <PaperPlaneRight size={22} weight="fill" />}
            </button>
          </>
        )}
      </div>
    </>
  )
}

/* ── Participantes ── */
function AbaParticipantes({ grupo, ocupado, editar }: {
  grupo: DadosDoGrupo; ocupado: boolean; editar: (c: Record<string, unknown>, p?: string) => void
}) {
  const [q, setQ] = useState('')
  const [novo, setNovo] = useState('')
  const lista = useMemo(() => {
    const s = sem(q.trim()), d = q.replace(/\D/g, '')
    return grupo.participantes.filter((p) => !s || sem(p.nome || '').includes(s) || (d.length >= 3 && p.telefone.includes(d)))
  }, [grupo.participantes, q])
  const quem = (p: Participante) => p.nome ? `${p.nome} (${fone(p.telefone)})` : fone(p.telefone)
  const admins = grupo.participantes.filter((p) => p.admin).length
  const corretores = grupo.participantes.filter((p) => p.corretor).length

  return (
    <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem">
      <div className="px-4 pt-3 pb-2 sticky top-0 z-10" style={{ background: 'var(--wa-conv-bg)' }}>
        <p className="text-[12.5px] mb-2" style={{ color: 'var(--wa-text-2)' }}>
          {grupo.participantes.length} pessoas · {admins} admin{admins === 1 ? '' : 's'} · {corretores} corretor{corretores === 1 ? '' : 'es'} cadastrado{corretores === 1 ? '' : 's'}.
          A Z-API não dá o nome: o nome aqui é o que a casa já conhece.
        </p>
        <label className="wa-busca"><MagnifyingGlass size={18} />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Procurar por nome ou número" aria-label="Procurar participante" />
        </label>
        {grupo.souAdmin && (
          <div className="flex gap-2 mt-2">
            <input value={novo} onChange={(e) => setNovo(e.target.value)} inputMode="tel" placeholder="Adicionar: telefone com DDD"
                   className="flex-1 rounded-lg px-3 py-1.5 text-[14px] outline-none" style={{ background: 'var(--wa-input)', color: 'var(--wa-text)' }} />
            <button type="button" disabled={ocupado || novo.replace(/\D/g, '').length < 10} className="wa-chip inline-flex items-center gap-1 disabled:opacity-40"
                    onClick={() => { const t = novo.replace(/\D/g, ''); editar({ acao: 'adicionar', telefones: [t.startsWith('55') ? t : '55' + t] }, `Adicionar ${fone(t)} ao grupo "${grupo.nome}"?`); setNovo('') }}>
              <UserPlus size={15} />Adicionar
            </button>
          </div>
        )}
      </div>
      <ul className="px-2 pb-4">
        {lista.map((p) => (
          <li key={p.telefone || p.lid || Math.random()} className="flex items-center gap-3 px-2 py-2 rounded-lg hover:brightness-95" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
            <div className="flex-1 min-w-0">
              <p className="truncate text-[14.5px]" style={{ color: 'var(--wa-text)' }}>{p.nome || <span style={{ color: 'var(--wa-text-2)' }}>sem nome conhecido</span>}</p>
              <p className="text-[12.5px] flex items-center gap-1.5 flex-wrap" style={{ color: 'var(--wa-text-2)' }}>
                {p.telefone ? fone(p.telefone) : 'número escondido (@lid)'}
                {p.admin && <Selo cor="#16a34a"><Crown size={11} weight="fill" />{p.dono ? 'dono' : 'admin'}</Selo>}
                {p.corretor && <Selo cor="#0284c7">corretor</Selo>}
                {!p.corretor && p.falouComANay && <Selo cor="#64748b">já falou com a Nay</Selo>}
              </p>
            </div>
            {grupo.souAdmin && p.telefone && !p.dono && (
              <div className="flex gap-1 flex-shrink-0">
                <button type="button" disabled={ocupado} className="wa-chip text-[12px] disabled:opacity-40"
                        onClick={() => editar({ acao: p.admin ? 'rebaixar' : 'promover', telefones: [p.telefone] },
                                              p.admin ? `Tirar o admin de ${quem(p)}?` : `Tornar ${quem(p)} admin do grupo?`)}>
                  {p.admin ? 'Tirar admin' : 'Tornar admin'}
                </button>
                <button type="button" disabled={ocupado} className="wa-chip text-[12px] inline-flex items-center gap-1 disabled:opacity-40" style={{ color: '#dc2626' }}
                        onClick={() => editar({ acao: 'remover', telefones: [p.telefone] }, `Remover ${quem(p)} do grupo "${grupo.nome}"?`)}>
                  <UserMinus size={14} />Remover
                </button>
              </div>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}

/* ── Configurações ── */
function AbaConfig({ grupo, ocupado, editar }: {
  grupo: DadosDoGrupo; ocupado: boolean; editar: (c: Record<string, unknown>, p?: string) => void
}) {
  const [nome, setNome] = useState(grupo.nome)
  const [desc, setDesc] = useState(grupo.descricao || '')
  useEffect(() => { setNome(grupo.nome); setDesc(grupo.descricao || '') }, [grupo.nome, grupo.descricao])
  const pode = grupo.souAdmin && !ocupado
  const opcoes: [keyof DadosDoGrupo['config'], string][] = [
    ['soAdminMandaMensagem', 'Só admins mandam mensagem'],
    ['soAdminEdita', 'Só admins mudam nome, foto e descrição'],
    ['soAdminAdiciona', 'Só admins adicionam participantes'],
    ['aprovacaoParaEntrar', 'Entrar pelo link precisa da aprovação de um admin'],
  ]
  const campo = { background: 'var(--wa-input)', color: 'var(--wa-text)' }
  return (
    <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-4 flex flex-col gap-4 max-w-2xl">
      {!grupo.souAdmin && (
        <p className="text-[13.5px] rounded-lg px-3 py-2" style={{ background: '#FEF3C7', color: '#78350F' }}>
          O número da Parceria não é admin deste grupo: dá para ver, mas não para mudar. Quem muda é um admin do grupo
          (ou alguém promove o número da Parceria a admin).
        </p>
      )}
      <div>
        <label className="text-[12.5px] font-semibold" style={{ color: 'var(--wa-text-2)' }}>Nome do grupo</label>
        <div className="flex gap-2 mt-1">
          <input value={nome} onChange={(e) => setNome(e.target.value)} disabled={!grupo.souAdmin} maxLength={100}
                 className="flex-1 rounded-lg px-3 py-2 text-[15px] outline-none disabled:opacity-70" style={campo} />
          {grupo.souAdmin && (
            <button type="button" className="wa-chip disabled:opacity-40" disabled={!pode || !nome.trim() || nome.trim() === grupo.nome}
                    onClick={() => editar({ acao: 'nome', nome: nome.trim() }, `Mudar o nome do grupo para "${nome.trim()}"? Todos os participantes veem o aviso.`)}>Salvar</button>
          )}
        </div>
      </div>
      <div>
        <label className="text-[12.5px] font-semibold" style={{ color: 'var(--wa-text-2)' }}>Descrição</label>
        <textarea value={desc} onChange={(e) => setDesc(e.target.value)} disabled={!grupo.souAdmin} rows={6} maxLength={2048}
                  className="w-full mt-1 rounded-lg px-3 py-2 text-[14px] outline-none disabled:opacity-70" style={campo} />
        {grupo.souAdmin && (
          <button type="button" className="wa-chip mt-1 disabled:opacity-40" disabled={!pode || desc === (grupo.descricao || '')}
                  onClick={() => editar({ acao: 'descricao', descricao: desc }, 'Salvar a descrição nova do grupo? Todos os participantes veem o aviso.')}>Salvar descrição</button>
        )}
      </div>
      <div>
        <p className="text-[12.5px] font-semibold mb-1" style={{ color: 'var(--wa-text-2)' }}>Quem pode o quê</p>
        {opcoes.map(([k, r]) => (
          <label key={k} className="flex items-center gap-2 py-1.5 text-[14px]" style={{ color: 'var(--wa-text)' }}>
            <input type="checkbox" checked={grupo.config[k]} disabled={!pode}
                   onChange={(e) => editar({ acao: 'config', [k]: e.target.checked }, `${e.target.checked ? 'Ligar' : 'Desligar'}: "${r}"?`)} />
            {r}
          </label>
        ))}
      </div>
      <div className="text-[13px] flex flex-col gap-1" style={{ color: 'var(--wa-text-2)' }}>
        {grupo.criadoEm && <span>Criado em {new Date(grupo.criadoEm).toLocaleDateString('pt-BR')}</span>}
        {grupo.dono && <span>Dono: {fone(grupo.dono)}</span>}
        {grupo.linkDeConvite ? (
          <span className="flex items-center gap-2">Link de convite: <a href={grupo.linkDeConvite} target="_blank" rel="noreferrer" className="underline truncate">{grupo.linkDeConvite}</a>
            <button type="button" className="wa-icone-btn" title="Copiar" onClick={() => navigator.clipboard?.writeText(grupo.linkDeConvite || '')}><Copy size={16} /></button>
          </span>
        ) : <span>Link de convite: só um admin consegue ver.</span>}
        {grupo.casa.disparo && <span>O publicador manda imóvel neste grupo{grupo.casa.limite_dia ? ` (até ${grupo.casa.limite_dia} por dia)` : ''}.</span>}
        {grupo.casa.corretores && <span>Os membros deste grupo viram corretores que a Nay atende.</span>}
      </div>
    </div>
  )
}
