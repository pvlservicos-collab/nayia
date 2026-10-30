'use client'

/**
 * BUSCA OLX MANUAL (Pedro, 29/10/2026): "uma página de busca da OLX manual ... vai ter vários imóveis em quadradinhos e lá
 * em cima vários filtros, os mesmos da /imoveis, e um filtro rápido Busca por Lead: o cara digita o nome do lead e já
 * preenche no automático baseado no nosso filtro".
 *
 * Os anúncios são os do banco de scrap da OLX (scrap_anuncio), lidos pelo banco da Nay: /api/olx/scrap (crm_olx_scrap_busca
 * e crm_olx_scrap_opcoes) e /api/olx/scrap/leads (o pedido de cada lead). Só leitura: nada daqui escreve no banco.
 * "Busca por lead" traduz o pedido do lead nos mesmos limites que a Nay usa (busca_olx_candidatos): preço de -20% a +10%
 * do teto, quartos do pedido até um a mais (um a menos se aceita), os bairros e o tipo.
 */
import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import ContactarDono from './ContactarDono'
import FilaDeEnvio, { enviarAoDono } from './FilaDeEnvio'
import type { Anuncio, LinhaDeEnvio } from './contatoDono'

type Item = {
  olx_id: number; titulo: string | null; preco: number | null; preco_texto: string | null; preco_antigo: string | null
  categoria: string | null; tipo_negocio: string | null; subtipo: string | null; quartos: number | null; banheiros: number | null
  vagas: number | null; area_m2: number | null; condominio: number | null; iptu: number | null; bairro: string | null
  anunciante: string | null; telefones: string[]; telefone_mascarado: string | null; fotos: string[] | null; n_fotos: number | null
  url: string | null; data_olx: string | null; coletado_em: string | null; lista: string | null; descricao: string | null
}
type LeadBusca = { lead: number; nome: string | null; telefone: string; estado: string; filtros: Record<string, any> }

type Filtros = {
  q: string; finalidade: '' | 'locacao' | 'venda'; tipos: string[]; subtipos: string[]; bairros: string[]
  preco_min: string; preco_max: string; area_min: string; area_max: string
  quartos: number[]; banheiros: number[]; vagas: number[]
  quem: '' | 'corretores' | 'imobiliarias'; com_telefone: boolean; dias: string
  ordem: 'recentes' | 'menor_preco' | 'maior_preco' | 'maior_area'
}
const VAZIO: Filtros = {
  q: '', finalidade: '', tipos: [], subtipos: [], bairros: [], preco_min: '', preco_max: '', area_min: '', area_max: '',
  quartos: [], banheiros: [], vagas: [], quem: '', com_telefone: false, dias: '', ordem: 'recentes',
}
const TIPOS: Array<[string, string]> = [['apartamento', 'Apartamento'], ['casa', 'Casa'], ['casa_condominio', 'Casa de condomínio']]
const SUBTIPOS: Array<[string, string]> = [['padrão', 'Padrão'], ['casa de condomínio', 'Casa de condomínio'], ['casa de vila', 'Casa de vila'],
  ['cobertura', 'Cobertura'], ['duplex ou triplex', 'Duplex ou tríplex'], ['loft', 'Loft'], ['kitnet', 'Kitnet']]
const POR_PAGINA = 24

const CAMPO = 'w-full px-3 py-2 border border-line rounded-lg text-sm text-ink bg-transparent focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent'
const ROTULO = 'block text-xs font-semibold text-muted mb-1'
const chip = (on: boolean) => `px-3 py-1.5 rounded-full border text-sm ${on ? 'bg-accent/15 border-accent text-accent font-semibold' : 'border-line text-ink'}`
const alterna = <T,>(l: T[], k: T) => (l.includes(k) ? l.filter((x) => x !== k) : [...l, k])
const numero = (t: string) => t.replace(/\./g, '').replace(',', '.').trim()
const reais = (v: number | null | undefined) => (v ? `R$ ${Math.round(Number(v)).toLocaleString('pt-BR')}` : '')

function foneBonito(t: string) {
  let d = String(t || '').replace(/\D/g, '')
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2)
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : d.length === 10 ? `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}` : t
}
function diaCurto(iso: string | null) {
  return iso ? new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Manaus' }) : ''
}

/** O pedido do lead nos filtros da tela (os mesmos limites do busca_olx_candidatos). */
function filtrosDoLead(f: Record<string, any>): Filtros {
  const fin = String(f.finalidade || '').toLowerCase()
  const tipo = String(f.tipo || '').toLowerCase()
  const teto = Number(f.teto) || 0
  const q = Number(f.quartos) || 0
  const qs = q ? [...(f.aceita_menos_quartos ? [q - 1] : []), q, q + 1].filter((n) => n >= 0) : []
  return {
    ...VAZIO,
    finalidade: fin.startsWith('loca') ? 'locacao' : fin.startsWith('vend') ? 'venda' : '',
    tipos: /condom/.test(tipo) ? ['casa_condominio'] : /casa/.test(tipo) ? ['casa'] : /apart/.test(tipo) ? ['apartamento'] : [],
    preco_max: teto ? String(Math.round(teto * 1.1)) : '', preco_min: teto ? String(Math.floor(teto * 0.8)) : '',
    quartos: qs, bairros: Array.isArray(f.bairros) && !f.qualquer_bairro ? f.bairros.map(String) : [],
  }
}
function resumoDoPedido(f: Record<string, any>) {
  return [String(f.finalidade || '').startsWith('vend') ? 'venda' : f.finalidade ? 'locação' : '', f.tipo,
    f.teto ? `até ${reais(Number(f.teto))}` : '', (f.bairros || []).join(', '), f.quartos ? `${f.quartos} quartos` : ''].filter(Boolean).join(' · ')
}
function paraEnviar(f: Filtros, pagina: number) {
  return {
    q: f.q.trim(), finalidade: f.finalidade, tipos: f.tipos, subtipos: f.subtipos, bairros: f.bairros,
    preco_min: numero(f.preco_min), preco_max: numero(f.preco_max), area_min: numero(f.area_min), area_max: numero(f.area_max),
    quartos: f.quartos, banheiros: f.banheiros, vagas: f.vagas, quem: f.quem, com_telefone: f.com_telefone ? 'true' : '',
    dias: f.dias, ordem: f.ordem, pagina, por: POR_PAGINA,
  }
}

function Bloco({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return <div><p className={ROTULO}>{titulo}</p><div className="flex flex-wrap items-center gap-1.5">{children}</div></div>
}
function Faixa({ titulo, min, max, aoMin, aoMax }: { titulo: string; min: string; max: string; aoMin: (v: string) => void; aoMax: (v: string) => void }) {
  return (
    <div><p className={ROTULO}>{titulo}</p>
      <div className="flex items-center gap-2">
        <input className={CAMPO} value={min} onChange={(e) => aoMin(e.target.value)} placeholder="Mín." inputMode="decimal" />
        <input className={CAMPO} value={max} onChange={(e) => aoMax(e.target.value)} placeholder="Máx." inputMode="decimal" />
      </div>
    </div>
  )
}
function Numeros({ titulo, valor, aoMudar }: { titulo: string; valor: number[]; aoMudar: (v: number[]) => void }) {
  return (
    <Bloco titulo={titulo}>
      {[0, 1, 2, 3, 4, 5].map((n) => (
        <button key={n} type="button" className={`${chip(valor.includes(n))} !px-3`} onClick={() => aoMudar(alterna(valor, n))}>{n === 5 ? '5+' : n}</button>
      ))}
    </Bloco>
  )
}

function Quadrado({ i, naFila, aoFila, aoContactar, aoEnviar }: {
  i: Item; naFila: boolean; aoFila: (i: Item) => void; aoContactar: (i: Item) => void; aoEnviar: (i: Item) => void
}) {
  const [foto, setFoto] = useState(0)
  const [copiado, setCopiado] = useState('')
  const fotos = (i.fotos || []).filter(Boolean)
  const fones = i.telefones || []
  const detalhes = [i.quartos != null ? `${i.quartos} qts` : '', i.banheiros != null ? `${i.banheiros} banh.` : '',
    i.vagas != null ? `${i.vagas} vaga${i.vagas === 1 ? '' : 's'}` : '', i.area_m2 ? `${Math.round(Number(i.area_m2))} m²` : ''].filter(Boolean).join(' · ')
  const aluguel = /^aluguel/i.test(i.tipo_negocio || '')
  return (
    <div className="rounded-xl border border-line bg-panel overflow-hidden flex flex-col text-sm text-ink">
      <div className="relative aspect-[4/3] bg-black/10">
        {fotos[foto] ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={fotos[foto]} alt={i.titulo || 'Imóvel'} loading="lazy" referrerPolicy="no-referrer" className="w-full h-full object-cover" />
        ) : <div className="w-full h-full flex items-center justify-center text-muted text-xs">sem foto</div>}
        {fotos.length > 1 && (
          <div className="absolute bottom-1.5 left-0 right-0 flex justify-center gap-1">
            {fotos.map((_, n) => (
              <button key={n} type="button" aria-label={`Foto ${n + 1}`} onClick={() => setFoto(n)}
                      className={`w-2 h-2 rounded-full ${n === foto ? 'bg-white' : 'bg-white/50'} border border-black/20`} />
            ))}
          </div>
        )}
        <span className="absolute top-1.5 left-1.5 text-[11px] font-semibold rounded-full px-2 py-0.5 text-white" style={{ background: aluguel ? '#2563eb' : '#16a34a' }}>
          {aluguel ? 'Aluguel' : 'Venda'}</span>
      </div>
      <div className="p-3 flex flex-col gap-1 flex-1">
        <p className="text-base font-bold">{reais(i.preco) || i.preco_texto || 'sem preço'}{aluguel && i.preco ? <span className="text-xs font-normal text-muted"> /mês</span> : null}</p>
        <p className="text-muted text-xs">{[i.bairro, i.subtipo && i.subtipo !== 'Padrão' ? i.subtipo : i.categoria === 'Casas' ? 'Casa' : 'Apartamento'].filter(Boolean).join(' · ')}</p>
        {detalhes && <p>{detalhes}</p>}
        {(i.condominio || i.iptu) ? <p className="text-xs text-muted">{[i.condominio ? `Cond. ${reais(i.condominio)}` : '', i.iptu ? `IPTU ${reais(i.iptu)}` : ''].filter(Boolean).join(' · ')}</p> : null}
        <p className="line-clamp-2 text-xs text-muted" title={i.titulo || ''}>{i.titulo}</p>
        <p className="text-xs"><span className="font-semibold">{i.anunciante || 'anunciante'}</span>
          {i.lista ? <span className="text-muted"> · {/Imobili/i.test(i.lista) ? 'imobiliária' : 'corretor'}</span> : null}</p>
        <div className="mt-auto pt-2 flex flex-col gap-1.5">
          {fones.length ? (
            <>
              {fones.slice(0, 2).map((t) => (
                <div key={t} className="flex items-center gap-1.5 flex-wrap">
                  <span className="text-xs font-semibold">{foneBonito(t)}</span>
                  <button type="button" className="btn btn-outline btn-sm"
                          onClick={() => { void navigator.clipboard?.writeText(String(t).replace(/\D/g, '')); setCopiado(t); setTimeout(() => setCopiado(''), 1500) }}>
                    {copiado === t ? 'Copiado' : 'Copiar'}</button>
                </div>
              ))}
              <button type="button" className="btn btn-outline btn-sm w-full" onClick={() => aoContactar(i)}>Contactar dono</button>
              <div className="flex gap-1.5">
                <button type="button" className="btn btn-sm flex-1 text-white" style={{ background: '#6d28d9' }} onClick={() => aoEnviar(i)}>Enviar</button>
                <button type="button" className={`btn btn-sm flex-1 ${naFila ? 'btn-outline' : 'text-white'}`} style={naFila ? undefined : { background: '#a855f7' }}
                        onClick={() => aoFila(i)}>{naFila ? 'Na fila ✓' : 'Adicionar à fila'}</button>
              </div>
            </>
          ) : <span className="text-xs text-muted">sem telefone no scrap{i.telefone_mascarado ? ` (${i.telefone_mascarado})` : ''}</span>}
          <div className="flex items-center justify-between text-[11px] text-muted">
            {i.url ? (fones.length ? <a className="underline text-ink" href={i.url} target="_blank" rel="noopener noreferrer">Ver na OLX</a>
              : <a className="rounded-md px-2.5 py-1 text-xs font-semibold text-white" style={{ background: 'linear-gradient(135deg, #ef4444, #b91c1c)' }}
                   href={i.url} target="_blank" rel="noopener noreferrer" title="Sem telefone no scrap: abra o anúncio e chame pelo chat da OLX">Tem que chamar na OLX</a>) : <span />}
            <span title="Data do anúncio na OLX · coletado no scrap">{diaCurto(i.data_olx)}{i.coletado_em ? ` · coletado ${diaCurto(i.coletado_em)}` : ''}</span>
          </div>
        </div>
      </div>
    </div>
  )
}

export default function BuscaOlxManual() {
  const [f, setF] = useState<Filtros>(VAZIO)
  const [opcoes, setOpcoes] = useState<{ total: number; ultima_coleta: string | null; bairros: Array<{ bairro: string; n: number }> } | null>(null)
  const [itens, setItens] = useState<Item[]>([])
  const [total, setTotal] = useState(0)
  const [pagina, setPagina] = useState(1)
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState('')
  const [maisFiltros, setMaisFiltros] = useState(false)
  const [bairroTxt, setBairroTxt] = useState('')
  const [leadTxt, setLeadTxt] = useState('')
  const [leads, setLeads] = useState<LeadBusca[]>([])
  const [leadAberto, setLeadAberto] = useState(false)
  const [doLead, setDoLead] = useState<LeadBusca | null>(null)
  const caixaLead = useRef<HTMLDivElement>(null)
  // 30/10 (Pedro): Contactar dono, Enviar e a fila de envio (o carrinho do lado direito)
  const [fila, setFila] = useState<Anuncio[]>([])
  const [linhaDeEnvio, setLinhaDeEnvio] = useState<LinhaDeEnvio>('captacao')
  const [contactar, setContactar] = useState<Anuncio | null>(null)
  const [aviso, setAviso] = useState('')
  useEffect(() => {
    try { const g = JSON.parse(localStorage.getItem('crm:olx:fila') || '[]'); if (Array.isArray(g)) setFila(g) } catch { /* sem fila guardada */ }
  }, [])
  const guardarFila = (l: Anuncio[]) => { setFila(l); try { localStorage.setItem('crm:olx:fila', JSON.stringify(l)) } catch { /* vale até recarregar */ } }
  const paraAnuncio = (i: Item): Anuncio => ({
    olx_id: i.olx_id, titulo: i.titulo, preco: i.preco, preco_texto: i.preco_texto, bairro: i.bairro, anunciante: i.anunciante,
    telefones: i.telefones || [], url: i.url, fotos: (i.fotos || []).slice(0, 1),
  })
  const alternarNaFila = (i: Item) => guardarFila(fila.some((a) => a.olx_id === i.olx_id) ? fila.filter((a) => a.olx_id !== i.olx_id) : [...fila, paraAnuncio(i)])
  const enviarUm = async (i: Item) => {
    const a = paraAnuncio(i)
    if (!window.confirm(`Mandar agora a pergunta da Nay a ${a.anunciante || 'este anunciante'} pelo ${linhaDeEnvio === 'captacao' ? 'WhatsApp Leads (8595)' : 'WhatsApp Parceria'}?`)) return
    setAviso(`Enviando a ${a.anunciante || 'anunciante'}…`)
    const erro = await enviarAoDono(a, linhaDeEnvio)
    setAviso(erro ? `Não saiu para ${a.anunciante || 'anunciante'}: ${erro}` : `Enviado a ${a.anunciante || 'anunciante'}.`)
    setTimeout(() => setAviso(''), 6000)
  }

  const muda = <K extends keyof Filtros>(k: K, v: Filtros[K]) => { setF((x) => ({ ...x, [k]: v })); setPagina(1) }

  useEffect(() => {
    void fetch('/api/olx/scrap').then((r) => r.json()).then((j) => setOpcoes(j)).catch(() => undefined)
  }, [])

  const chave = useMemo(() => JSON.stringify(paraEnviar(f, pagina)), [f, pagina])
  const pedido = useRef(0)
  const buscar = useCallback(async (corpo: string) => {
    const n = ++pedido.current
    setCarregando(true); setErro('')
    try {
      const r = await fetch(`/api/olx/scrap?filtros=${encodeURIComponent(corpo)}`)
      const j = await r.json().catch(() => ({}))
      if (n !== pedido.current) return
      if (!r.ok) { setErro(j.erro || j.error || 'Não consegui ler os anúncios.'); setItens([]); setTotal(0); return }
      setItens(j.itens || []); setTotal(Number(j.total) || 0)
    } catch { if (n === pedido.current) setErro('Não consegui ler os anúncios.') }
    finally { if (n === pedido.current) setCarregando(false) }
  }, [])
  useEffect(() => {
    const t = setTimeout(() => void buscar(chave), 350)   // espera 350 ms entre as mudanças dos filtros
    return () => clearTimeout(t)
  }, [chave, buscar])

  // Busca por lead: a lista desce enquanto digita
  useEffect(() => {
    const q = leadTxt.trim()
    if (q.length < 2) { setLeads([]); return }
    const t = setTimeout(async () => {
      try {
        const r = await fetch(`/api/olx/scrap/leads?q=${encodeURIComponent(q)}`)
        const j = await r.json().catch(() => ({}))
        setLeads(r.ok ? (j.leads || []) : []); setLeadAberto(true)
      } catch { setLeads([]) }
    }, 300)
    return () => clearTimeout(t)
  }, [leadTxt])
  useEffect(() => {
    const fora = (e: MouseEvent) => { if (caixaLead.current && !caixaLead.current.contains(e.target as Node)) setLeadAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [])

  const usarLead = (l: LeadBusca) => {
    setDoLead(l); setLeadTxt(''); setLeadAberto(false); setPagina(1)
    setF({ ...filtrosDoLead(l.filtros || {}), ordem: 'recentes' })
  }
  const limpar = () => { setF(VAZIO); setDoLead(null); setPagina(1) }

  const bairrosSugeridos = useMemo(() => {
    const t = bairroTxt.trim().toLowerCase()
    if (!t || !opcoes) return []
    return opcoes.bairros.filter((b) => b.bairro.toLowerCase().includes(t) && !f.bairros.includes(b.bairro)).slice(0, 8)
  }, [bairroTxt, opcoes, f.bairros])

  const paginas = Math.max(1, Math.ceil(total / POR_PAGINA))
  const temFiltro = JSON.stringify({ ...f, ordem: 'recentes' }) !== JSON.stringify({ ...VAZIO })

  return (
    <div>
      <p className="text-sm text-muted mb-4">
        Os anúncios da OLX que a gente já raspou{opcoes ? ` (${opcoes.total.toLocaleString('pt-BR')} imóveis, última coleta em ${diaCurto(opcoes.ultima_coleta)})` : ''}.
        Filtre à mão ou use a Busca por lead para já vir com o pedido dele.
      </p>

      <div className="rounded-xl border border-line bg-panel p-4 grid gap-4 mb-4">
        {/* BUSCA RÁPIDA (Pedro, 30/10: "coloca dentro de um card e outra cor: Busca rápida") */}
        <div ref={caixaLead} className="relative rounded-xl p-3.5 text-white"
             style={{ background: 'linear-gradient(135deg, #7c3aed, #4f46e5)', boxShadow: '0 4px 14px rgba(99, 102, 241, 0.35)' }}>
          <p className="text-sm font-bold mb-0.5">Busca rápida</p>
          <label className="block text-xs mb-1.5" style={{ color: 'rgba(255,255,255,0.85)' }}>Busca por lead — digite o nome (ou o número) e os filtros se preenchem com o pedido dele</label>
          <input className="w-full px-3 py-2 rounded-lg text-sm text-gray-900 bg-white placeholder-gray-400 focus:outline-none focus:ring-2 focus:ring-white/70"
                 value={leadTxt} onChange={(e) => setLeadTxt(e.target.value)} onFocus={() => leads.length && setLeadAberto(true)}
                 placeholder="Ex.: Ana, Alê Mendes, 92 99999…" />
          {leadAberto && leadTxt.trim().length >= 2 && (
            <div className="absolute z-20 left-3.5 right-3.5 mt-1 rounded-lg border border-line bg-panel text-ink shadow-lg max-h-72 overflow-auto">
              {!leads.length ? <p className="p-3 text-sm text-muted">Nenhum lead com pedido anotado para “{leadTxt.trim()}”.</p> : leads.map((l) => (
                <button key={l.lead} type="button" className="block w-full text-left px-3 py-2 hover:bg-accent/10 border-b border-line last:border-0" onClick={() => usarLead(l)}>
                  <span className="font-semibold">{l.nome || 'sem nome'} · {foneBonito(l.telefone)}</span>
                  <span className="block text-xs text-muted">{resumoDoPedido(l.filtros || {}) || 'pedido ainda sem dados'}</span>
                </button>
              ))}
            </div>
          )}
        </div>
        {doLead && (
          <div className="flex flex-wrap items-center gap-2 text-sm rounded-lg bg-accent/10 border border-accent/40 px-3 py-2">
            <span>Filtros do lead <b>{doLead.nome || foneBonito(doLead.telefone)}</b>: {resumoDoPedido(doLead.filtros || {}) || 'sem dados no pedido'}.</span>
            <span className="text-xs text-muted">Preço de -20% a +10% do teto e quartos do pedido até um a mais, como a Nay faz. Ajuste à vontade.</span>
            <button type="button" className="btn btn-outline btn-sm ml-auto" onClick={limpar}>Limpar</button>
          </div>
        )}

        {/* FILTROS */}
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <div><label className={ROTULO}>Procurar (título, descrição, anunciante, código da OLX)</label>
            <input className={CAMPO} value={f.q} onChange={(e) => muda('q', e.target.value)} placeholder="piscina, Monique, 1536106394…" /></div>
          <Bloco titulo="Negócio">
            {([['', 'Todos'], ['locacao', 'Aluguel'], ['venda', 'Venda']] as const).map(([k, r]) => (
              <button key={k || 'todos'} type="button" className={chip(f.finalidade === k)} onClick={() => muda('finalidade', k)}>{r}</button>
            ))}
          </Bloco>
          <Bloco titulo="Tipo">
            {TIPOS.map(([k, r]) => <button key={k} type="button" className={chip(f.tipos.includes(k))} onClick={() => muda('tipos', alterna(f.tipos, k))}>{r}</button>)}
          </Bloco>
          <div className="relative"><label className={ROTULO}>Bairro</label>
            <input className={CAMPO} value={bairroTxt} onChange={(e) => setBairroTxt(e.target.value)} placeholder="Digite e escolha: Ponta Negra, Adrianópolis…" />
            {bairrosSugeridos.length > 0 && (
              <div className="absolute z-20 left-0 right-0 mt-1 rounded-lg border border-line bg-panel shadow-lg max-h-60 overflow-auto">
                {bairrosSugeridos.map((b) => (
                  <button key={b.bairro} type="button" className="block w-full text-left px-3 py-1.5 text-sm hover:bg-accent/10"
                          onClick={() => { muda('bairros', [...f.bairros, b.bairro]); setBairroTxt('') }}>{b.bairro} <span className="text-xs text-muted">({b.n})</span></button>
                ))}
              </div>
            )}
          </div>
        </div>
        {f.bairros.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {f.bairros.map((b) => <button key={b} type="button" className={chip(true)} onClick={() => muda('bairros', f.bairros.filter((x) => x !== b))}>{b} ✕</button>)}
          </div>
        )}
        <div className="grid gap-4 sm:grid-cols-3">
          <Faixa titulo="Preço (R$)" min={f.preco_min} max={f.preco_max} aoMin={(v) => muda('preco_min', v)} aoMax={(v) => muda('preco_max', v)} />
          <Faixa titulo="Área (m²)" min={f.area_min} max={f.area_max} aoMin={(v) => muda('area_min', v)} aoMax={(v) => muda('area_max', v)} />
          <Numeros titulo="Quartos" valor={f.quartos} aoMudar={(v) => muda('quartos', v)} />
        </div>

        <button type="button" className="text-sm underline text-left w-fit" onClick={() => setMaisFiltros((x) => !x)}>{maisFiltros ? 'Menos filtros' : 'Mais filtros'}</button>
        {maisFiltros && (
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <Numeros titulo="Banheiros" valor={f.banheiros} aoMudar={(v) => muda('banheiros', v)} />
            <Numeros titulo="Vagas na garagem" valor={f.vagas} aoMudar={(v) => muda('vagas', v)} />
            <Bloco titulo="Subtipo">
              {SUBTIPOS.map(([k, r]) => <button key={k} type="button" className={chip(f.subtipos.includes(k))} onClick={() => muda('subtipos', alterna(f.subtipos, k))}>{r}</button>)}
            </Bloco>
            <Bloco titulo="Anunciante">
              {([['', 'Todos'], ['corretores', 'Corretores'], ['imobiliarias', 'Imobiliárias']] as const).map(([k, r]) => (
                <button key={k || 'todos'} type="button" className={chip(f.quem === k)} onClick={() => muda('quem', k)}>{r}</button>
              ))}
            </Bloco>
            <div><label className={ROTULO}>Coletado nos últimos (dias)</label>
              <input className={CAMPO} value={f.dias} onChange={(e) => muda('dias', e.target.value.replace(/\D/g, ''))} placeholder="Todos" inputMode="numeric" /></div>
            <label className="inline-flex items-center gap-2 text-sm text-ink self-end pb-2">
              <input type="checkbox" checked={f.com_telefone} onChange={(e) => muda('com_telefone', e.target.checked)} /> Só os que têm telefone</label>
          </div>
        )}

        <div className="flex flex-wrap items-center gap-3">
          <Bloco titulo="Ordenar por">
            {([['recentes', 'Mais recentes'], ['menor_preco', 'Menor preço'], ['maior_preco', 'Maior preço'], ['maior_area', 'Maior área']] as const).map(([k, r]) => (
              <button key={k} type="button" className={chip(f.ordem === k)} onClick={() => muda('ordem', k)}>{r}</button>
            ))}
          </Bloco>
          {temFiltro && <button type="button" className="btn btn-outline btn-sm ml-auto self-end" onClick={limpar}>Limpar filtros</button>}
        </div>
      </div>

      <div className="flex items-center justify-between mb-3 text-sm">
        <span className="text-muted">{carregando ? 'Buscando…' : `${total.toLocaleString('pt-BR')} imóvel(is)`}</span>
        <Paginacao pagina={pagina} paginas={paginas} aoIr={setPagina} />
      </div>
      {erro && <p className="text-sm mb-3" style={{ color: '#dc2626' }}>{erro}</p>}
      {!carregando && !erro && !itens.length ? (
        <p className="text-sm text-muted">Nenhum anúncio com esses filtros. Afrouxe um deles.</p>
      ) : (
        <div className={`grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 ${carregando ? 'opacity-60' : ''}`}>
          {itens.map((i) => (
            <Quadrado key={i.olx_id} i={i} naFila={fila.some((a) => a.olx_id === i.olx_id)} aoFila={alternarNaFila}
                      aoContactar={(x) => setContactar(paraAnuncio(x))} aoEnviar={(x) => void enviarUm(x)} />
          ))}
        </div>
      )}
      <div className="flex justify-end mt-4"><Paginacao pagina={pagina} paginas={paginas} aoIr={(n) => { setPagina(n); window.scrollTo({ top: 0, behavior: 'smooth' }) }} /></div>
      {aviso && <div className="fixed left-1/2 -translate-x-1/2 bottom-6 z-[90] rounded-lg bg-black/85 text-white text-sm px-4 py-2 shadow-xl">{aviso}</div>}
      {contactar && <ContactarDono anuncio={contactar} aoFechar={() => setContactar(null)} />}
      <FilaDeEnvio itens={fila} linha={linhaDeEnvio} aoMudarLinha={setLinhaDeEnvio}
                   aoTirar={(id) => guardarFila(fila.filter((a) => a.olx_id !== id))}
                   aoEnviados={(ids) => guardarFila(fila.filter((a) => !ids.includes(a.olx_id)))} />
    </div>
  )
}

function Paginacao({ pagina, paginas, aoIr }: { pagina: number; paginas: number; aoIr: (n: number) => void }) {
  if (paginas <= 1) return <span />
  return (
    <div className="flex items-center gap-2 text-sm">
      <button type="button" className="btn btn-outline btn-sm disabled:opacity-40" disabled={pagina <= 1} onClick={() => aoIr(pagina - 1)}>Anterior</button>
      <span className="text-muted">{pagina} de {paginas}</span>
      <button type="button" className="btn btn-outline btn-sm disabled:opacity-40" disabled={pagina >= paginas} onClick={() => aoIr(pagina + 1)}>Próxima</button>
    </div>
  )
}
