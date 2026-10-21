'use client'

/**
 * A ABA CHAT CHAVES NA MÃO (Pedro, 21/10/2026): "vai ter uma outra aba lá no menu, no lugar de visitantes ... Chat
 * Chaves na Mão igual o olx mesmas coisas".
 *
 * A mesma tela do Chat OLX (ChatOlxContas.tsx, estilos .olx-* do globals.css): em cima, Chat / Anúncios /
 * Informações. A diferença é de onde vem a conversa: o Chaves na Mão NÃO tem chat. O que chega é o lead que ele manda
 * por POST (nay-site-api /api/chavesnamao/leads, migração 458), com a mensagem que a pessoa escreveu no anúncio. Os
 * leads da mesma pessoa (telefone, ou e-mail) são uma conversa; cada lead é um balão. A RESPOSTA sai pelo WhatsApp
 * Leads: o botão abre (ou cria) a conversa daquele telefone lá, pelo mesmo caminho da lupa (/api/leads/abrir).
 *
 * Anúncios = o que está no XML que o portal lê (uma vez por dia) e o que ficou de fora, com o motivo; Informações =
 * os dois endereços da integração e o estado dos leads (459: crm_cnm_chats, crm_cnm_conversa, crm_cnm_ler,
 * crm_cnm_painel).
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import {
  ArrowClockwise, ArrowLeft, ArrowSquareOut, ChatsCircle, CheckCircle, CircleNotch, Copy, DotsThreeVertical, EnvelopeSimple, House, Info,
  MagnifyingGlass, Megaphone, Phone, WarningCircle, WhatsappLogo, X,
} from '@phosphor-icons/react'
import type { AnuncioNoXml, ChatCnmNaLista, LeadCnm, PainelCnm } from '@/lib/chavesNaMaoTipos'

type Secao = 'chat' | 'anuncios' | 'info'
type Filtro = 'todas' | 'naoLidas' | 'venda' | 'locacao'

const FUSO = 'America/Manaus'
const MESES = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro']
const sem = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
const diaDe = (iso: string) => new Date(iso).toLocaleDateString('en-CA', { timeZone: FUSO })
const horaDe = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { timeZone: FUSO, hour: '2-digit', minute: '2-digit' })
const ontemEmManaus = () => diaDe(new Date(Date.now() - 864e5).toISOString())
const quandoInteiro = (iso: string) =>
  new Date(iso).toLocaleString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
const dinheiro = (v: number | null | undefined) => (v == null ? '' : `R$ ${Number(v).toLocaleString('pt-BR')}`)
function rotuloDoDia(iso: string) {
  const d = diaDe(iso)
  const [a, m, dd] = d.split('-').map(Number)
  const data = `${dd} de ${MESES[m - 1]} de ${a}`
  return d === diaDe(new Date().toISOString()) ? `Hoje, ${data}` : d === ontemEmManaus() ? `Ontem, ${data}` : data
}
function quandoNaLista(iso: string | null) {
  if (!iso) return ''
  const d = diaDe(iso)
  if (d === diaDe(new Date().toISOString())) return horaDe(iso)
  if (d === ontemEmManaus()) return 'Ontem'
  return new Date(iso).toLocaleDateString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit' })
}
const nomeDe = (c: { nome: string | null }) => c.nome || 'Sem nome'
const inicialDe = (c: { nome: string | null }) => ((c.nome || '').match(/\p{L}/u)?.[0] || '?').toUpperCase()
function primeiroNome(c: { nome: string | null }) {
  const p = (c.nome || '').trim().split(/\s+/)[0] || ''
  return p ? p.charAt(0).toUpperCase() + p.slice(1).toLowerCase() : 'cliente'
}
const tituloDe = (a: ChatCnmNaLista['anuncio']) =>
  a.titulo || (a.condominio ? `${a.condominio}${a.bairro ? `, ${a.bairro}` : ''}` : a.codigo ? `Imóvel ${a.codigo}` : 'Anúncio no Chaves na Mão')
const telefoneBonito = (t: string | null) => {
  const d = (t || '').replace(/\D/g, '').replace(/^55(?=\d{10,11}$)/, '')
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : t || ''
}

async function pedir<T>(url: string, init?: RequestInit): Promise<T> {
  const r = await fetch(url, init)
  const j = await r.json().catch(() => ({}))
  if (!r.ok) throw new Error(j?.error || j?.erro || `Erro ${r.status}`)
  return j as T
}

/** a capa do imóvel com a inicial de quem pediu no canto (como a lista do Chat OLX) */
function Capa({ c, tamanho }: { c: ChatCnmNaLista; tamanho: 'p' | 'm' }) {
  const [falhou, setFalhou] = useState(false)
  const foto = c.anuncio.foto
  return (
    <span className={`olx-capa ${tamanho === 'm' ? 'olx-capa--m' : ''}`}>
      <span className="olx-capa__foto">
        {foto && !falhou ? <img src={foto} alt="" loading="lazy" onError={() => setFalhou(true)} /> : <House size={tamanho === 'm' ? 20 : 24} />}
      </span>
      <span className={`olx-inicial ${tamanho === 'm' ? 'olx-inicial--m' : 'olx-inicial--p'}`}>{inicialDe(c)}</span>
    </span>
  )
}

/* ── o chat: os leads como conversas ── */
function ChatDosLeads({ busca, aoBuscar, aoContar }: { busca: string; aoBuscar: (t: string) => void; aoContar: (n: number) => void }) {
  const [chats, setChats] = useState<ChatCnmNaLista[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [filtro, setFiltro] = useState<Filtro>('todas')
  const [selChave, setSelChave] = useState<string | null>(null)
  const [msgs, setMsgs] = useState<LeadCnm[] | null>(null)
  const [aviso, setAviso] = useState<{ texto: string; erro?: boolean } | null>(null)
  const [abrindo, setAbrindo] = useState(false)
  const [menuAberto, setMenuAberto] = useState(false)
  const [copiado, setCopiado] = useState<string | null>(null)
  const fim = useRef<HTMLDivElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  const carregar = useCallback(() => {
    pedir<{ chats: ChatCnmNaLista[] }>('/api/chavesnamao/chat')
      .then((d) => { setChats(d.chats); setErro(null) })
      .catch((e) => setErro(e.message))
  }, [])
  useEffect(() => { carregar(); const t = setInterval(carregar, 20_000); return () => clearInterval(t) }, [carregar])
  useEffect(() => { aoContar((chats || []).reduce((n, c) => n + c.naoLidas, 0)) }, [chats, aoContar])

  useEffect(() => {
    setMsgs(null); setAviso(null); setMenuAberto(false); setCopiado(null)
    if (!selChave) return
    const ch = encodeURIComponent(selChave)
    pedir<{ mensagens: LeadCnm[] }>(`/api/chavesnamao/chat/${ch}`)
      .then((d) => setMsgs(d.mensagens))
      .catch((e) => setAviso({ texto: e.message, erro: true }))
    // abriu = leu: some o pontinho da lista
    pedir(`/api/chavesnamao/chat/${ch}`, { method: 'POST' }).then(carregar).catch(() => { /* fica não lida; tenta na próxima */ })
  }, [selChave, carregar])
  const quantas = msgs?.length ?? 0
  useEffect(() => { fim.current?.scrollIntoView({ block: 'end' }) }, [quantas, selChave])
  useEffect(() => {
    if (!menuAberto) return
    const fora = (e: MouseEvent) => { if (!menuRef.current?.contains(e.target as Node)) setMenuAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [menuAberto])

  const filtrados = useMemo(() => {
    const q = sem(busca.trim())
    return (chats || [])
      .filter((c) => filtro !== 'naoLidas' || c.naoLidas > 0)
      .filter((c) => filtro !== 'venda' || /venda/i.test(c.anuncio.negocio || ''))
      .filter((c) => filtro !== 'locacao' || /loca/i.test(c.anuncio.negocio || ''))
      .filter((c) => !q || sem([c.nome, c.email, c.telefone, c.ultimaTexto, c.anuncio.titulo, c.anuncio.condominio, c.anuncio.bairro,
        c.anuncio.codigo ? String(c.anuncio.codigo) : null].filter(Boolean).join(' ')).includes(q))
  }, [chats, busca, filtro])
  const sel = useMemo(() => (chats || []).find((c) => c.chave === selChave) || null, [chats, selChave])

  async function responderNoWhatsApp() {
    if (!sel?.telefone || abrindo) return
    setAbrindo(true); setAviso(null)
    try {
      const j = await pedir<{ id: string }>('/api/leads/abrir', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ telefone: sel.telefone, linha: 'captacao', nome: sel.nome || '' }),
      })
      window.location.href = `/chat/captacao?leadId=${j.id}`
    } catch (e: any) {
      setAviso({ texto: e.message, erro: true })
      setAbrindo(false)
    }
  }
  async function copiar(valor: string, qual: string) {
    try { await navigator.clipboard.writeText(valor); setCopiado(qual) } catch { setCopiado(null) }
  }

  const faixaDeAviso = aviso && (
    <div className={`olx-aviso ${aviso.erro ? 'olx-aviso--erro' : 'olx-aviso--ok'}`}>
      <span className="flex-1">{aviso.texto}</span><button type="button" onClick={() => setAviso(null)} aria-label="Fechar"><X size={14} /></button>
    </div>
  )

  const q = busca.trim()
  const vazio = !chats ? null
    : q ? <>Nenhum lead com &quot;{q}&quot;.</>
    : filtro !== 'todas' && chats.length ? 'Nenhum lead neste filtro.'
    : 'Nenhum lead chegou ainda. Quando alguém pedir contato num anúncio nosso no Chaves na Mão, a conversa aparece aqui.'

  const lista = (
    <aside className={`olx-lado ${selChave ? 'hidden md:flex' : 'flex'}`}>
      <div className="olx-lado__topo">
        <h1 className="olx-titulo">Chat</h1>
        <label className="olx-busca"><MagnifyingGlass size={20} />
          <input value={busca} onChange={(e) => aoBuscar(e.target.value)} placeholder="Busque por imóvel, código ou pessoa..." aria-label="Busque por imóvel, código ou pessoa"
                 className="bg-transparent" />
          {busca && <button type="button" onClick={() => aoBuscar('')} aria-label="Limpar"><X size={16} /></button>}
        </label>
        <div className="olx-filtros" role="group" aria-label="Filtrar leads">
          {([['todas', 'Todas'], ['naoLidas', 'Não lidas'], ['venda', 'Venda'], ['locacao', 'Locação']] as [Filtro, string][]).map(([f, r]) => (
            <button key={f} type="button" onClick={() => setFiltro(f)} aria-pressed={filtro === f} className={`olx-chip ${filtro === f ? 'olx-chip--on' : ''}`}>{r}</button>
          ))}
        </div>
      </div>
      <div className="olx-lista">
        {!chats && !erro && (
          <p className="olx-vazio flex items-center justify-center gap-2"><CircleNotch size={18} className="animate-spin" /> Lendo os leads…</p>
        )}
        {erro && <p className="olx-vazio text-red-500">{erro}</p>}
        {filtrados.map((c) => (
          <button key={c.chave} type="button" onClick={() => setSelChave(c.chave)}
                  className={`olx-linha ${selChave === c.chave ? 'olx-linha--sel' : ''} ${c.naoLidas ? 'olx-linha--nova' : ''}`}>
            {c.naoLidas > 0 && <span className="olx-linha__ponto" aria-label={`${c.naoLidas} não lido${c.naoLidas === 1 ? '' : 's'}`} />}
            <Capa key={c.anuncio.foto || c.chave} c={c} tamanho="p" />
            <span className="olx-linha__texto">
              <span className="olx-linha__anuncio">{tituloDe(c.anuncio)}</span>
              <span className="olx-linha__nome">{nomeDe(c)}{c.leads > 1 ? ` · ${c.leads} pedidos` : ''}</span>
              <span className="olx-linha__ultima">
                <span>{c.ultimaTexto || '—'}</span>
                <span className="olx-linha__hora">{quandoNaLista(c.ultimaEm)}</span>
              </span>
            </span>
          </button>
        ))}
        {chats && !filtrados.length && vazio && <p className="olx-vazio">{vazio}</p>}
      </div>
    </aside>
  )

  const itens: React.ReactNode[] = []
  if (sel && msgs) {
    let diaAnterior = ''
    let anuncioAnterior = ''
    for (const m of msgs) {
      const dia = diaDe(m.quando)
      if (dia !== diaAnterior) { itens.push(<p key={`d${m.id}`} className="olx-dia">{rotuloDoDia(m.quando)}</p>); diaAnterior = dia; anuncioAnterior = '' }
      // o anúncio de cada pedido, quando muda (a mesma pessoa pode pedir de vários imóveis)
      const an = m.anuncio
      const chaveDoAnuncio = `${an.codigo ?? ''}|${an.titulo ?? ''}`
      if (chaveDoAnuncio !== anuncioAnterior) {
        itens.push(
          <p key={`a${m.id}`} className="olx-sistema">
            {[m.tipo || 'Pediu contato', an.codigo ? `imóvel ${an.codigo}` : an.titulo, an.negocio, dinheiro(an.preco)].filter(Boolean).join(' · ')}
          </p>,
        )
        anuncioAnterior = chaveDoAnuncio
      }
      itens.push(
        <p key={`q${m.id}`} className="olx-quem"><b>{primeiroNome(sel)}</b><span>{horaDe(m.quando)}</span>{!m.autenticado && <span title="Chegou antes de guardarmos a senha dos leads">teste</span>}</p>,
      )
      itens.push(
        <div key={m.id} className="olx-balao olx-balao--dele" title={quandoInteiro(m.quando)}>
          {m.texto || <i>{m.tipo ? `${m.tipo}, sem mensagem` : 'Pediu contato, sem mensagem'}</i>}
        </div>,
      )
    }
  }

  const anuncioUrl = sel?.anuncio.url || null
  const conversa = !sel ? (
    <section className="olx-conversa hidden md:flex items-center justify-center text-center px-8">
      <ChatsCircle size={56} style={{ color: 'var(--olx-roxo)' }} />
      <p className="text-[18px] font-bold mt-3">Selecione um lead</p>
      <p className="text-[14px] mt-1 max-w-md" style={{ color: 'var(--olx-texto-2)' }}>
        O Chaves na Mão não tem chat: a resposta vai pelo WhatsApp Leads. O botão embaixo da conversa abre o WhatsApp da pessoa.
      </p>
    </section>
  ) : (
    <section className="olx-conversa flex">
      <header className="olx-conv__topo">
        <span className="md:hidden -ml-2">
          <button type="button" className="olx-icone" onClick={() => setSelChave(null)} aria-label="Voltar"><ArrowLeft size={22} /></button>
        </span>
        {anuncioUrl
          ? <a href={anuncioUrl} target="_blank" rel="noopener noreferrer" title="Abrir o anúncio no Chaves na Mão"><Capa key={sel.anuncio.foto || sel.chave} c={sel} tamanho="m" /></a>
          : <Capa key={sel.anuncio.foto || sel.chave} c={sel} tamanho="m" />}
        <div className="flex-1 min-w-0">
          <p className="olx-conv__anuncio">
            {anuncioUrl
              ? <a href={anuncioUrl} target="_blank" rel="noopener noreferrer" title="Abrir o anúncio no Chaves na Mão">{tituloDe(sel.anuncio)}</a>
              : <span className="truncate">{tituloDe(sel.anuncio)}</span>}
            {sel.anuncio.preco != null && <><span className="olx-conv__sep">|</span><span className="olx-conv__preco">{dinheiro(sel.anuncio.preco)}</span></>}
          </p>
          <p className="olx-conv__nome">{nomeDe(sel)}</p>
        </div>
        {sel.anuncio.codigo && (
          <a href={`/${sel.anuncio.codigo}`} target="_blank" rel="noopener noreferrer" className="olx-conv__imovel" title="Abrir o imóvel no CRM">
            <span className="olx-conv__cod">Cód. {sel.anuncio.codigo}</span>
            {(sel.anuncio.condominio || sel.anuncio.bairro) && (
              <span className="olx-conv__condo">{[sel.anuncio.condominio, sel.anuncio.bairro].filter(Boolean).join(' · ')}</span>
            )}
          </a>
        )}
        <div className="relative" ref={menuRef}>
          <button type="button" className="olx-icone" onClick={() => setMenuAberto((v) => !v)} aria-label="Mais opções" aria-expanded={menuAberto}>
            <DotsThreeVertical size={24} weight="bold" />
          </button>
          {menuAberto && (
            <div className="olx-menu" role="menu">
              {anuncioUrl && <a href={anuncioUrl} target="_blank" rel="noopener noreferrer" role="menuitem"><ArrowSquareOut size={18} /> Ver o anúncio no Chaves na Mão</a>}
              {sel.anuncio.codigo && (
                <a href={`/${sel.anuncio.codigo}`} target="_blank" rel="noopener noreferrer" role="menuitem"><House size={18} /> Abrir o imóvel #{sel.anuncio.codigo}</a>
              )}
              {sel.telefone && (
                <button type="button" role="menuitem" onClick={() => void copiar(sel.telefone!, 'telefone')}>
                  <Phone size={18} /> {copiado === 'telefone' ? 'Telefone copiado' : `Copiar o telefone (${telefoneBonito(sel.telefone)})`}
                </button>
              )}
              {sel.email && (
                <button type="button" role="menuitem" onClick={() => void copiar(sel.email!, 'email')}>
                  <EnvelopeSimple size={18} /> {copiado === 'email' ? 'E-mail copiado' : 'Copiar o e-mail'}
                </button>
              )}
            </div>
          )}
        </div>
      </header>
      {faixaDeAviso}
      <div className="olx-conv__rolagem">
        <div className="olx-perfil">
          <span className="olx-inicial olx-inicial--g">{inicialDe(sel)}</span>
          <p className="olx-perfil__nome">{nomeDe(sel)}</p>
          <p className="olx-perfil__info">{[telefoneBonito(sel.telefone), sel.email].filter(Boolean).join(' · ') || 'sem telefone nem e-mail'}</p>
          <p className="olx-perfil__info">
            <b>{sel.leads}</b> pedido{sel.leads === 1 ? '' : 's'} de contato desde {new Date(sel.criadoEm).toLocaleDateString('pt-BR', { timeZone: FUSO, day: '2-digit', month: '2-digit' })}
          </p>
        </div>
        {msgs === null && <p className="olx-sistema">carregando…</p>}
        {itens}
        <div ref={fim} />
      </div>
      <footer className="olx-conv__rodape">
        <div className="flex flex-wrap items-center gap-2 px-3 py-2">
          {sel.telefone ? (
            <button type="button" className="olx-chip olx-chip--on inline-flex items-center gap-1.5" onClick={() => void responderNoWhatsApp()} disabled={abrindo}>
              {abrindo ? <CircleNotch size={17} className="animate-spin" /> : <WhatsappLogo size={17} />} Responder {primeiroNome(sel)} no WhatsApp Leads
            </button>
          ) : (
            <span className="text-[13px]" style={{ color: 'var(--olx-texto-2)' }}>Este lead veio sem telefone.</span>
          )}
          {sel.email && (
            <a href={`mailto:${sel.email}`} className="olx-chip inline-flex items-center gap-1.5"><EnvelopeSimple size={17} /> E-mail</a>
          )}
          <span className="text-[12px] ml-auto" style={{ color: 'var(--olx-texto-2)' }}>O Chaves na Mão não tem chat: a resposta vai pelo WhatsApp.</span>
        </div>
      </footer>
    </section>
  )

  return (
    <div className="flex-1 min-h-0 flex flex-col">
      {!sel && faixaDeAviso}
      <div className="flex flex-1 min-h-0">
        {lista}
        {conversa}
      </div>
    </div>
  )
}

/* ── Anúncios: o que está no XML e o que ficou de fora ── */
function AnunciosNoXml({ aoVerLeads }: { aoVerLeads: (codigo: number) => void }) {
  const [d, setD] = useState<PainelCnm | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [deFora, setDeFora] = useState(false)
  const carregar = useCallback(() => {
    setErro(null)
    pedir<PainelCnm>('/api/chavesnamao/painel').then(setD).catch((e) => setErro(e.message))
  }, [])
  useEffect(() => { carregar() }, [carregar])
  const lista = useMemo(() => {
    const q = sem(busca.trim())
    return (d?.anuncios || [])
      .filter((a) => a.ok !== deFora)
      .filter((a) => !q || sem([String(a.codigo), a.titulo, a.tipo, ...(a.falta || [])].filter(Boolean).join(' ')).includes(q))
  }, [d, busca, deFora])

  const cartao = (a: AnuncioNoXml) => (
    <div key={a.codigo} className="rounded-xl p-3 flex gap-3" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
      <span className="w-[72px] h-[72px] rounded-lg overflow-hidden flex-shrink-0 grid place-items-center" style={{ background: 'var(--wa-conv-bg)' }}>
        {a.foto ? <img src={a.foto} alt="" loading="lazy" className="w-full h-full object-cover" /> : <House size={26} style={{ color: 'var(--wa-icon)' }} />}
      </span>
      <div className="flex-1 min-w-0 flex flex-col gap-1">
        <p className="text-[14px] font-semibold break-words" style={{ color: 'var(--wa-text)' }}>{a.titulo || `Imóvel ${a.codigo}`}</p>
        <p className="text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
          {[`Cód. ${a.codigo}`, a.tipo, a.valor != null ? dinheiro(a.valor) : null, a.valorLocacao != null ? `aluguel ${dinheiro(a.valorLocacao)}` : null,
            a.ok ? `${a.fotos} foto${a.fotos === 1 ? '' : 's'}` : null].filter(Boolean).join(' · ')}
        </p>
        {!a.ok && (
          <p className="text-[12.5px] flex items-start gap-1" style={{ color: '#B45309' }}>
            <WarningCircle size={15} weight="fill" className="mt-0.5 flex-shrink-0" /> Fica de fora: {(a.falta || []).join('; ')}
          </p>
        )}
        <div className="flex flex-wrap gap-1.5 mt-1">
          {a.leads > 0 && (
            <button type="button" onClick={() => aoVerLeads(a.codigo)} className="wa-chip wa-chip--on inline-flex items-center gap-1.5">
              <ChatsCircle size={15} /> {a.leads} lead{a.leads === 1 ? '' : 's'}
            </button>
          )}
          <a href={`/${a.codigo}`} target="_blank" rel="noopener noreferrer" className="wa-chip inline-flex items-center gap-1.5"><House size={15} /> Abrir o imóvel</a>
        </div>
      </div>
    </div>
  )

  return (
    <div className="flex-1 min-h-0 flex flex-col" style={{ background: 'var(--wa-conv-bg)' }}>
      <div className="px-3 py-2 flex flex-wrap items-center gap-2" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        <label className="wa-busca flex-1 min-w-[220px] max-w-[420px]"><MagnifyingGlass size={18} />
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Procurar imóvel (código, título ou motivo)" aria-label="Procurar imóvel" />
          {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar"><X size={16} /></button>}
        </label>
        {d && (
          <>
            <button type="button" onClick={() => setDeFora(false)} className={`wa-chip ${!deFora ? 'wa-chip--on' : ''}`}>No XML ({d.vao})</button>
            <button type="button" onClick={() => setDeFora(true)} className={`wa-chip ${deFora ? 'wa-chip--on' : ''}`}>De fora ({d.ficam})</button>
          </>
        )}
        <button type="button" className="wa-icone-btn ml-auto" onClick={carregar} title="Atualizar agora"><ArrowClockwise size={20} /></button>
      </div>
      <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-3">
        <p className="text-[12.5px] mb-3" style={{ color: 'var(--wa-text-2)' }}>
          O portal lê o nosso XML uma vez por dia. Vai todo imóvel nosso Disponível e no site, com foto, bairro e tipo (a mesma regra da OLX).
          Para tirar um imóvel do Chaves na Mão, tire-o do site ou mude a situação: ele sai na leitura seguinte.
        </p>
        {!d && !erro && <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}><CircleNotch size={18} className="animate-spin" /> Lendo os imóveis…</p>}
        {erro && <p className="text-center text-[14px] mt-10 text-red-500">{erro}</p>}
        {d && !lista.length && <p className="text-center text-[14px] mt-10" style={{ color: 'var(--wa-text-2)' }}>Nenhum imóvel assim.</p>}
        <div className="grid gap-3" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(300px, 1fr))' }}>
          {lista.map(cartao)}
        </div>
      </div>
    </div>
  )
}

/* ── Informações: os endereços da integração e o estado dos leads ── */
function Informacoes() {
  const [d, setD] = useState<PainelCnm | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [copiado, setCopiado] = useState<string | null>(null)
  const carregar = useCallback(() => {
    setErro(null)
    pedir<PainelCnm>('/api/chavesnamao/painel').then(setD).catch((e) => setErro(e.message))
  }, [])
  useEffect(() => { carregar() }, [carregar])
  async function copiar(v: string) { try { await navigator.clipboard.writeText(v); setCopiado(v) } catch { setCopiado(null) } }
  const linha = (rotulo: string, valor: React.ReactNode) => (
    <div className="flex flex-wrap gap-x-3 gap-y-0.5 py-2" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
      <span className="w-[210px] flex-shrink-0 text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{rotulo}</span>
      <span className="flex-1 min-w-[200px] text-[14px] break-words" style={{ color: 'var(--wa-text)' }}>{valor}</span>
    </div>
  )
  const sim = (v: boolean, s: string, n: string) => (
    <span className="inline-flex items-center gap-1.5">
      {v ? <CheckCircle size={16} weight="fill" style={{ color: 'var(--wa-green)' }} /> : <WarningCircle size={16} weight="fill" style={{ color: '#B45309' }} />}{v ? s : n}
    </span>
  )
  const endereco = (url: string, abrir: boolean) => (
    <span className="inline-flex flex-wrap items-center gap-2">
      <code className="text-[13px]">{url}</code>
      <button type="button" className="wa-chip inline-flex items-center gap-1" onClick={() => void copiar(url)}><Copy size={14} /> {copiado === url ? 'Copiado' : 'Copiar'}</button>
      {abrir && <a href={url} target="_blank" rel="noopener noreferrer" className="wa-chip inline-flex items-center gap-1"><ArrowSquareOut size={14} /> Abrir</a>}
    </span>
  )
  return (
    <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-4 py-4" style={{ background: 'var(--wa-conv-bg)' }}>
      {!d && !erro && <p className="text-center text-[14px] mt-10 flex items-center justify-center gap-2" style={{ color: 'var(--wa-text-2)' }}><CircleNotch size={18} className="animate-spin" /> Lendo…</p>}
      {erro && <p className="text-center text-[14px] mt-10 text-red-500">{erro}</p>}
      {d && (
        <div className="max-w-[860px] mx-auto flex flex-col gap-4">
          <section className="rounded-xl px-4 py-2" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
            <h3 className="text-[15px] font-semibold py-2" style={{ color: 'var(--wa-text)' }}>Imóveis (XML que o portal lê)</h3>
            {linha('Endereço do XML', endereco(d.xml, true))}
            {linha('Imóveis no XML', `${d.vao} (ficam de fora ${d.ficam}: veja em Anúncios)`)}
            {linha('Leitura do portal', 'Uma vez por dia. O XML é feito na hora, com até 10 minutos de atraso.')}
          </section>
          <section className="rounded-xl px-4 py-2" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
            <h3 className="text-[15px] font-semibold py-2" style={{ color: 'var(--wa-text)' }}>Leads (o portal manda para nós)</h3>
            {linha('Endereço dos leads', endereco(d.leadsUrl, false))}
            {linha('Senha da conta guardada', sim(d.senhaGuardada, 'Sim: só entra lead com o e-mail e o token da Imob Easy',
              'Ainda não: entra o lead que vem do portal, marcado "teste" (falta o e-mail e o Token Integração de leads, em Meus Dados no Chaves na Mão)'))}
            {linha('Leads recebidos', `${d.leads.total} (${d.leads.pessoas} pessoa${d.leads.pessoas === 1 ? '' : 's'}, ${d.leads.naoLidos} não lido${d.leads.naoLidos === 1 ? '' : 's'})`)}
            {linha('Último lead', d.leads.ultimoEm ? quandoInteiro(d.leads.ultimoEm) : '—')}
            <div className="flex flex-wrap gap-2 py-3">
              <button type="button" onClick={carregar} className="wa-chip inline-flex items-center gap-1.5"><ArrowClockwise size={15} /> Atualizar</button>
            </div>
          </section>
          <section className="rounded-xl px-4 py-2" style={{ background: 'var(--wa-panel)', border: '1px solid var(--wa-divider)' }}>
            <h3 className="text-[15px] font-semibold py-2" style={{ color: 'var(--wa-text)' }}>Contato técnico com o portal</h3>
            {linha('Imob Easy', 'Pedro Victor · (96) 99171-2835 · pvlservicos@gmail.com')}
            {linha('Chaves na Mão', 'atendimento@chavesnamao.com.br · (41) 3092-1001')}
          </section>
        </div>
      )}
    </div>
  )
}

export default function ChatChavesNaMao() {
  const [secao, setSecao] = useState<Secao>('chat')
  const [naoLidas, setNaoLidas] = useState(0)
  const [busca, setBusca] = useState('')
  return (
    <div className="flex flex-col flex-1 min-h-0 h-full">
      <div className="olx-barra">
        <span className="olx-barra__nome">Chat Chaves na Mão</span>
        <nav className="olx-abas" role="tablist" aria-label="Menu do Chaves na Mão">
          {([['chat', 'Chat', ChatsCircle], ['anuncios', 'Anúncios', Megaphone], ['info', 'Informações', Info]] as const).map(([k, rotulo, Icone]) => (
            <button key={k} type="button" role="tab" aria-selected={secao === k} onClick={() => setSecao(k)} className={`olx-aba ${secao === k ? 'olx-aba--on' : ''}`}>
              <Icone size={17} /> {rotulo}
              {k === 'chat' && naoLidas > 0 && <span className="olx-aba__n">{naoLidas > 99 ? '99+' : naoLidas}</span>}
            </button>
          ))}
        </nav>
        <span className="ml-auto flex items-center gap-2 flex-wrap">
          <a href="https://www.chavesnamao.com.br/" target="_blank" rel="noopener noreferrer" className="olx-chip olx-chip--p"
             title="Abre o site do Chaves na Mão em outra aba"><ArrowSquareOut size={15} /> <span className="hidden sm:inline">Site do Chaves na Mão</span></a>
        </span>
      </div>
      {secao === 'chat' && <ChatDosLeads busca={busca} aoBuscar={setBusca} aoContar={setNaoLidas} />}
      {secao === 'anuncios' && <AnunciosNoXml aoVerLeads={(codigo) => { setBusca(String(codigo)); setSecao('chat') }} />}
      {secao === 'info' && <Informacoes />}
    </div>
  )
}
