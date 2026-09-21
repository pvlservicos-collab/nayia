'use client'

/**
 * /settings/leads — log dos leads recebidos, uma aba por fonte.
 *
 * Cada aba é uma planilha cujas colunas vêm da definição da fonte no servidor
 * (GET /api/lead-sources → src/lib/leadSources.ts), não daqui. Clicar numa linha
 * abre o detalhe com o payload inteiro.
 *
 * A barra de controles (abas, filtros, busca) é sticky: com 644 linhas, rolar
 * até o fim e ter que voltar ao topo pra trocar de filtro seria o caminho normal
 * de uso, não a exceção.
 */

import { useCallback, useEffect, useMemo, useState } from 'react'
import { MagnifyingGlass, ArrowClockwise, Table, PlugsConnected, Check } from '@phosphor-icons/react'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import SubmissionsTable from '@/components/Leads/SubmissionsTable'
import SubmissionDetail from '@/components/Leads/SubmissionDetail'
import ApiPanel from '@/components/Leads/ApiPanel'
import TabelaCadastroManual from '@/components/Pipeline/TabelaCadastroManual'
import { MOMENTOS } from '@/lib/momentos'
import type { LeadSourceKey } from '@/lib/leadSources'
import type { EtapaFiltro, LeadSourceTab, MomentoFiltro, Submission } from '@/components/Leads/types'

const PAGE_SIZE = 200

type FiltroContato = 'todos' | 'nao' | 'sim'

/** Chip "Sem momento" — o mesmo valor que a API usa. */
const SEM_MOMENTO = 'sem_momento'

/** Nome do momento pros chips: os quatro do vocabulário, mais "sem momento". */
function rotuloMomento(chave: string): { label: string; cor: string | null; descricao?: string } {
  const conhecido = MOMENTOS.find((m) => m.key === chave)
  if (conhecido) return { label: conhecido.label, cor: conhecido.cor, descricao: conhecido.descricao }
  if (chave === SEM_MOMENTO) return { label: 'Sem momento', cor: null }
  return { label: chave, cor: null }
}

export default function LeadsPage() {
  const [sources, setSources] = useState<LeadSourceTab[]>([])
  const [activeSource, setActiveSource] = useState<string | null>(null)
  const [rows, setRows] = useState<Submission[]>([])
  const [etapas, setEtapas] = useState<EtapaFiltro[]>([])
  const [contato, setContato] = useState({ contatados: 0, pendentes: 0 })
  const [total, setTotal] = useState(0)
  const [search, setSearch] = useState('')
  const [etapaFiltro, setEtapaFiltro] = useState<string | null>(null)
  const [momentos, setMomentos] = useState<MomentoFiltro[]>([])
  const [momentoFiltro, setMomentoFiltro] = useState<string | null>(null)
  /** Lead que vai entrar no pipeline — abre a tabela centralizada. */
  const [aoPipeline, setAoPipeline] = useState<Submission | null>(null)
  const [contatoFiltro, setContatoFiltro] = useState<FiltroContato>('todos')
  const [loadingSources, setLoadingSources] = useState(true)
  const [loadingRows, setLoadingRows] = useState(false)
  const [selected, setSelected] = useState<Submission | null>(null)
  const [showApiPanel, setShowApiPanel] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const res = await fetch('/api/lead-sources')
        const json = await res.json()
        if (cancelled) return
        const data: LeadSourceTab[] = json.data || []
        setSources(data)
        setActiveSource((current) => current ?? data[0]?.key ?? null)
      } catch {
        if (!cancelled) setError('Não foi possível carregar as fontes de lead.')
      } finally {
        if (!cancelled) setLoadingSources(false)
      }
    })()
    return () => { cancelled = true }
  }, [])

  const loadRows = useCallback(
    async (source: string, q: string, etapa: string | null, cont: FiltroContato, momento: string | null) => {
      setLoadingRows(true)
      setError(null)
      try {
        const params = new URLSearchParams({ limit: String(PAGE_SIZE) })
        if (q) params.set('q', q)
        if (etapa) params.set('stage', etapa)
        if (momento) params.set('momento', momento)
        if (cont !== 'todos') params.set('contatados', cont)
        const res = await fetch(`/api/lead-sources/${source}/submissions?${params}`)
        const json = await res.json()
        if (!res.ok) throw new Error(json.error || 'Falha ao carregar os leads.')
        setRows(json.data || [])
        setTotal(json.total ?? 0)
        setEtapas(json.etapas || [])
        setMomentos(json.momentos || [])
        setContato(json.contato || { contatados: 0, pendentes: 0 })
      } catch (err: any) {
        setError(err.message || 'Falha ao carregar os leads.')
        setRows([])
        setTotal(0)
      } finally {
        setLoadingRows(false)
      }
    },
    []
  )

  // Busca com atraso: digitar não dispara uma requisição por tecla.
  useEffect(() => {
    if (!activeSource) return
    const timer = setTimeout(
      () => { loadRows(activeSource, search.trim(), etapaFiltro, contatoFiltro, momentoFiltro) },
      search ? 300 : 0
    )
    return () => clearTimeout(timer)
  }, [activeSource, search, etapaFiltro, contatoFiltro, momentoFiltro, loadRows])

  const activeDef = useMemo(
    () => sources.find((s) => s.key === activeSource) ?? null,
    [sources, activeSource]
  )

  /**
   * Marca o contato ao abrir a conversa.
   *
   * Pinta a linha na hora e só depois grava — o clique já está navegando pro
   * chat, então esperar a resposta significaria a pessoa voltar e ver o botão
   * ainda azul. Se a gravação falhar, desfaz a pintura em vez de mentir.
   */
  const marcarContato = useCallback(
    async (row: Submission) => {
      if (!activeSource || row.contacted_at) return
      const agora = new Date().toISOString()
      setRows((prev) => prev.map((r) => (r.id === row.id ? { ...r, contacted_at: agora } : r)))
      setContato((c) => ({ contatados: c.contatados + 1, pendentes: Math.max(0, c.pendentes - 1) }))
      try {
        const res = await fetch(`/api/lead-sources/${activeSource}/submissions`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: row.id }),
        })
        if (!res.ok) throw new Error()
      } catch {
        setRows((prev) => prev.map((r) => (r.id === row.id ? { ...r, contacted_at: null } : r)))
        setContato((c) => ({ contatados: Math.max(0, c.contatados - 1), pendentes: c.pendentes + 1 }))
      }
    },
    [activeSource]
  )

  const trocarFonte = (key: string) => {
    setActiveSource(key)
    setSearch('')
    setEtapaFiltro(null)
    setMomentoFiltro(null)
    setContatoFiltro('todos')
  }

  const recarregar = useCallback(() => {
    if (activeSource) loadRows(activeSource, search.trim(), etapaFiltro, contatoFiltro, momentoFiltro)
  }, [activeSource, search, etapaFiltro, contatoFiltro, momentoFiltro, loadRows])

  if (loadingSources) {
    return (
      <div className="flex items-center justify-center py-24">
        <LoadingSpinner text="Carregando…" size="lg" />
      </div>
    )
  }

  return (
    <>
      <div className="space-y-5">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-ink">Leads</h1>
            <p className="text-sm text-muted mt-1">
              Tudo que chegou de cada fonte, do mais recente para o mais antigo.
            </p>
          </div>
          <button
            onClick={() => setShowApiPanel((v) => !v)}
            className={`btn btn-sm ${showApiPanel ? 'btn-secondary' : 'btn-outline'}`}
          >
            <PlugsConnected size={15} weight="bold" />
            {showApiPanel ? 'Ocultar integração' : 'Como enviar leads'}
          </button>
        </div>

        {showApiPanel && activeSource && (
          <ApiPanel sources={sources} activeSource={activeSource} />
        )}

        {/* Barra de controles presa no topo. top-14 = altura da navbar do app,
            senão ela encobriria a primeira linha ao rolar. */}
        <div className="sticky top-14 z-30 -mx-2 px-2 py-3 glass-raised rounded-2xl space-y-3">
          {/* Fontes */}
          <div className="flex items-center gap-2 overflow-x-auto scrollbar-hide">
            {sources.map((source) => (
              <button
                key={source.key}
                onClick={() => trocarFonte(source.key)}
                className={`pill flex-shrink-0 !px-4 !py-2 !text-sm ${
                  source.key === activeSource ? 'pill-active' : ''
                }`}
              >
                <Table size={15} weight="bold" />
                {source.label}
                <span
                  className={`ml-0.5 px-1.5 rounded-full text-[10px] font-bold ${
                    source.key === activeSource ? 'bg-black/30 text-ink' : 'bg-white/10 text-muted'
                  }`}
                >
                  {source.total}
                </span>
              </button>
            ))}
          </div>

          <div className="h-px hairline-x" />

          {/* Etapas — cada chip já traz quantos leads estão nela */}
          {etapas.length > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-[10px] font-bold uppercase tracking-wider text-muted mr-1">
                Etapa
              </span>
              <button
                onClick={() => setEtapaFiltro(null)}
                className={`pill !py-1 ${etapaFiltro === null ? 'pill-active' : ''}`}
              >
                Todas
                <span className="ml-1 px-1.5 rounded-full bg-white/10 text-[10px] font-bold">
                  {etapas.reduce((a, e) => a + e.total, 0)}
                </span>
              </button>
              {etapas.map((etapa) => (
                <button
                  key={etapa.id}
                  onClick={() => setEtapaFiltro(etapaFiltro === etapa.id ? null : etapa.id)}
                  className={`pill !py-1 ${etapaFiltro === etapa.id ? 'pill-active' : ''}`}
                >
                  {etapa.color && (
                    <span
                      className="w-2 h-2 rounded-full flex-shrink-0"
                      style={{ backgroundColor: etapa.color }}
                    />
                  )}
                  {etapa.name}
                  <span className="ml-1 px-1.5 rounded-full bg-white/10 text-[10px] font-bold">
                    {etapa.total}
                  </span>
                </button>
              ))}
            </div>
          )}

          {/* Momento da jornada — de onde a pessoa parou na Agenda (ver
              src/lib/momentos.ts). Só aparece quando a fonte tem essa
              informação; o site, por exemplo, não tem. */}
          {momentos.some((m) => m.key !== SEM_MOMENTO) && (
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-[10px] font-bold uppercase tracking-wider text-muted mr-1">
                Momento
              </span>
              <button
                onClick={() => setMomentoFiltro(null)}
                className={`pill !py-1 ${momentoFiltro === null ? 'pill-active' : ''}`}
              >
                Todos
                <span className="ml-1 px-1.5 rounded-full bg-white/10 text-[10px] font-bold">
                  {momentos.reduce((a, m) => a + m.total, 0)}
                </span>
              </button>
              {momentos.map((m) => {
                const info = rotuloMomento(m.key)
                return (
                  <button
                    key={m.key}
                    onClick={() => setMomentoFiltro(momentoFiltro === m.key ? null : m.key)}
                    className={`pill !py-1 ${momentoFiltro === m.key ? 'pill-active' : ''}`}
                    title={info.descricao}
                  >
                    {info.cor && (
                      <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ backgroundColor: info.cor }} />
                    )}
                    {info.label}
                    <span className="ml-1 px-1.5 rounded-full bg-white/10 text-[10px] font-bold">{m.total}</span>
                  </button>
                )
              })}
            </div>
          )}

          {/* Contato + busca */}
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-[10px] font-bold uppercase tracking-wider text-muted mr-1">
              Contato
            </span>
            {([
              ['todos', 'Todos', contato.contatados + contato.pendentes],
              ['nao', 'A contatar', contato.pendentes],
              ['sim', 'Já contatados', contato.contatados],
            ] as [FiltroContato, string, number][]).map(([valor, rotulo, qtd]) => (
              <button
                key={valor}
                onClick={() => setContatoFiltro(valor)}
                className={`pill !py-1 ${contatoFiltro === valor ? 'pill-active' : ''}`}
              >
                {valor === 'sim' && <Check size={12} weight="bold" />}
                {rotulo}
                <span className="ml-1 px-1.5 rounded-full bg-white/10 text-[10px] font-bold">{qtd}</span>
              </button>
            ))}

            <div className="relative ml-auto">
              <MagnifyingGlass
                size={15}
                className="absolute left-3 top-1/2 -translate-y-1/2 text-muted pointer-events-none"
              />
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Buscar nome, telefone, e-mail…"
                className="field !pl-9 !py-1.5 !text-xs w-[240px]"
              />
            </div>
            <button
              onClick={recarregar}
              className="btn-icon w-8 h-8"
              title="Atualizar"
            >
              <ArrowClockwise size={15} weight="bold" />
            </button>
          </div>
        </div>

        {activeDef && (
          <p className="text-xs text-muted">
            {activeDef.description}
            {activeDef.last_received_at && (
              <span className="text-muted/70">
                {' '}· último recebido em {new Date(activeDef.last_received_at).toLocaleString('pt-BR')}
              </span>
            )}
          </p>
        )}

        {error && (
          <div className="glass rounded-xl border-red-500/30 px-4 py-3">
            <p className="text-sm text-red-300">{error}</p>
          </div>
        )}

        {loadingRows ? (
          <div className="flex items-center justify-center py-20">
            <LoadingSpinner text="Carregando leads…" />
          </div>
        ) : rows.length === 0 ? (
          <div className="glass rounded-2xl px-6 py-16 text-center">
            <p className="text-sm font-semibold text-ink">
              {search || etapaFiltro || momentoFiltro || contatoFiltro !== 'todos'
                ? 'Nenhum lead com esses filtros.'
                : 'Nenhum lead recebido ainda.'}
            </p>
            {!search && !etapaFiltro && !momentoFiltro && contatoFiltro === 'todos' && (
              <p className="text-xs text-muted mt-1.5">
                Assim que a fonte começar a enviar, os leads aparecem aqui.{' '}
                <button
                  onClick={() => setShowApiPanel(true)}
                  className="text-accent-2 hover:underline"
                >
                  Ver como enviar
                </button>
              </p>
            )}
          </div>
        ) : (
          <>
            {activeDef && (
              <SubmissionsTable
                columns={activeDef.columns}
                rows={rows}
                onSelect={setSelected}
                onContatar={marcarContato}
                onAdicionarAoPipeline={setAoPipeline}
              />
            )}
            <p className="text-[11px] text-muted text-center">
              Mostrando {rows.length} de {total}
              {total > rows.length && ' — refine com os filtros ou a busca para ver os demais'}
            </p>
          </>
        )}
      </div>

      {aoPipeline && activeSource && (
        <TabelaCadastroManual
          source={activeSource as LeadSourceKey}
          modo="pipeline"
          linhasIniciais={[
            {
              nome: aoPipeline.name ?? '',
              whatsapp: aoPipeline.phone ?? '',
              momento: momentoDaLinha(aoPipeline),
              leadId: aoPipeline.lead_id ?? undefined,
            },
          ]}
          onClose={() => setAoPipeline(null)}
          onCreated={recarregar}
        />
      )}

      {selected && activeSource && (
        <SubmissionDetail
          submission={selected}
          sourceKey={activeSource}
          onClose={() => setSelected(null)}
        />
      )}
    </>
  )
}

/**
 * Momento que a lista já conhece daquele lead.
 *
 * Vem do payload da própria submissão (é o que a tela mostra); a Agenda manda
 * em `agenda.phase`, a planilha antiga em `fase`.
 */
function momentoDaLinha(row: Submission): string | null {
  const payload = (row.payload ?? {}) as Record<string, any>
  const agenda = (payload.agenda ?? {}) as Record<string, any>
  const valor = agenda.phase ?? payload.fase ?? payload.phase
  return typeof valor === 'string' && valor ? valor : null
}
