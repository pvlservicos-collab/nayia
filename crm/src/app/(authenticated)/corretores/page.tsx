'use client'

/**
 * A ABA CORRETORES (Pedro, 30/09/2026): "cria mais uma aba ali no CRM, Corretores:
 * vai ser uma aba com vários quadradinhos, cada quadradinho um corretor, e ali vai
 * ter métricas que o CRM vai guardar -- quantidade de interações, visitas
 * agendadas, contratos fechados -- e ali listar e dar para filtrar pelos nossos
 * melhores corretores parceiros".
 *
 * Um cartão por corretor parceiro (quem a Nay reconhece como corretor na
 * Parceria), no período escolhido. Os números vêm de /api/corretores, o mesmo de
 * Configurações > Corretores (a tabela, com a pasta de documentos):
 *   interações      mensagens dele + as nossas
 *   visitas         agendadas (pedidas) e realizadas
 *   contratos       fechamentos que a Rayssa concluiu (e o que está em andamento)
 * "Melhores" ordena por uma nota que pesa contrato > visita realizada > visita
 * agendada > conversa. O cartão abre a conversa.
 */
import { useEffect, useMemo, useState } from 'react'
import Link from 'next/link'
import {
  MagnifyingGlass, ChatCircleText, CalendarCheck, Handshake, Trophy, CircleNotch, Copy, Check, IdentificationBadge,
} from '@phosphor-icons/react'
import { linkDaConversa } from '@/lib/links'
import { numeroParaCopiar } from '@/components/Chat/PainelContatoParceria'

type Corretor = {
  leadId: string
  nome: string
  nomeNoCadastro: string | null
  telefone: string | null
  creci: string | null
  avatar: string | null
  mensagensDele: number
  mensagensNossas: number
  ultimaMensagem: string | null
  visitasPedidas: number
  visitasRealizadas: number
  visitasAbertas: number
  documentos: number
  contratosFechados: number
  fechamentoEmAndamento: number
}

type Ordem = 'melhores' | 'interacoes' | 'visitas' | 'contratos' | 'recentes' | 'nome'
type Filtro = 'todos' | 'com_visita' | 'com_contrato' | 'ativos'

const PERIODOS: Array<[number, string]> = [[7, '7 dias'], [30, '30 dias'], [90, '90 dias'], [365, '1 ano']]
const ORDENS: Array<[Ordem, string]> = [
  ['melhores', 'Melhores'], ['contratos', 'Mais contratos'], ['visitas', 'Mais visitas'],
  ['interacoes', 'Mais interações'], ['recentes', 'Conversa mais recente'], ['nome', 'Nome'],
]
const FILTROS: Array<[Filtro, string]> = [
  ['todos', 'Todos'], ['ativos', 'Conversaram no período'], ['com_visita', 'Com visita'], ['com_contrato', 'Com contrato'],
]

/** a nota dos "melhores": contrato vale mais que visita, que vale mais que conversa */
function nota(c: Corretor): number {
  return c.contratosFechados * 20 + c.fechamentoEmAndamento * 8 + c.visitasRealizadas * 6 + c.visitasPedidas * 3
    + Math.min(c.mensagensDele, 200) * 0.1
}

function quando(iso: string | null) {
  if (!iso) return 'sem conversa'
  const dias = Math.floor((Date.now() - new Date(iso).getTime()) / 86400000)
  if (dias <= 0) return 'falou hoje'
  if (dias === 1) return 'falou ontem'
  return `falou há ${dias} dias`
}

function iniciais(nome: string) {
  return nome.split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]?.toUpperCase() || '').join('') || '?'
}

function CopiarNumero({ telefone }: { telefone: string | null }) {
  const numero = numeroParaCopiar(telefone)
  const [ok, setOk] = useState(false)
  if (!numero) return null
  return (
    <button type="button" title="Copiar o número (sem o 55)"
            className="inline-flex items-center gap-1 text-xs text-muted hover:text-ink"
            onClick={async (e) => {
              e.preventDefault(); e.stopPropagation()
              try { await navigator.clipboard.writeText(numero); setOk(true); setTimeout(() => setOk(false), 1500) } catch {}
            }}>
      {numero} {ok ? <Check size={12} weight="bold" className="text-accent" /> : <Copy size={12} />}
    </button>
  )
}

function Metrica({ icone: Icone, valor, rotulo, detalhe }: {
  icone: typeof ChatCircleText; valor: number; rotulo: string; detalhe?: string
}) {
  return (
    <div className="rounded-lg bg-panel-2 border border-line px-2.5 py-2 min-w-0">
      <div className="flex items-center gap-1.5 text-muted text-[11px] uppercase tracking-wide">
        <Icone size={14} /> <span className="truncate">{rotulo}</span>
      </div>
      <div className="text-xl font-bold text-ink leading-tight mt-0.5">{valor}</div>
      {detalhe && <div className="text-[11px] text-muted truncate">{detalhe}</div>}
    </div>
  )
}

export default function CorretoresPage() {
  const [dias, setDias] = useState(30)
  const [lista, setLista] = useState<Corretor[] | null>(null)
  const [erro, setErro] = useState<string | null>(null)
  const [busca, setBusca] = useState('')
  const [ordem, setOrdem] = useState<Ordem>('melhores')
  const [filtro, setFiltro] = useState<Filtro>('todos')

  useEffect(() => {
    let vivo = true
    setLista(null); setErro(null)
    fetch(`/api/corretores?dias=${dias}`)
      .then(async (r) => { const j = await r.json().catch(() => ({})); if (!r.ok) throw new Error(j?.error || `HTTP ${r.status}`); return j })
      .then((j) => { if (vivo) setLista(j.corretores || []) })
      .catch((e) => { if (vivo) setErro(e?.message || 'Não consegui carregar') })
    return () => { vivo = false }
  }, [dias])

  const cartoes = useMemo(() => {
    const q = busca.trim().toLowerCase()
    const f = (lista || []).filter((c) => {
      if (q && ![c.nome, c.nomeNoCadastro, c.creci, c.telefone].some((x) => String(x ?? '').toLowerCase().includes(q))) return false
      if (filtro === 'com_visita' && c.visitasPedidas === 0) return false
      if (filtro === 'com_contrato' && c.contratosFechados + c.fechamentoEmAndamento === 0) return false
      if (filtro === 'ativos' && c.mensagensDele === 0) return false
      return true
    })
    const valor = (c: Corretor): number | string => ordem === 'melhores' ? nota(c)
      : ordem === 'contratos' ? c.contratosFechados * 1000 + c.fechamentoEmAndamento
      : ordem === 'visitas' ? c.visitasPedidas * 1000 + c.visitasRealizadas
      : ordem === 'interacoes' ? c.mensagensDele + c.mensagensNossas
      : ordem === 'recentes' ? (c.ultimaMensagem ? Date.parse(c.ultimaMensagem) : 0)
      : c.nome.toLowerCase()
    return f.sort((a, b) => {
      const va = valor(a), vb = valor(b)
      if (ordem === 'nome') return String(va).localeCompare(String(vb), 'pt-BR')
      return (vb as number) - (va as number)
    })
  }, [lista, busca, ordem, filtro])

  // o pódio sai da nota, e só quando há o que medir
  const podio = useMemo(() => {
    const ranking = [...(lista || [])].filter((c) => nota(c) > 0).sort((a, b) => nota(b) - nota(a)).slice(0, 3)
    return new Map(ranking.map((c, i) => [c.leadId, i + 1]))
  }, [lista])

  const totais = useMemo(() => (lista || []).reduce((s, c) => ({
    interacoes: s.interacoes + c.mensagensDele + c.mensagensNossas,
    visitas: s.visitas + c.visitasPedidas,
    contratos: s.contratos + c.contratosFechados,
  }), { interacoes: 0, visitas: 0, contratos: 0 }), [lista])

  return (
    <div className="max-w-7xl mx-auto px-4 py-6 space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-ink flex items-center gap-2"><IdentificationBadge size={26} /> Corretores</h1>
          <p className="text-sm text-muted mt-1">
            Os corretores parceiros e o que cada um fez no período: conversas, visitas agendadas e contratos fechados.
          </p>
        </div>
        <div className="flex items-center gap-1 rounded-lg border border-line bg-panel p-0.5">
          {PERIODOS.map(([d, r]) => (
            <button key={d} type="button" onClick={() => setDias(d)}
                    className={`px-3 py-1.5 text-sm rounded-md ${dias === d ? 'bg-accent text-white' : 'text-muted hover:text-ink'}`}>
              {r}
            </button>
          ))}
        </div>
      </div>

      {lista && (
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <Metrica icone={IdentificationBadge} valor={lista.length} rotulo="Corretores" />
          <Metrica icone={ChatCircleText} valor={totais.interacoes} rotulo="Interações" />
          <Metrica icone={CalendarCheck} valor={totais.visitas} rotulo="Visitas agendadas" />
          <Metrica icone={Handshake} valor={totais.contratos} rotulo="Contratos fechados" />
        </div>
      )}

      <div className="flex flex-wrap items-center gap-2">
        <label className="flex items-center gap-2 rounded-lg border border-line bg-panel px-3 py-2 flex-1 min-w-[220px]">
          <MagnifyingGlass size={16} className="text-muted" />
          <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar por nome, CRECI ou número"
                 className="bg-transparent outline-none text-sm text-ink flex-1 min-w-0" />
        </label>
        <select value={ordem} onChange={(e) => setOrdem(e.target.value as Ordem)}
                className="rounded-lg border border-line bg-panel px-3 py-2 text-sm text-ink" aria-label="Ordenar">
          {ORDENS.map(([k, r]) => <option key={k} value={k}>{r}</option>)}
        </select>
        <div className="flex flex-wrap gap-1">
          {FILTROS.map(([k, r]) => (
            <button key={k} type="button" onClick={() => setFiltro(k)}
                    className={`px-3 py-1.5 text-sm rounded-full border ${filtro === k ? 'border-accent bg-accent/10 text-ink' : 'border-line text-muted hover:text-ink'}`}>
              {r}
            </button>
          ))}
        </div>
      </div>

      {erro && <p className="text-sm text-red-500">{erro}</p>}
      {!lista && !erro && (
        <p className="text-sm text-muted flex items-center gap-2"><CircleNotch size={16} className="animate-spin" /> Carregando os corretores…</p>
      )}
      {lista && cartoes.length === 0 && <p className="text-sm text-muted">Nenhum corretor com esse filtro.</p>}

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
        {cartoes.map((c) => {
          const lugar = podio.get(c.leadId)
          return (
            <Link key={c.leadId} href={linkDaConversa(c.leadId).replace('/chat?', '/chat/parceria?')}
                  className="rounded-xl border border-line bg-panel p-3.5 hover:border-accent/60 hover:shadow-sm transition flex flex-col gap-3"
                  title="Abrir a conversa">
              <div className="flex items-center gap-3 min-w-0">
                {c.avatar
                  ? <img src={c.avatar} alt="" className="w-11 h-11 rounded-full object-cover flex-shrink-0" />
                  : <span className="w-11 h-11 rounded-full bg-accent/15 text-accent font-bold flex items-center justify-center flex-shrink-0">{iniciais(c.nome)}</span>}
                <div className="min-w-0 flex-1">
                  <div className="font-semibold text-ink truncate flex items-center gap-1.5">
                    {c.nome}
                    {lugar && (
                      <span title={`${lugar}º melhor no período`}
                            className={`inline-flex items-center gap-0.5 text-[11px] font-bold px-1.5 rounded-full ${lugar === 1 ? 'bg-amber-400/20 text-amber-600' : lugar === 2 ? 'bg-slate-400/20 text-slate-500' : 'bg-orange-400/20 text-orange-600'}`}>
                        <Trophy size={11} weight="fill" /> {lugar}º
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-2 flex-wrap">
                    {c.creci && <span className="text-xs text-muted">CRECI {c.creci}</span>}
                    <CopiarNumero telefone={c.telefone} />
                  </div>
                </div>
              </div>
              <div className="grid grid-cols-3 gap-2">
                <Metrica icone={ChatCircleText} valor={c.mensagensDele + c.mensagensNossas} rotulo="Interações"
                         detalhe={`dele ${c.mensagensDele} · nossas ${c.mensagensNossas}`} />
                <Metrica icone={CalendarCheck} valor={c.visitasPedidas} rotulo="Visitas"
                         detalhe={`${c.visitasRealizadas} realizada${c.visitasRealizadas === 1 ? '' : 's'}`} />
                <Metrica icone={Handshake} valor={c.contratosFechados} rotulo="Contratos"
                         detalhe={c.fechamentoEmAndamento ? `${c.fechamentoEmAndamento} em andamento` : 'fechados'} />
              </div>
              <div className="text-xs text-muted flex items-center justify-between">
                <span>{quando(c.ultimaMensagem)}</span>
                {c.visitasAbertas > 0 && <span className="text-accent font-medium">visita em aberto</span>}
              </div>
            </Link>
          )
        })}
      </div>
    </div>
  )
}
