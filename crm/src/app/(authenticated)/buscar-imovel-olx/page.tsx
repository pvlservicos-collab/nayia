'use client'

/**
 * AS BUSCAS DOS CLIENTES (Pedro, 22/10/2026: "cada lead que chega na aba leads da OLX seja criado para ele um registro de
 * busca ... que tenha lá na lista de buscas cada pedido com uma marcação tipo uma linha a ser preenchida de até onde ele já
 * foi, e aquele buscador manual com várias opções da OLX esconde em um botão busca manual ... eu podendo acompanhar cada
 * etapa na aba buscas da OLX").
 *
 * A lista vem de crm_busca_cliente_lista (475): o perfil, a nossa base, o aviso ao cliente, os grupos de WhatsApp, os
 * anunciantes da OLX perguntados, os corretores que ofereceram e a oferta ao cliente, numa linha de 7 passos; "Ver passos"
 * abre o histórico. Quem anda é o nay-olx (olx/buscas.py). O formulário antigo (19-20/10) ficou atrás de "Busca manual" e
 * agora abre a busca do fluxo novo já ativada (475b). ?telefone=&nome= preenchem o cliente e abrem o formulário.
 */
import { Suspense, useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'next/navigation'
import BuscaOlxManual from '@/components/Olx/BuscaOlxManual'

type BuscaCliente = {
  id: number; lead: number; estado: string; motivo: string | null; teste: boolean; filtros: Record<string, any>
  nome: string | null; telefone: string; origem: string; etapa: string; codigo: number | null
  criado_em: string; atualizado_em: string; ativada_em: string | null; cliente_avisado_em: string | null
  base_em: string | null; base_qtd: number | null; grupos: Array<{ grupo: string; nome: string; em: string; teste?: boolean }>
  grupos_em: string | null; olx: Array<{ olx_id: number; titulo: string; url: string; preco: number; bairro: string; tel: string;
    anunciante: string | null; em: string; teste?: boolean }>
  olx_em: string | null; ofertas: Array<{ tel: string; nome: string | null; codigo: number; em: string; estado: string }>
  ofertado_em: string | null; passos: Array<{ em: string; lugar: string; texto: string }>
}

const ESTADO_DA_BUSCA: Record<string, { rotulo: string; cor: string }> = {
  perfil: { rotulo: 'Perfil anotado', cor: '#64748b' },
  nossa_base: { rotulo: 'Atendida pela nossa base', cor: '#16a34a' },
  buscando: { rotulo: 'Buscando fora', cor: '#2563eb' },
  ofertado: { rotulo: 'Imóvel oferecido', cor: '#16a34a' },
  pausada: { rotulo: 'Pausada', cor: '#b45309' },
  encerrada: { rotulo: 'Encerrada', cor: '#64748b' },
}
const FILTROS: Array<[string, string]> = [['ativas', 'Buscando fora'], ['todas', 'Todas'], ['ofertadas', 'Oferecidas'],
  ['base', 'Nossa base'], ['paradas', 'Pausadas e encerradas']]
function passaNoFiltro(b: BuscaCliente, f: string) {
  if (f === 'ativas') return b.estado === 'buscando'
  if (f === 'ofertadas') return b.estado === 'ofertado'
  if (f === 'base') return b.estado === 'nossa_base' || b.estado === 'perfil'
  if (f === 'paradas') return b.estado === 'pausada' || b.estado === 'encerrada'
  return true
}
function dataCurta(iso: string | undefined) {
  return iso && iso.length >= 16 ? `${iso.slice(8, 10)}/${iso.slice(5, 7)} ${iso.slice(11, 16)}` : ''
}

/* a "linha a ser preenchida": 7 passos, do perfil à oferta ao cliente */
function passosDaLinha(b: BuscaCliente) {
  const reais = (x: { teste?: boolean }) => !x.teste
  const grupos = (b.grupos || []).filter(reais), gruposTeste = (b.grupos || []).length - grupos.length
  const olx = (b.olx || []).filter(reais), olxTeste = (b.olx || []).length - olx.length
  const fora = b.estado === 'buscando' || b.estado === 'ofertado' || !!b.ativada_em
  const ofertas = b.ofertas || []
  return [
    { nome: 'Perfil', feito: Object.keys(b.filtros || {}).length > 0, info: resumo(b.filtros || {}) ? 'anotado' : 'sem dados' },
    { nome: 'Nossa base', feito: !!b.base_em, info: b.base_em ? (b.base_qtd ? `${b.base_qtd} opção(ões)` : 'nada exato') : 'ainda não' },
    { nome: 'Cliente avisado', feito: !!b.cliente_avisado_em, info: b.cliente_avisado_em ? quando(b.cliente_avisado_em) : fora ? 'ainda não' : '—' },
    { nome: 'Grupos', feito: grupos.length > 0, info: grupos.length ? `${grupos.length} grupo(s)` : gruposTeste ? `${gruposTeste} em teste` : fora ? 'na fila' : '—' },
    { nome: 'OLX', feito: olx.length > 0, info: olx.length ? `${olx.length} anunciante(s)` : olxTeste ? `${olxTeste} em teste` : b.olx_em ? 'nada na base' : fora ? 'na fila' : '—' },
    { nome: 'Corretores', feito: ofertas.length > 0, info: ofertas.length ? `${ofertas.length} imóvel(is)` : fora ? 'esperando' : '—' },
    { nome: 'Oferecido', feito: b.estado === 'ofertado', info: b.ofertado_em ? quando(b.ofertado_em) : '—' },
  ]
}

function LinhaDoProgresso({ b }: { b: BuscaCliente }) {
  const ps = passosDaLinha(b)
  const atual = ps.findIndex((p) => !p.feito)
  return (
    <div className="grid grid-cols-7 gap-1 mt-3">
      {ps.map((p, i) => {
        const cor = p.feito ? '#16a34a' : i === atual && b.estado === 'buscando' ? '#2563eb' : '#cbd5e1'
        return (
          <div key={p.nome} className="min-w-0">
            <div className="h-2 rounded-full" style={{ background: cor }} />
            <p className="text-[11px] font-semibold text-ink mt-1 truncate">{p.feito ? '✓ ' : ''}{p.nome}</p>
            <p className="text-[11px] text-muted truncate" title={p.info}>{p.info}</p>
          </div>
        )
      })}
    </div>
  )
}

function CartaoDaBusca({ b, aoAgir }: { b: BuscaCliente; aoAgir: (id: number, acao: string) => void }) {
  const [aberto, setAberto] = useState(false)
  const e = ESTADO_DA_BUSCA[b.estado] || { rotulo: b.estado, cor: '#64748b' }
  const origem = b.origem === 'olx' ? 'veio da OLX' : b.origem === 'organico' ? 'orgânico' : b.origem === 'manual' ? 'aberta pelo CRM' : b.origem
  return (
    <div className="rounded-xl border border-line bg-panel p-4 text-sm text-ink">
      <div className="flex flex-wrap items-center gap-2">
        <span className="font-semibold">{b.nome || 'sem nome'} · {fone(b.telefone)}</span>
        <span className="text-xs font-semibold rounded-full px-2 py-0.5 text-white" style={{ background: e.cor }}>{e.rotulo}</span>
        <span className="text-xs text-muted">{origem}</span>
        {b.codigo ? <span className="text-xs text-muted">anúncio do #{b.codigo}</span> : null}
        <span className="ml-auto text-xs text-muted">busca nº {b.id} · {quando(b.atualizado_em)}</span>
      </div>
      <p className="text-muted mt-1">{resumo(b.filtros || {}) || 'perfil ainda sem dados'}</p>
      <LinhaDoProgresso b={b} />
      <div className="flex flex-wrap items-center gap-2 mt-3">
        <button type="button" className="btn btn-outline btn-sm" onClick={() => setAberto((x) => !x)}>{aberto ? 'Fechar passos' : 'Ver passos'}</button>
        {b.estado !== 'buscando' && b.estado !== 'ofertado' && (
          <button type="button" className="btn btn-outline btn-sm" onClick={() => aoAgir(b.id, 'ativar')}>Ativar busca fora</button>)}
        {b.estado === 'buscando' && <button type="button" className="btn btn-outline btn-sm" onClick={() => aoAgir(b.id, 'pausar')}>Pausar</button>}
        {b.estado !== 'encerrada' && <button type="button" className="btn btn-outline btn-sm" onClick={() => aoAgir(b.id, 'encerrar')}>Encerrar</button>}
      </div>
      {aberto && (
        <div className="mt-3 grid gap-3">
          {(b.grupos || []).length > 0 && (
            <div><p className="text-xs font-semibold text-muted mb-1">Grupos</p>
              <ul className="grid gap-0.5">{b.grupos.map((g, i) => <li key={i}>{g.nome} · {dataCurta(g.em)}{g.teste ? ' (teste)' : ''}</li>)}</ul></div>)}
          {(b.olx || []).length > 0 && (
            <div><p className="text-xs font-semibold text-muted mb-1">Anunciantes da OLX perguntados</p>
              <ul className="grid gap-0.5">{b.olx.map((a, i) => (
                <li key={i}>{a.anunciante || 'anunciante'} (…{String(a.tel).slice(-4)}) · <a className="underline" href={a.url} target="_blank" rel="noopener noreferrer">{a.titulo}</a>
                  {a.preco ? ` · R$ ${Number(a.preco).toLocaleString('pt-BR')}` : ''}{a.bairro ? ` · ${a.bairro}` : ''}{a.teste ? ' (teste)' : ''}</li>))}</ul></div>)}
          {(b.ofertas || []).length > 0 && (
            <div><p className="text-xs font-semibold text-muted mb-1">Imóveis dos corretores</p>
              <ul className="grid gap-0.5">{b.ofertas.map((o, i) => (
                <li key={i}><a className="underline" href={`/admin/imovel-editar.html?codigo=${o.codigo}`} target="_blank" rel="noopener noreferrer">#{o.codigo}</a>
                  {' '}de {o.nome || 'corretor'} (…{String(o.tel).slice(-4)})</li>))}</ul></div>)}
          <div><p className="text-xs font-semibold text-muted mb-1">Passos</p>
            <ol className="grid gap-1">{(b.passos || []).map((p, i) => (
              <li key={i} className="flex gap-2"><span className="text-xs text-muted whitespace-nowrap pt-0.5">{quando(p.em)}</span>
                <span>{p.texto}</span></li>))}</ol></div>
        </div>
      )}
    </div>
  )
}

const CAMPO = 'w-full px-3 py-2 border border-line rounded-lg text-sm text-ink bg-transparent focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent'
const ROTULO = 'block text-xs font-semibold text-muted mb-1'

const SUBTIPOS: Array<[string, string]> = [['casa_condominio', 'Casa de condomínio'], ['casa_vila', 'Casa de vila'], ['cobertura', 'Cobertura'],
  ['duplex', 'Duplex ou tríplex'], ['kitnet', 'Kitnet'], ['loft', 'Loft'], ['padrao', 'Padrão']]
const DETALHES: Array<[string, string]> = [['academia', 'Academia'], ['aquecimento', 'Aquecimento'], ['ar_condicionado', 'Ar condicionado'],
  ['area_servico', 'Área de serviço'], ['armarios_cozinha', 'Armários na cozinha'], ['armarios_quarto', 'Armários no quarto'],
  ['banheiro_quarto', 'Banheiro no quarto'], ['churrasqueira', 'Churrasqueira'], ['internet', 'Internet'], ['mobiliado', 'Mobiliado'],
  ['piscina', 'Piscina'], ['porteiro_24h', 'Porteiro 24h'], ['quarto_servico', 'Quarto de serviço'], ['salao_festas', 'Salão de festas'],
  ['tv_cabo', 'TV a cabo'], ['varanda', 'Varanda']]
const CONDOMINIO: Array<[string, string]> = [['academia', 'Academia'], ['aceita_pet', 'Aceita pet'], ['area_murada', 'Área murada'],
  ['condominio_fechado', 'Condomínio fechado'], ['elevador', 'Elevador'], ['piscina', 'Piscina'], ['portao_eletronico', 'Portão eletrônico'],
  ['portaria', 'Portaria'], ['salao_festas', 'Salão de festas'], ['seguranca_24h', 'Segurança 24h']]
const alterna = (l: string[], k: string) => (l.includes(k) ? l.filter((x) => x !== k) : [...l, k])
const chipCls = (on: boolean) => `px-3 py-1.5 rounded-full border text-sm ${on ? 'bg-accent/15 border-accent text-accent font-semibold' : 'border-line text-ink'}`

function Bloco({ titulo, children }: { titulo: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-sm font-semibold text-ink mb-2">{titulo}</p>
      <div className="flex flex-wrap items-center gap-1.5">{children}</div>
    </div>
  )
}
function Faixa({ titulo, min, max, aoMin, aoMax, obrigatorioMax }: {
  titulo: string; min: string; max: string; aoMin: (v: string) => void; aoMax: (v: string) => void; obrigatorioMax?: boolean
}) {
  return (
    <div>
      <p className="text-sm font-semibold text-ink mb-2">{titulo}{obrigatorioMax ? ' *' : ''}</p>
      <div className="flex items-center gap-2">
        <input className={CAMPO} value={min} onChange={(e) => aoMin(e.target.value)} placeholder="Mín." inputMode="decimal" />
        <input className={CAMPO} value={max} onChange={(e) => aoMax(e.target.value)} placeholder="Máx." inputMode="decimal" required={obrigatorioMax} />
      </div>
    </div>
  )
}

function fone(t: string | null | undefined) {
  let d = String(t || '').replace(/\D/g, '')
  if (d.length >= 12 && d.startsWith('55')) d = d.slice(2)
  return d.length === 11 ? `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}` : (t || '')
}
function quando(iso: string) {
  const d = new Date(iso)
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Manaus' })
}
function resumo(f: Record<string, any>) {
  return [f.finalidade === 'venda' ? 'venda' : 'locação', f.tipo,
          f.teto ? `até R$ ${Number(f.teto).toLocaleString('pt-BR')}` : '',
          (f.bairros || []).join(', ') || (f.qualquer_bairro ? 'qualquer bairro' : ''),
          f.quartos ? `${f.quartos} quartos` : '', f.aceita_escada === false ? 'com elevador' : '', f.mobilia]
    .filter(Boolean).join(' · ')
}

/* 29/10 (Pedro: "vai ficar no mesmo Busca OLX, com 2 abas: a Manual, que é a nova, e as da Nay de hoje vão para
   AUTOMÁTICO (Nay)"). A Manual lê o banco de scrap da OLX em quadradinhos com filtros (BuscaOlxManual); o link com
   ?telefone= (abrir a busca de um cliente) cai direto no Automático, onde o formulário abre. */
export default function BuscarImovelOlxPage() {
  return <Suspense fallback={null}><AbasDaBuscaOlx /></Suspense>
}

function AbasDaBuscaOlx() {
  const qs = useSearchParams()
  const [aba, setAba] = useState<'manual' | 'auto'>(qs.get('telefone') || qs.get('aba') === 'auto' ? 'auto' : 'manual')
  return (
    <div className="max-w-6xl mx-auto px-4 pt-6">
      <div className="flex items-center gap-2 border-b border-line pb-3">
        {([['manual', 'Manual'], ['auto', 'Automático (Nay)']] as const).map(([k, r]) => (
          <button key={k} type="button" onClick={() => setAba(k)}
                  className={`px-4 py-2 rounded-lg text-sm font-semibold border ${aba === k ? 'bg-accent/15 border-accent text-accent' : 'border-line text-ink'}`}>{r}</button>
        ))}
      </div>
      {aba === 'manual' ? <div className="py-5"><BuscaOlxManual /></div> : <BuscarImovelOlx />}
    </div>
  )
}

function BuscarImovelOlx() {
  const qs = useSearchParams()
  const [f, setF] = useState({
    nome: qs.get('nome') || '', telefone: qs.get('telefone') || '', finalidade: 'locacao', teto: '',
    bairros: '', qualquer_bairro: false, aceita_menos_quartos: false, financiamento: '', observacao: '',
  })
  /* 20/10 (Pedro: "a busca precisa ser mais detalhada, de preferência igual ao filtro da OLX, tenta simular"): os blocos do
     filtro da OLX, com os mesmos nomes e opções; o nay-olx põe cada um no endereço da busca da OLX. */
  const [o, setO] = useState<{
    tipos: string[]; subtipos: string[]; preco_min: string; iptu_min: string; iptu_max: string; quartos: number[]
    banheiros: number[]; vagas: number[]; area_min: string; area_max: string; detalhes: string[]; condominio: string[]
    anunciante: '' | 'p' | 'c'; ordem: 'recentes' | 'relevantes' | 'menor_preco'
  }>({ tipos: ['apartamento'], subtipos: [], preco_min: '', iptu_min: '', iptu_max: '', quartos: [], banheiros: [], vagas: [],
       area_min: '', area_max: '', detalhes: [], condominio: [], anunciante: '', ordem: 'recentes' })
  const [enviando, setEnviando] = useState(false)
  const [recado, setRecado] = useState<{ t: string; ok?: boolean } | null>(null)
  const [manual, setManual] = useState(!!qs.get('telefone'))
  const [filtro, setFiltro] = useState('ativas')
  const [novas, setNovas] = useState<BuscaCliente[]>([])
  const [carregandoNovas, setCarregandoNovas] = useState(true)

  const carregarNovas = useCallback(async () => {
    try {
      const r = await fetch('/api/olx/buscas?dias=14')
      const j = await r.json()
      setNovas(j.buscas || [])
    } finally { setCarregandoNovas(false) }
  }, [])
  useEffect(() => {
    void carregarNovas()
    const t = setInterval(() => { if (document.visibilityState === 'visible') void carregarNovas() }, 20_000)
    return () => clearInterval(t)
  }, [carregarNovas])

  const agir = async (id: number, acao: string) => {
    if (acao === 'encerrar' && !window.confirm('Encerrar esta busca? Ela para de pedir nos grupos e na OLX.')) return
    const r = await fetch('/api/olx/buscas', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id, acao }) })
    if (!r.ok) { const j = await r.json().catch(() => ({})); window.alert(j.erro || j.error || 'Não deu.') }
    void carregarNovas()
  }

  const muda = (k: string, v: any) => setF((x) => ({ ...x, [k]: v }))

  const abrir = async (e: React.FormEvent) => {
    e.preventDefault()
    setEnviando(true)
    setRecado(null)
    try {
      const numero = (t: string) => t.replace(/\./g, '').replace(',', '.').trim()
      const corpo = {
        ...f, teto: numero(f.teto),
        bairros: f.bairros.split(/[,;\n]/).map((b) => b.trim()).filter(Boolean),
        tipo: o.tipos.length === 1 ? o.tipos[0] : null,
        quartos: o.quartos.length ? Math.min(...o.quartos) : null,
        mobilia: o.detalhes.includes('mobiliado') ? 'mobiliado' : null,
        precisa_elevador: o.condominio.includes('elevador'),
        financiamento: f.financiamento || null,
        olx: { ...o, preco_min: numero(o.preco_min) || null, iptu_min: numero(o.iptu_min) || null, iptu_max: numero(o.iptu_max) || null,
               area_min: numero(o.area_min) || null, area_max: numero(o.area_max) || null, anunciante: o.anunciante || null },
      }
      const r = await fetch('/api/olx/busca-parceiro', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) })
      const j = await r.json().catch(() => ({}))
      if (!r.ok || j.erro) { setRecado({ t: j.erro || j.error || 'Não abriu a busca.' }); return }
      setRecado({ t: `Busca aberta (nº ${j.busca || j.id}). Ela vai aos grupos e à base da OLX: o andamento aparece na lista.`, ok: true })
      setF((x) => ({ ...x, teto: '', bairros: '', observacao: '' }))
      void carregarNovas()
    } finally { setEnviando(false) }
  }

  return (
    <div className="py-5">
      <div className="flex flex-wrap items-start justify-between gap-3 pb-1">
        <h1 className="text-2xl font-bold text-ink">Buscas dos clientes</h1>
        <div className="flex gap-2">
          <button type="button" className="btn btn-outline btn-sm" onClick={() => void carregarNovas()}>Atualizar</button>
          <button type="button" className={`btn btn-sm ${manual ? 'btn-primary' : 'btn-outline'}`} onClick={() => setManual((x) => !x)}>
            {manual ? 'Fechar busca manual' : 'Busca manual'}</button>
        </div>
      </div>
      <p className="text-sm text-muted mb-4">
        Todo lead da aba Leads ganha uma busca com o que ele procura. Primeiro a Nay mostra as nossas opções; sem o perfil exato,
        ela avisa o cliente que vai continuar verificando e a busca anda sozinha: pedido nos grupos de WhatsApp (pela regra de
        cada grupo), anunciantes da OLX da nossa base perguntados sobre parceria, e o corretor que responder no privado tem o
        imóvel cadastrado e oferecido ao cliente. Tudo pelo número de captação (8595).
      </p>

      {manual && (
        <div className="mb-6">
        <form onSubmit={abrir} className="rounded-xl border border-line bg-panel p-4 grid gap-5">
          <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <div className="sm:col-span-2"><label className={ROTULO}>Nome do cliente</label>
              <input className={CAMPO} value={f.nome} onChange={(e) => muda('nome', e.target.value)} placeholder="Ana Souza" /></div>
            <div className="sm:col-span-2"><label className={ROTULO}>WhatsApp do cliente *</label>
              <input className={CAMPO} value={f.telefone} onChange={(e) => muda('telefone', e.target.value)} placeholder="(92) 99999-9999" required inputMode="tel" /></div>
            <div><label className={ROTULO}>Negócio *</label>
              <div className="flex gap-1.5">
                {([['locacao', 'Aluguel'], ['venda', 'Venda']] as const).map(([k, r]) => (
                  <button key={k} type="button" className={chipCls(f.finalidade === k)} onClick={() => muda('finalidade', k)}>{r}</button>
                ))}
              </div></div>
            <div className="sm:col-span-3"><label className={ROTULO}>Bairros (separe por vírgula) *</label>
              <div className="flex items-center gap-3">
                <input className={CAMPO} value={f.bairros} onChange={(e) => muda('bairros', e.target.value)} placeholder="Parque 10, Adrianópolis"
                       disabled={f.qualquer_bairro} />
                <label className="inline-flex items-center gap-1.5 text-sm text-ink whitespace-nowrap">
                  <input type="checkbox" checked={f.qualquer_bairro} onChange={(e) => muda('qualquer_bairro', e.target.checked)} /> Qualquer bairro</label>
              </div></div>
          </div>

          <Bloco titulo="Tipo do imóvel">
            {([['apartamento', f.finalidade === 'venda' ? 'Apartamentos à venda' : 'Apartamentos para alugar'],
               ['casa', f.finalidade === 'venda' ? 'Casas à venda' : 'Casas para alugar']] as const).map(([k, r]) => (
              <label key={k} className="inline-flex items-center gap-2 text-sm text-ink mr-5">
                <input type="checkbox" checked={o.tipos.includes(k)} onChange={() => setO((x) => ({ ...x, tipos: alterna(x.tipos, k) }))} /> {r}
              </label>
            ))}
          </Bloco>
          <Bloco titulo="Subtipo do imóvel">
            {SUBTIPOS.map(([k, r]) => (
              <button key={k} type="button" className={chipCls(o.subtipos.includes(k))} onClick={() => setO((x) => ({ ...x, subtipos: alterna(x.subtipos, k) }))}>{r}</button>
            ))}
          </Bloco>
          <div className="grid gap-4 sm:grid-cols-3">
            <Faixa titulo="Preço (R$)" min={o.preco_min} max={f.teto} obrigatorioMax
                   aoMin={(v) => setO((x) => ({ ...x, preco_min: v }))} aoMax={(v) => muda('teto', v)} />
            <Faixa titulo="IPTU (R$)" min={o.iptu_min} max={o.iptu_max}
                   aoMin={(v) => setO((x) => ({ ...x, iptu_min: v }))} aoMax={(v) => setO((x) => ({ ...x, iptu_max: v }))} />
            <Faixa titulo="Área (m²)" min={o.area_min} max={o.area_max}
                   aoMin={(v) => setO((x) => ({ ...x, area_min: v }))} aoMax={(v) => setO((x) => ({ ...x, area_max: v }))} />
          </div>
          <div className="grid gap-4 sm:grid-cols-3">
            {([['quartos', 'Número de quartos'], ['banheiros', 'Número de banheiros'], ['vagas', 'Vagas na garagem']] as const).map(([k, r]) => (
              <Bloco key={k} titulo={r}>
                {[0, 1, 2, 3, 4, 5].map((n) => (
                  <button key={n} type="button" className={`${chipCls(o[k].includes(n))} !px-3`}
                          onClick={() => setO((x) => ({ ...x, [k]: x[k].includes(n) ? x[k].filter((y) => y !== n) : [...x[k], n] }))}>{n === 5 ? '5+' : n}</button>
                ))}
              </Bloco>
            ))}
          </div>
          <label className="inline-flex items-center gap-2 text-sm text-ink -mt-2">
            <input type="checkbox" checked={f.aceita_menos_quartos} onChange={(e) => muda('aceita_menos_quartos', e.target.checked)} /> Aceita um quarto a menos
          </label>
          <Bloco titulo="Detalhes do imóvel">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-x-4 gap-y-1.5 w-full">
              {DETALHES.map(([k, r]) => (
                <label key={k} className="inline-flex items-center gap-2 text-sm text-ink">
                  <input type="checkbox" checked={o.detalhes.includes(k)} onChange={() => setO((x) => ({ ...x, detalhes: alterna(x.detalhes, k) }))} /> {r}
                </label>
              ))}
            </div>
          </Bloco>
          <Bloco titulo="Detalhes do condomínio">
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-x-4 gap-y-1.5 w-full">
              {CONDOMINIO.map(([k, r]) => (
                <label key={k} className="inline-flex items-center gap-2 text-sm text-ink">
                  <input type="checkbox" checked={o.condominio.includes(k)} onChange={() => setO((x) => ({ ...x, condominio: alterna(x.condominio, k) }))} /> {r}
                </label>
              ))}
            </div>
          </Bloco>
          <div className="grid gap-4 sm:grid-cols-3">
            <Bloco titulo="Tipo de anunciante">
              {([['', 'Ambos'], ['p', 'Particular'], ['c', 'Profissional']] as const).map(([k, r]) => (
                <button key={k || 'ambos'} type="button" className={chipCls(o.anunciante === k)} onClick={() => setO((x) => ({ ...x, anunciante: k }))}>{r}</button>
              ))}
            </Bloco>
            <Bloco titulo="Ordenar por">
              {([['relevantes', 'Mais relevantes'], ['recentes', 'Mais recentes'], ['menor_preco', 'Menor preço']] as const).map(([k, r]) => (
                <button key={k} type="button" className={chipCls(o.ordem === k)} onClick={() => setO((x) => ({ ...x, ordem: k }))}>{r}</button>
              ))}
            </Bloco>
            <div><label className={ROTULO}>Financiamento</label>
              <select className={CAMPO} value={f.financiamento} onChange={(e) => muda('financiamento', e.target.value)}>
                <option value="">Não precisa</option><option value="simular">Vai simular</option><option value="aprovado">Já aprovado</option></select></div>
          </div>
          <div><label className={ROTULO}>Observação para a equipe</label>
            <input className={CAMPO} value={f.observacao} onChange={(e) => muda('observacao', e.target.value)} placeholder="Ex.: perto da escola dos filhos" /></div>
          <div className="flex flex-wrap items-center gap-3">
            <button type="submit" className="btn btn-primary disabled:opacity-40" disabled={enviando}>{enviando ? 'Abrindo…' : 'Abrir a busca'}</button>
            {recado && <span className="text-sm" style={{ color: recado.ok ? '#16a34a' : '#dc2626' }}>{recado.t}</span>}
          </div>
        </form>
        </div>
      )}

      <div className="flex flex-wrap gap-1.5 mb-3">
        {FILTROS.map(([k, r]) => (
          <button key={k} type="button" className={chipCls(filtro === k)} onClick={() => setFiltro(k)}>
            {r} ({novas.filter((b) => passaNoFiltro(b, k)).length})</button>
        ))}
      </div>
      {carregandoNovas ? <p className="text-sm text-muted">Carregando…</p> : !novas.filter((b) => passaNoFiltro(b, filtro)).length ? (
        <p className="text-sm text-muted">Nenhuma busca aqui nos últimos 14 dias.</p>
      ) : (
        <div className="grid gap-3">
          {novas.filter((b) => passaNoFiltro(b, filtro)).map((b) => <CartaoDaBusca key={b.id} b={b} aoAgir={agir} />)}
        </div>
      )}
    </div>
  )
}
