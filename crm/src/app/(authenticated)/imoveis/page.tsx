'use client'

/**
 * A aba Imóveis do CRM.
 *
 * Tel, 27/09/2026: "ja tras uma aba imoveis que é a mesma aba do site
 * reformulada para dentro do crm tb para se alguem quiser buscar imoveis para la
 * e ja enviar para uma conversa".
 *
 * Mesma fonte que a Nay lê (a API do site, via `/api/imoveis-nay`), mesmos
 * filtros da tela de lá e o MESMO card que sai nos grupos. Nada de acervo
 * paralelo: imóvel alugado tem de aparecer alugado aqui no mesmo instante.
 *
 * O botão "Mandar para uma conversa" abre a busca de conversa e dispara o card +
 * as fotos pelo número por onde aquela pessoa fala. É o mesmo caminho do `/3050`
 * no campo de mensagem -- dois jeitos de fazer a mesma coisa, porque às vezes
 * você está na conversa e às vezes está procurando imóvel.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import {
  ArrowClockwise, Camera, CaretLeft, CaretRight, MagnifyingGlass, PaperPlaneTilt, X,
} from '@phosphor-icons/react'

interface Imovel {
  codigo: string
  status: string
  tipo: string | null
  valor: string
  valorVenda: number | null
  valorAluguel: number | null
  condominio: string
  bairro: string | null
  endereco: string
  quartos: number | null
  suites: number | null
  banheiros: number | null
  vagas: number | null
  area: number | null
  fotos: number
  capa: string | null
  anunciado: boolean
  parceiro: boolean
  proprietario: string
}

interface Facetas {
  status?: Record<string, number>
  tipo?: Record<string, number>
  fin?: Record<string, number>
  quartos?: Record<string, number>
  foto?: Record<string, number>
  parceiro?: Record<string, number>
  anuncio?: Record<string, number>
}

const POR_PAGINA = 24

const COR_STATUS: Record<string, string> = {
  'Disponível': 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30',
  'Alugado': 'bg-violet-500/15 text-violet-300 border-violet-500/30',
  'Vendido': 'bg-white/10 text-muted border-white/15',
  'Arquivado': 'bg-white/10 text-muted border-white/15',
  'Rascunho': 'bg-white/10 text-muted border-white/15',
  'Removido': 'bg-red-500/15 text-red-400 border-red-500/30',
  'Em revisão': 'bg-amber-500/15 text-amber-400 border-amber-500/30',
}

/** Uma opção de filtro com a contagem do lado — igual à tela do site. */
function Op({ ligado, n, children, onClick }: {
  ligado: boolean; n?: number; children: React.ReactNode; onClick: () => void
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={n === 0 && !ligado}
      className={`px-2.5 py-1 rounded-full text-xs border transition disabled:opacity-40 ${
        ligado
          ? 'bg-accent text-black border-accent font-semibold'
          : 'bg-panel-2 border-line text-ink hover:border-accent/60'
      }`}
    >
      {children}
      {n !== undefined && <span className={`ml-1.5 ${ligado ? 'opacity-70' : 'text-muted'}`}>{n}</span>}
    </button>
  )
}

export default function ImoveisPage() {
  const [busca, setBusca] = useState('')
  const [buscaAtiva, setBuscaAtiva] = useState('')
  const [status, setStatus] = useState<string[]>(['Disponível'])
  const [grupo, setGrupo] = useState('')
  const [fin, setFin] = useState('')
  const [quartos, setQuartos] = useState('')
  const [foto, setFoto] = useState('')
  const [parceiro, setParceiro] = useState('nao')
  const [anuncio, setAnuncio] = useState('')
  const [bairro, setBairro] = useState('')
  const [pagina, setPagina] = useState(1)

  const [itens, setItens] = useState<Imovel[]>([])
  const [total, setTotal] = useState(0)
  const [facetas, setFacetas] = useState<Facetas>({})
  const [carregando, setCarregando] = useState(true)
  const [erro, setErro] = useState<string | null>(null)
  const [escolhido, setEscolhido] = useState<string | null>(null)

  // Espera parar de digitar: uma consulta por tecla derruba a mão de qualquer um.
  useEffect(() => {
    const t = setTimeout(() => { setBuscaAtiva(busca); setPagina(1) }, 350)
    return () => clearTimeout(t)
  }, [busca])

  const params = useMemo(() => {
    const p = new URLSearchParams()
    if (buscaAtiva.trim()) p.set('q', buscaAtiva.trim())
    if (status.length) p.set('status', status.join(','))
    if (grupo) p.set('grupo', grupo)
    if (fin) p.set('finalidade', fin)
    if (quartos) p.set('quartos', `${quartos}+`)
    if (foto) p.set('com_foto', foto)
    if (parceiro) p.set('parceiro', parceiro)
    if (anuncio) p.set('anunciado', anuncio)
    if (bairro.trim()) p.set('bairro', bairro.trim())
    p.set('page', String(pagina))
    p.set('per', String(POR_PAGINA))
    return p
  }, [buscaAtiva, status, grupo, fin, quartos, foto, parceiro, anuncio, bairro, pagina])

  const carregar = useCallback(async () => {
    setCarregando(true); setErro(null)
    try {
      const res = await fetch(`/api/imoveis-nay?${params.toString()}`)
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'não consegui ler os imóveis')
      setItens(j.itens || [])
      setTotal(j.total || 0)
      setFacetas(j.facetas || {})
    } catch (e: any) {
      setErro(e?.message || 'não consegui ler os imóveis')
      setItens([])
    } finally {
      setCarregando(false)
    }
  }, [params])

  useEffect(() => { carregar() }, [carregar])

  function alternarStatus(s: string) {
    setPagina(1)
    setStatus((atual) => atual.includes(s) ? atual.filter((x) => x !== s) : [...atual, s])
  }
  function um<T extends string>(valor: T, set: (v: T) => void, atual: T) {
    setPagina(1)
    set(atual === valor ? ('' as T) : valor)
  }
  function limpar() {
    setBusca(''); setStatus([]); setGrupo(''); setFin(''); setQuartos('')
    setFoto(''); setParceiro(''); setAnuncio(''); setBairro(''); setPagina(1)
  }

  const paginas = Math.max(1, Math.ceil(total / POR_PAGINA))

  return (
    <div className="p-4 md:p-6 max-w-[1500px] mx-auto">
      <div className="flex items-start justify-between gap-3 flex-wrap mb-4">
        <div>
          <h1 className="text-xl md:text-2xl font-bold text-ink">Imóveis</h1>
          <p className="text-xs md:text-sm text-muted mt-0.5">
            O mesmo acervo que a Nay usa. Escolha um imóvel e mande para uma conversa —
            vai o card dos grupos e as fotos.
          </p>
        </div>
        <button type="button" onClick={carregar}
                className="btn-icon px-3 py-2 rounded-lg text-sm text-muted hover:text-ink flex items-center gap-2">
          <ArrowClockwise size={16} /> Atualizar
        </button>
      </div>

      {/* ---- busca e filtros ---- */}
      <div className="panel rounded-xl border border-line p-3 md:p-4 mb-4 space-y-3">
        <div className="flex gap-2 flex-wrap">
          <label className="flex-1 min-w-[220px] relative">
            <MagnifyingGlass size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-muted" />
            <input
              value={busca}
              onChange={(e) => setBusca(e.target.value)}
              placeholder="Código, condomínio, bairro, rua ou proprietário"
              className="w-full bg-panel-2 border border-line rounded-lg pl-9 pr-3 py-2 text-sm text-ink"
            />
          </label>
          <input
            value={bairro}
            onChange={(e) => { setBairro(e.target.value); setPagina(1) }}
            placeholder="Bairro"
            className="w-full sm:w-[150px] bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink"
          />
          <button type="button" onClick={limpar}
                  className="text-xs text-accent-2 underline px-2">limpar</button>
        </div>

        <div className="flex gap-1.5 overflow-x-auto pb-1 sm:flex-wrap sm:overflow-visible [&>*]:flex-shrink-0">
          {['Disponível', 'Alugado', 'Vendido', 'Em revisão', 'Rascunho'].map((s) => (
            <Op key={s} ligado={status.includes(s)} n={facetas.status?.[s]} onClick={() => alternarStatus(s)}>
              {s}
            </Op>
          ))}
        </div>

        <div className="flex gap-1.5 overflow-x-auto pb-1 sm:flex-wrap sm:overflow-visible [&>*]:flex-shrink-0">
          {[['apartamento', 'Apartamentos'], ['casa', 'Casas'], ['outros', 'Outros']].map(([v, r]) => (
            <Op key={v} ligado={grupo === v} n={facetas.tipo?.[v]} onClick={() => um(v, setGrupo, grupo)}>{r}</Op>
          ))}
          <span className="w-px bg-line mx-1" />
          {[['aluguel', 'Aluguel'], ['venda', 'Venda']].map(([v, r]) => (
            <Op key={v} ligado={fin === v} n={facetas.fin?.[v]} onClick={() => um(v, setFin, fin)}>{r}</Op>
          ))}
          <span className="w-px bg-line mx-1" />
          {['1', '2', '3', '4'].map((q) => (
            <Op key={q} ligado={quartos === q} n={facetas.quartos?.[q]} onClick={() => um(q, setQuartos, quartos)}>
              {q}+ quartos
            </Op>
          ))}
        </div>

        <div className="flex gap-1.5 overflow-x-auto pb-1 sm:flex-wrap sm:overflow-visible [&>*]:flex-shrink-0">
          <Op ligado={foto === 'sim'} n={facetas.foto?.sim} onClick={() => um('sim', setFoto, foto)}>Com foto</Op>
          <Op ligado={foto === 'nao'} n={facetas.foto?.nao} onClick={() => um('nao', setFoto, foto)}>Sem foto</Op>
          <span className="w-px bg-line mx-1" />
          <Op ligado={anuncio === 'sim'} n={facetas.anuncio?.sim} onClick={() => um('sim', setAnuncio, anuncio)}>No site</Op>
          <Op ligado={anuncio === 'nao'} n={facetas.anuncio?.nao} onClick={() => um('nao', setAnuncio, anuncio)}>Fora do site</Op>
          <span className="w-px bg-line mx-1" />
          <Op ligado={parceiro === 'nao'} n={facetas.parceiro?.nao} onClick={() => um('nao', setParceiro, parceiro)}>Nossos</Op>
          <Op ligado={parceiro === 'sim'} n={facetas.parceiro?.sim} onClick={() => um('sim', setParceiro, parceiro)}>De parceiro</Op>
        </div>
      </div>

      <div className="flex items-center justify-between gap-3 mb-3 text-sm text-muted">
        <span>{carregando ? 'procurando…' : <><b className="text-ink">{total.toLocaleString('pt-BR')}</b> imóveis</>}</span>
        {paginas > 1 && (
          <span className="flex items-center gap-2">
            <button type="button" disabled={pagina <= 1} onClick={() => setPagina((p) => p - 1)}
                    className="btn-icon p-1.5 rounded-lg disabled:opacity-30"><CaretLeft size={16} /></button>
            {pagina} de {paginas}
            <button type="button" disabled={pagina >= paginas} onClick={() => setPagina((p) => p + 1)}
                    className="btn-icon p-1.5 rounded-lg disabled:opacity-30"><CaretRight size={16} /></button>
          </span>
        )}
      </div>

      {erro && (
        <div className="bg-red-500/10 border border-red-500/30 text-red-400 text-sm rounded-xl px-4 py-3 mb-4">{erro}</div>
      )}

      {/* ---- a grade ---- */}
      <div className="grid gap-3 [grid-template-columns:repeat(auto-fill,minmax(min(230px,100%),1fr))]">
        {itens.map((i) => (
          <div key={i.codigo} className="panel rounded-xl border border-line overflow-hidden flex flex-col">
            <div className="relative aspect-[4/3] bg-panel-2">
              {i.capa
                ? <img src={i.capa} alt="" loading="lazy" className="w-full h-full object-cover" />
                : <span className="absolute inset-0 grid place-items-center text-muted text-xs gap-1 flex-col">
                    <Camera size={20} /> sem foto
                  </span>}
              <span className={`absolute top-2 left-2 text-[10px] px-2 py-0.5 rounded-full border ${
                COR_STATUS[i.status] || 'bg-white/10 text-muted border-white/15'}`}>
                {i.status}
              </span>
              {i.parceiro && (
                <span className="absolute top-2 right-2 text-[10px] px-2 py-0.5 rounded-full border bg-amber-500/20 text-amber-300 border-amber-500/30">
                  parceiro
                </span>
              )}
            </div>
            <div className="p-3 flex-1 flex flex-col gap-1">
              <p className="text-sm font-semibold text-ink truncate">{i.condominio || i.tipo || `Imóvel ${i.codigo}`}</p>
              <p className="text-[11px] text-muted truncate">
                {[i.bairro, i.tipo, i.quartos ? `${i.quartos} quartos` : null,
                  i.area ? `${Math.round(i.area)} m²` : null].filter(Boolean).join(' · ')}
              </p>
              <p className="text-sm font-bold text-accent-2">{i.valor.replace(/^(Venda|Aluguel): /, '')}</p>
              <p className="text-[11px] text-muted">
                cód. {i.codigo} · {i.fotos ? `${i.fotos} fotos` : 'sem foto'} · {i.anunciado ? 'no site' : 'fora do site'}
              </p>
              <button type="button" onClick={() => setEscolhido(i.codigo)}
                      className="mt-2 w-full bg-accent text-black font-bold py-1.5 rounded-lg text-xs flex items-center justify-center gap-1.5">
                <PaperPlaneTilt size={13} /> Mandar para uma conversa
              </button>
            </div>
          </div>
        ))}
      </div>

      {!carregando && itens.length === 0 && !erro && (
        <p className="text-sm text-muted py-10 text-center">
          Nenhum imóvel com esses filtros. Tire um filtro acima.
        </p>
      )}

      {escolhido && <MandarParaConversa codigo={escolhido} onClose={() => setEscolhido(null)} />}
    </div>
  )
}

/* ---------------------------------------------------------------------------
   Escolher a conversa e mandar.

   A busca de conversa é a mesma do chat (`/api/leads/search`), então quem já
   sabe procurar lead ali sabe procurar aqui.
   --------------------------------------------------------------------------- */
function MandarParaConversa({ codigo, onClose }: { codigo: string; onClose: () => void }) {
  const [q, setQ] = useState('')
  const [hits, setHits] = useState<any[]>([])
  const [procurando, setProcurando] = useState(false)
  const [enviando, setEnviando] = useState<string | null>(null)
  const [recado, setRecado] = useState<string | null>(null)
  const [comFotos, setComFotos] = useState(true)

  useEffect(() => {
    if (q.trim().length < 2) { setHits([]); return }
    let vivo = true
    setProcurando(true)
    const t = setTimeout(async () => {
      try {
        const res = await fetch('/api/leads/search', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ q: q.trim(), limit: 20 }),
        })
        const j = await res.json()
        if (vivo) setHits(j?.hits || [])
      } catch {
        if (vivo) setHits([])
      } finally {
        if (vivo) setProcurando(false)
      }
    }, 300)
    return () => { vivo = false; clearTimeout(t) }
  }, [q])

  async function mandar(leadId: string, nome: string) {
    setEnviando(leadId); setRecado(null)
    try {
      const res = await fetch(`/api/leads/${leadId}/enviar-imovel`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ codigo, fotos: comFotos }),
      })
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'não consegui mandar')
      const avisoParceiro = j.e_parceiro
        ? ' ATENÇÃO: esse é imóvel DE PARCEIRO — a Nay nunca manda imóvel de parceiro.'
        : ''
      const falhas = j.fotos_que_falharam ? ` ${j.fotos_que_falharam} foto(s) não foram.` : ''
      setRecado(`Mandei o ${codigo} para ${nome}: card + ${j.fotos_enviadas} foto(s).${falhas}${avisoParceiro}`)
    } catch (e: any) {
      setRecado(`Não saiu para ${nome}: ${e?.message || 'erro'}`)
    } finally {
      setEnviando(null)
    }
  }

  return (
    <div className="fixed inset-0 z-[120] flex items-center justify-center p-4 bg-black/65" onClick={onClose}>
      <div onClick={(e) => e.stopPropagation()}
           className="w-full max-w-md bg-panel border border-line rounded-2xl p-4 max-h-[88vh] overflow-y-auto">
        <div className="flex items-center justify-between mb-3">
          <h2 className="text-base font-bold text-ink">Mandar o imóvel {codigo}</h2>
          <button type="button" onClick={onClose} className="text-muted hover:text-ink"><X size={18} /></button>
        </div>

        <label className="flex items-center gap-2 text-xs text-muted mb-3">
          <input type="checkbox" checked={comFotos} onChange={(e) => setComFotos(e.target.checked)} />
          mandar as fotos também (até 8)
        </label>

        {recado && (
          <div className="bg-panel-2 border border-line text-ink text-xs rounded-lg px-3 py-2 mb-3">{recado}</div>
        )}

        <input
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Nome ou telefone da conversa"
          autoFocus
          className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink mb-2"
        />

        {procurando && <p className="text-xs text-muted">procurando…</p>}
        {!procurando && q.trim().length >= 2 && hits.length === 0 && (
          <p className="text-xs text-muted">Nenhuma conversa com esse nome.</p>
        )}

        <div className="space-y-1.5">
          {hits.map((h) => (
            <button
              key={h.lead.id}
              type="button"
              disabled={enviando === h.lead.id}
              onClick={() => mandar(h.lead.id, h.lead.title || h.lead.phone)}
              className="w-full text-left px-3 py-2 rounded-lg border border-line bg-panel-2 hover:border-accent/60 disabled:opacity-50"
            >
              <span className="block text-sm text-ink truncate">{h.lead.title || h.lead.phone}</span>
              <span className="block text-[11px] text-muted">
                {h.lead.phone}
                {h.lead.linhas?.length ? ` · ${h.lead.linhas.join(' e ')}` : ''}
                {enviando === h.lead.id ? ' · mandando…' : ''}
              </span>
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}
