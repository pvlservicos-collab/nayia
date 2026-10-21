'use client'

/**
 * A ESCOLHA DOS IMÓVEIS DO "ENVIAR IMÓVEL" -- um a um ou por faixa. É a mesma
 * na tela do menu (/disparo) e no card do contato da Parceria (Pedro,
 * 29/09/2026: "aqui no Enviar imóvel quero do jeito que tá no menu, por 1 ou
 * por faixa"). Quem guarda os escolhidos é quem usa; quem envia também.
 *
 * UM A UM (Tel, 28/09): "digita uma parte e desce uma lista de imóveis, eu
 * seleciono". POR FAIXA (Tel, 28/09): "selecionar uma faixa de renda, bairro ou
 * imobiliário e o sistema vai achar e marcar os imóveis para mim confirmar
 * visualmente" -- `/api/disparo/buscar` marca os primeiros (do mais barato) até
 * o teto por envio. A busca mostra só o que é nosso e está disponível: a rota
 * `/api/disparo` recusaria o resto.
 */
import { useEffect, useRef, useState } from 'react'
import { Camera, Check, Funnel, MagnifyingGlass, X } from '@phosphor-icons/react'

export interface ImovelParaEnviar {
  codigo: string
  tipo: string | null
  valor: string
  condominio: string
  bairro: string | null
  quartos: number | null
  fotos: number
  capa: string | null
  mobilia?: string | null
}

export interface OpcaoDoFiltro { valor: string; n?: number }

/** "Tarumã" acha digitando "taruma". */
function semAcento(s: string) {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase()
}

/**
 * Campo de várias escolhas (Tel, 28/09: "selecionar mais de um bairro... e
 * quando eu começo a digitar desce a lista também do nosso banco para só
 * selecionar sem precisar digitar certinho"). A lista sai de `opcoes` (o que
 * existe no nosso banco); cada escolha vira uma etiqueta que sai no ×.
 */
function Multi({ rotulo, opcoes, valores, aoMudar, dica }: {
  rotulo: string; opcoes: OpcaoDoFiltro[]; valores: string[]; aoMudar: (v: string[]) => void; dica: string
}) {
  const [texto, setTexto] = useState('')
  const [aberto, setAberto] = useState(false)
  const [ativo, setAtivo] = useState(0)
  const caixa = useRef<HTMLDivElement>(null)
  useEffect(() => {
    function fora(e: MouseEvent) { if (caixa.current && !caixa.current.contains(e.target as Node)) setAberto(false) }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [])
  const busca = semAcento(texto.trim())
  const lista = opcoes.filter((o) => !valores.includes(o.valor) && semAcento(o.valor).includes(busca)).slice(0, 60)
  function pegar(v: string) { aoMudar([...valores, v]); setTexto(''); setAtivo(0) }
  return (
    <div ref={caixa} className="relative">
      <span className="text-[11px] text-muted">{rotulo}</span>
      <div className="mt-0.5 min-h-[38px] w-full bg-panel-2 border border-line rounded-lg px-1.5 py-1 flex flex-wrap gap-1 items-center cursor-text"
           onClick={() => setAberto(true)}>
        {valores.map((v) => (
          <span key={v} className="inline-flex items-center gap-1 pl-2 pr-1 py-0.5 rounded-full text-xs bg-accent/15 text-ink border border-accent/40">
            {v}
            <button type="button" aria-label={`tirar ${v}`} className="p-0.5 rounded-full hover:bg-white/10"
                    onClick={(e) => { e.stopPropagation(); aoMudar(valores.filter((x) => x !== v)) }}>
              <X size={10} />
            </button>
          </span>
        ))}
        <input
          value={texto}
          onChange={(e) => { setTexto(e.target.value); setAberto(true); setAtivo(0) }}
          onFocus={() => setAberto(true)}
          onKeyDown={(e) => {
            if (e.key === 'ArrowDown') { e.preventDefault(); setAberto(true); setAtivo((a) => Math.min(a + 1, Math.max(lista.length - 1, 0))) }
            else if (e.key === 'ArrowUp') { e.preventDefault(); setAtivo((a) => Math.max(a - 1, 0)) }
            else if (e.key === 'Enter') { e.preventDefault(); if (lista[ativo]) pegar(lista[ativo].valor) }
            else if (e.key === 'Backspace' && !texto && valores.length) aoMudar(valores.slice(0, -1))
            else if (e.key === 'Escape') setAberto(false)
          }}
          placeholder={valores.length ? '' : dica}
          className="flex-1 min-w-[90px] bg-transparent outline-none text-sm text-ink px-1 py-1"
        />
      </div>
      {aberto && lista.length > 0 && (
        <div className="absolute z-30 left-0 right-0 mt-1 max-h-[240px] overflow-y-auto rounded-lg border border-line bg-panel shadow-xl">
          {lista.map((o, k) => (
            <button key={o.valor} type="button" onMouseDown={(e) => e.preventDefault()} onClick={() => pegar(o.valor)}
                    className={`w-full flex items-center justify-between gap-2 px-3 py-1.5 text-sm text-left ${k === ativo ? 'bg-accent/15' : 'hover:bg-panel-2'}`}>
              <span className="text-ink truncate">{o.valor}</span>
              {o.n !== undefined && <span className="text-muted text-xs flex-shrink-0">{o.n}</span>}
            </button>
          ))}
        </div>
      )}
    </div>
  )
}

/** Botões de liga-desliga, vários ao mesmo tempo (mobília, quartos). */
function Chips({ rotulo, opcoes, valores, aoMudar }: {
  rotulo: string; opcoes: [string, string][]; valores: string[]; aoMudar: (v: string[]) => void
}) {
  return (
    <div>
      <span className="text-[11px] text-muted">{rotulo}</span>
      <div className="mt-0.5 flex flex-wrap gap-1.5">
        {opcoes.map(([v, r]) => {
          const ligado = valores.includes(v)
          return (
            <button key={v} type="button" aria-pressed={ligado}
                    onClick={() => aoMudar(ligado ? valores.filter((x) => x !== v) : [...valores, v])}
                    className={`px-3 py-1.5 rounded-full text-xs border ${ligado ? 'bg-accent text-black border-accent font-semibold' : 'bg-panel-2 border-line text-ink hover:border-accent/60'}`}>
              {r}
            </button>
          )
        })}
      </div>
    </div>
  )
}

function reais(v: number) {
  return v.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 })
}

/** O que a busca por faixa devolve, no formato da lista da tela. */
function doAchado(a: any, fin: string): ImovelParaEnviar {
  const precos: string[] = []
  if (a.valorAluguel) precos.push(`Aluguel ${reais(a.valorAluguel)}`)
  if (a.valorVenda) precos.push(`Venda ${reais(a.valorVenda)}`)
  if (fin === 'venda') precos.reverse()
  return {
    codigo: String(a.codigo), tipo: a.tipo, valor: precos.join(' · '), condominio: a.titulo,
    bairro: a.bairro, quartos: a.quartos, fotos: a.fotos, capa: a.capa, mobilia: a.mobilia,
  }
}

/** As opções dos filtros e o teto por envio (GET /api/disparo), para quem não as tem. */
export function useOpcoesDoDisparo() {
  const [dados, setDados] = useState<{ opcoes: { bairros: OpcaoDoFiltro[]; tipos: OpcaoDoFiltro[] }; teto: number; linhas: any[] }>(
    { opcoes: { bairros: [], tipos: [] }, teto: 10, linhas: [] })
  useEffect(() => {
    fetch('/api/disparo').then((r) => r.json()).then((j) => {
      setDados({
        opcoes: { bairros: j.opcoes?.bairros || [], tipos: j.opcoes?.tipos || [] },
        teto: Number(j.teto) > 0 ? Number(j.teto) : 10,
        linhas: j.linhas || [],
      })
    }).catch(() => {})
  }, [])
  return dados
}

export default function EscolherImoveis({ escolhidos, aoMudar, teto, opcoes, compacto = false, aoAvisar, pedido }: {
  escolhidos: ImovelParaEnviar[]
  aoMudar: (lista: ImovelParaEnviar[]) => void
  teto: number
  opcoes: { bairros: OpcaoDoFiltro[]; tipos: OpcaoDoFiltro[] }
  /** o card do contato: uma coluna só */
  compacto?: boolean
  /** "no máximo N por envio" e afins, para quem mostra os avisos */
  aoAvisar?: (texto: string | null) => void
  /** pôr um código de fora (o histórico do card): { codigo, vez } -- `vez` muda a cada clique */
  pedido?: { codigo: string; vez: number } | null
}) {
  const [modo, setModo] = useState<'um' | 'faixa'>('um')
  const [busca, setBusca] = useState('')
  const [resultados, setResultados] = useState<ImovelParaEnviar[]>([])
  const [procurando, setProcurando] = useState(false)
  const [aberta, setAberta] = useState(false)
  const caixa = useRef<HTMLDivElement>(null)

  const [filtro, setFiltro] = useState({
    finalidade: 'aluguel', vmin: '', vmax: '',
    bairros: [] as string[], tipos: [] as string[], mobilias: [] as string[], quartos: [] as string[],
  })
  const [achados, setAchados] = useState<ImovelParaEnviar[] | null>(null)
  const [buscandoFaixa, setBuscandoFaixa] = useState(false)
  const [avisoFaixa, setAvisoFaixa] = useState<string | null>(null)

  async function buscarFaixa() {
    setBuscandoFaixa(true); setAvisoFaixa(null); aoAvisar?.(null)
    try {
      const p = new URLSearchParams()
      if (filtro.finalidade) p.set('finalidade', filtro.finalidade)
      if (filtro.vmin.trim()) p.set('vmin', filtro.vmin.trim())
      if (filtro.vmax.trim()) p.set('vmax', filtro.vmax.trim())
      filtro.bairros.forEach((v) => p.append('bairro', v))
      filtro.tipos.forEach((v) => p.append('tipo', v))
      filtro.mobilias.forEach((v) => p.append('mobilia', v))
      filtro.quartos.forEach((v) => p.append('quartos', v))
      const res = await fetch(`/api/disparo/buscar?${p.toString()}`)
      const j = await res.json()
      if (!res.ok) throw new Error(j?.error || 'não consegui procurar')
      const lista: ImovelParaEnviar[] = (j.itens || []).map((a: any) => doAchado(a, filtro.finalidade))
      setAchados(lista)
      // MARCA SOZINHO os primeiros (do mais barato), até o teto por envio -- ele confere e ajusta
      aoMudar(lista.slice(0, teto))
      setAvisoFaixa(!lista.length ? 'Nenhum imóvel nosso disponível nessa faixa. Afrouxe um filtro.'
        : lista.length > teto ? `Achei ${lista.length}; marquei os ${teto} mais baratos (é o máximo por envio). Troque à vontade.`
        : `Achei ${lista.length} e marquei todos. Confira e desmarque o que não quiser.`)
    } catch (err: any) {
      setAchados([]); aoMudar([])
      setAvisoFaixa(err?.message || 'não consegui procurar')
    } finally {
      setBuscandoFaixa(false)
    }
  }

  function trocarModo(m: 'um' | 'faixa') {
    if (m === modo) return
    setModo(m); aoMudar([]); aoAvisar?.(null); setAvisoFaixa(null); setAchados(null); setBusca('')
  }

  // a lista desce enquanto ele digita (espera 300 ms entre teclas)
  useEffect(() => {
    const q = busca.trim()
    if (q.length < 2) { setResultados([]); return }
    const t = setTimeout(async () => {
      setProcurando(true)
      try {
        const p = new URLSearchParams({ q, status: 'Disponível', parceiro: 'nao', per: '15', page: '1' })
        const res = await fetch(`/api/imoveis-nay?${p.toString()}`)
        const j = await res.json()
        setResultados(res.ok ? (j.itens || []) : [])
        setAberta(true)
      } catch {
        setResultados([])
      } finally {
        setProcurando(false)
      }
    }, 300)
    return () => clearTimeout(t)
  }, [busca])

  // clicar fora fecha a lista
  useEffect(() => {
    function fora(e: MouseEvent) {
      if (caixa.current && !caixa.current.contains(e.target as Node)) setAberta(false)
    }
    document.addEventListener('mousedown', fora)
    return () => document.removeEventListener('mousedown', fora)
  }, [])

  // um código de fora (o histórico do card): acha e marca, no modo um a um
  const escolhidosRef = useRef(escolhidos)
  escolhidosRef.current = escolhidos
  useEffect(() => {
    if (!pedido?.codigo) return
    let vivo = true
    setModo('um'); setAchados(null); setAvisoFaixa(null)
    ;(async () => {
      try {
        const p = new URLSearchParams({ q: pedido.codigo, status: 'Disponível', parceiro: 'nao', per: '10', page: '1' })
        const res = await fetch(`/api/imoveis-nay?${p.toString()}`)
        const j = await res.json()
        if (!vivo) return
        const achado = (j.itens || []).find((i: ImovelParaEnviar) => String(i.codigo) === pedido.codigo)
        const atuais = escolhidosRef.current
        if (!achado) { aoAvisar?.(`O ${pedido.codigo} não está disponível para envio (parceiro, fora do ar ou não existe).`); return }
        if (atuais.some((x) => x.codigo === achado.codigo)) return
        if (atuais.length >= teto) { aoAvisar?.(`No máximo ${teto} imóveis por envio. Desmarque um para marcar outro.`); return }
        aoAvisar?.(null)
        aoMudar([...atuais, achado])
      } catch { /* fica como está */ }
    })()
    return () => { vivo = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pedido?.vez])

  function alternar(i: ImovelParaEnviar) {
    aoAvisar?.(null)
    if (escolhidos.some((x) => x.codigo === i.codigo)) {
      aoMudar(escolhidos.filter((x) => x.codigo !== i.codigo))
      return
    }
    if (escolhidos.length >= teto) {
      aoAvisar?.(`No máximo ${teto} imóveis por envio. Desmarque um para marcar outro.`)
      return
    }
    aoMudar([...escolhidos, i])
  }

  const linhaDoImovel = (i: ImovelParaEnviar, marcado: boolean, faixa: boolean) => (
    <button key={i.codigo} type="button" onClick={() => alternar(i)}
            className={`w-full flex items-center gap-3 px-3 py-2 text-left border-b border-line last:border-0 hover:bg-panel-2 ${
              marcado ? 'bg-accent/10' : faixa ? 'opacity-70' : ''}`}>
      <span className={`w-5 h-5 rounded border flex-shrink-0 grid place-items-center ${
        marcado ? 'bg-accent border-accent text-black' : 'border-line'}`}>
        {marcado && <Check size={12} weight="bold" />}
      </span>
      {i.capa
        ? <img src={i.capa} alt="" loading="lazy" className="w-12 h-9 rounded object-cover flex-shrink-0" />
        : <span className="w-12 h-9 rounded bg-panel-2 grid place-items-center text-muted flex-shrink-0"><Camera size={14} /></span>}
      <span className="min-w-0 flex-1">
        <span className="block text-sm text-ink truncate"><b>#{i.codigo}</b> · {i.condominio || i.tipo || 'Imóvel'}</span>
        <span className="block text-[11px] text-muted truncate">
          {(faixa
            ? [i.valor, i.bairro, i.quartos ? `${i.quartos} quartos` : null, i.mobilia || null, i.fotos ? `${i.fotos} fotos` : 'sem foto']
            : [i.bairro, i.quartos ? `${i.quartos} quartos` : null, i.valor, i.fotos ? `${i.fotos} fotos` : 'sem foto']
          ).filter(Boolean).join(' · ')}
        </span>
      </span>
    </button>
  )

  return (
    <div>
      <div className="flex items-center justify-between gap-2 flex-wrap">
        {!compacto && <span className="text-xs text-muted">Imóveis</span>}
        <div className={`inline-flex rounded-lg border border-line p-0.5 text-xs ${compacto ? 'w-full' : ''}`} role="tablist">
          {([['um', 'Um a um', MagnifyingGlass], ['faixa', 'Por faixa', Funnel]] as const).map(([m, rot, Ico]) => (
            <button key={m} type="button" role="tab" aria-selected={modo === m} onClick={() => trocarModo(m)}
                    className={`px-3 py-1.5 rounded-md flex items-center justify-center gap-1.5 font-semibold ${compacto ? 'flex-1' : ''} ${
                      modo === m ? 'bg-accent text-black' : 'text-muted hover:text-ink'}`}>
              <Ico size={13} /> {rot}
            </button>
          ))}
        </div>
      </div>

      {modo === 'faixa' && (
        <div className="mt-3">
          <div className={`grid gap-2 ${compacto ? 'grid-cols-2' : 'grid-cols-2 sm:grid-cols-4'}`}>
            <label className={`block ${compacto ? 'col-span-2' : ''}`}>
              <span className="text-[11px] text-muted">Finalidade</span>
              <select value={filtro.finalidade} onChange={(e) => setFiltro({ ...filtro, finalidade: e.target.value })}
                      className="mt-0.5 w-full bg-panel-2 border border-line rounded-lg px-2 py-2 text-sm text-ink">
                <option value="aluguel">Aluguel</option>
                <option value="venda">Venda</option>
                <option value="">Tanto faz</option>
              </select>
            </label>
            <label className="block">
              <span className="text-[11px] text-muted">Valor de (R$)</span>
              <input value={filtro.vmin} onChange={(e) => setFiltro({ ...filtro, vmin: e.target.value })}
                     inputMode="numeric" placeholder="0"
                     className="mt-0.5 w-full bg-panel-2 border border-line rounded-lg px-2 py-2 text-sm text-ink" />
            </label>
            <label className="block">
              <span className="text-[11px] text-muted">até (R$)</span>
              <input value={filtro.vmax} onChange={(e) => setFiltro({ ...filtro, vmax: e.target.value })}
                     inputMode="numeric" placeholder="sem limite"
                     className="mt-0.5 w-full bg-panel-2 border border-line rounded-lg px-2 py-2 text-sm text-ink" />
            </label>
            <div className={`col-span-2 grid gap-2 ${compacto ? '' : 'sm:col-span-4 sm:grid-cols-2'}`}>
              <Multi rotulo="Bairros" dica="digite e escolha: um ou vários" opcoes={opcoes.bairros}
                     valores={filtro.bairros} aoMudar={(v) => setFiltro({ ...filtro, bairros: v })} />
              <Multi rotulo="Tipos de imóvel" dica="todos" opcoes={opcoes.tipos}
                     valores={filtro.tipos} aoMudar={(v) => setFiltro({ ...filtro, tipos: v })} />
            </div>
            <div className={`col-span-2 flex flex-wrap gap-4 ${compacto ? '' : 'sm:col-span-3'}`}>
              <Chips rotulo="Mobília" opcoes={[['mobiliado', 'Mobiliado'], ['semi', 'Semimobiliado']]}
                     valores={filtro.mobilias} aoMudar={(v) => setFiltro({ ...filtro, mobilias: v })} />
              <Chips rotulo="Quartos" opcoes={[['1', '1'], ['2', '2'], ['3', '3'], ['4', '4+']]}
                     valores={filtro.quartos} aoMudar={(v) => setFiltro({ ...filtro, quartos: v })} />
            </div>
            <div className={`flex items-end ${compacto ? 'col-span-2' : ''}`}>
              <button type="button" onClick={buscarFaixa} disabled={buscandoFaixa}
                      className="w-full border border-accent text-accent-2 font-bold py-2 rounded-lg text-sm flex items-center justify-center gap-1.5 disabled:opacity-40">
                <Funnel size={14} /> {buscandoFaixa ? 'procurando…' : 'Buscar'}
              </button>
            </div>
          </div>

          {avisoFaixa && <p className="mt-3 text-xs text-muted">{avisoFaixa}</p>}

          {achados && achados.length > 0 && (
            <div className={`mt-2 overflow-y-auto rounded-lg border border-line bg-panel dark:bg-transparent ${compacto ? 'max-h-[340px]' : 'max-h-[420px]'}`}>
              <div className="flex items-center justify-between gap-2 flex-wrap px-3 py-1.5 text-[11px] text-muted border-b border-line bg-panel-2 sticky top-0">
                <span><b className="text-ink">{escolhidos.length}</b> de {achados.length} marcados (máximo {teto})</span>
                <span className="flex gap-3">
                  <button type="button" className="underline" onClick={() => { aoAvisar?.(null); aoMudar(achados.slice(0, teto)) }}>
                    marcar os {Math.min(teto, achados.length)} primeiros
                  </button>
                  <button type="button" className="underline" onClick={() => { aoAvisar?.(null); aoMudar([]) }}>desmarcar todos</button>
                </span>
              </div>
              {achados.map((i) => linhaDoImovel(i, escolhidos.some((x) => x.codigo === i.codigo), true))}
            </div>
          )}
        </div>
      )}

      {modo === 'um' && (
        <div ref={caixa} className="relative mt-2">
          <MagnifyingGlass size={16} className="absolute left-3 top-[11px] text-muted" />
          <input
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            onFocus={() => resultados.length && setAberta(true)}
            placeholder={compacto ? 'Código, condomínio, bairro ou rua' : 'Digite uma parte: código, condomínio, bairro ou rua'}
            className="w-full bg-panel-2 border border-line rounded-lg pl-9 pr-3 py-2 text-sm text-ink"
          />
          {aberta && busca.trim().length >= 2 && (
            <div className="absolute z-20 left-0 right-0 mt-1 max-h-[360px] overflow-y-auto rounded-lg border border-line bg-panel shadow-xl">
              {procurando && <p className="px-3 py-2 text-xs text-muted">procurando…</p>}
              {!procurando && resultados.length === 0 && (
                <p className="px-3 py-2 text-xs text-muted">Nenhum imóvel nosso disponível com isso.</p>
              )}
              {resultados.map((i) => linhaDoImovel(i, escolhidos.some((x) => x.codigo === i.codigo), false))}
            </div>
          )}
        </div>
      )}

      {modo === 'um' && escolhidos.length > 0 && (
        <div className="mt-3 flex flex-wrap gap-1.5">
          {escolhidos.map((i) => (
            <span key={i.codigo} className="inline-flex items-center gap-1 pl-2.5 pr-1 py-1 rounded-full text-xs bg-accent/15 bg-panel-2 dark:bg-transparent text-ink border border-accent/40">
              #{i.codigo} {i.condominio || i.tipo || ''}
              <button type="button" onClick={() => alternar(i)} className="p-0.5 rounded-full hover:bg-white/10" aria-label="tirar">
                <X size={11} />
              </button>
            </span>
          ))}
        </div>
      )}
    </div>
  )
}
