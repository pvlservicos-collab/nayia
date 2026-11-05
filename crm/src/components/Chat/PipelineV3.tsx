'use client'

/**
 * O PIPELINE DA V3 (Pedro, 05/11/2026: "a pipeline do v3 precisa ser refeita, não é pra ter 3 números e sim uma pipeline de
 * atendimento e os outros só aparecem se marcar igual o proprietários, e as etapas de atendimento são as da Nay").
 *
 *   o quadro    um funil só, o de Atendimento: as colunas são as etapas da Nay Leads (lib/olxClientes.ts ETAPAS_OLX, mais
 *               "Chegou agora" de quem ela ainda não começou); entram os leads (locação e venda) que a v3 mostra
 *   arrastar    soltar o card noutra coluna muda a etapa da Nay (/api/captacao/olx-clientes), como a barra de etapas da
 *               conversa, com o Desfazer do aviso
 *   os números  o funil de cada número (Oficial, Parceria, Leads) fica escondido: marcar a caixinha mostra aquele, desmarcar
 *               volta ao de Atendimento (o mesmo jeito da caixinha Proprietários do quadro antigo)
 */
import { useMemo, useState } from 'react'
import { CalendarBlank, CircleNotch, MagnifyingGlass, Warning, X } from '@phosphor-icons/react'
import { casaNaBusca } from './BuscaDaLista'
import { useVisitasParceria } from '@/hooks/useVisitasParceria'
import { organizar } from './OrganizarConversa'
import AgendarVisita from './AgendarVisita'
import type { VisitaNaTela } from '@/lib/tiposNay'
import type { LeadWithOwner } from '@/lib/types'
import { ETAPAS_OLX } from '@/lib/olxClientes'
import { mudarEtapaOlx } from '@/hooks/useOlxClientes'
import { NOME_DA_ETAPA } from '@/lib/modoV3'
import { formatPhone } from '@/lib/utils'
import { quandoCurtoEmManaus } from '@/lib/fusoDeManaus'
import PipelineBoard from '@/components/Pipeline/PipelineBoard'

type Linha = 'oficial' | 'parceria' | 'captacao'
const FUNIS: Array<{ linha: Linha; rotulo: string }> = [
  { linha: 'captacao', rotulo: 'Funil Leads' }, { linha: 'parceria', rotulo: 'Funil Parceria' }, { linha: 'oficial', rotulo: 'Funil Oficial' },
]
const COLUNAS: Array<{ chave: string; rotulo: string; cor: string; titulo: string }> = [
  { chave: 'nova', rotulo: 'Chegou agora', cor: '#94a3b8', titulo: 'A Nay ainda não começou o atendimento' },
  ...ETAPAS_OLX.map((e) => ({ chave: e.chave as string, rotulo: e.rotulo, cor: e.cor, titulo: e.titulo })),
]
const COR_DO_SELO = { ia: '#7c3aed', humano: '#16a34a', parada: '#888780' } as const

export interface CardDoPipeline { cor: string; tipo: string; responde: { tipo: 'ia' | 'humano' | 'parada'; nome: string } }

export default function PipelineV3({ organizationId, linhas, leads, etapaDe, cardDe, comAEquipe, aoAbrir, avisar }: {
  organizationId: string | null
  /** os funis de número que este login pode marcar (o SDR só os números dele, como na v2) */
  linhas: Linha[]
  /** os leads que a v3 mostra (já com o recorte do SDR) */
  leads: LeadWithOwner[]
  /** a etapa da Nay; null = não é lead (corretor, proprietário): fica fora do quadro */
  etapaDe: (l: LeadWithOwner) => string | null
  cardDe: (l: LeadWithOwner) => CardDoPipeline
  /** a equipe está com a conversa (aí mudar a etapa também solta a Nay, como na barra de etapas) */
  comAEquipe: (l: LeadWithOwner) => boolean
  aoAbrir: (leadId: string) => void
  avisar: (texto: string, desfazer?: () => Promise<void>) => void
}) {
  const [funil, setFunil] = useState<Linha | null>(null)
  const [arrastando, setArrastando] = useState<string | null>(null)
  const [sobre, setSobre] = useState<string | null>(null)
  const [salvando, setSalvando] = useState<string | null>(null)
  // o que acabou de ser arrastado vale na hora, até a leitura da Nay confirmar
  const [movidos, setMovidos] = useState<Record<string, string>>({})
  // 05/11 (Pedro: "põe uma lupa lá no pipeline para buscar leads por lá"): nome ou número, a mesma busca da lista
  const [busca, setBusca] = useState('')
  /* PARA VISITA SÓ COM A VISITA (05/11, Pedro: "no pipeline não posso mover um contato para visita sem selecionar a visita,
     aparece um popup Cuidado, para mover o contato selecione ou crie uma nova"): soltar em Visita abre o aviso; escolhida
     (ou criada) a visita, a conversa entra no card dela (organizar visita.ligar) e só então a etapa da Nay vira Visita */
  const [paraVisita, setParaVisita] = useState<LeadWithOwner | null>(null)

  const porColuna = useMemo(() => {
    const m = new Map<string, LeadWithOwner[]>(COLUNAS.map((c) => [c.chave, []]))
    for (const l of leads) {
      if (l.is_archived || (busca.trim() && !casaNaBusca(busca, l))) continue
      const e = movidos[l.id] || etapaDe(l)
      if (!e) continue
      ;(m.get(e) || m.get('nova')!).push(l)
    }
    return m
  }, [leads, etapaDe, movidos, busca])
  const total = Array.from(porColuna.values()).reduce((n, c) => n + c.length, 0)

  const mover = async (l: LeadWithOwner, para: string) => {
    const de = movidos[l.id] || etapaDe(l)
    if (!de || de === para || para === 'nova' || salvando) return
    setSalvando(l.id)
    setMovidos((m) => ({ ...m, [l.id]: para }))
    const erro = await mudarEtapaOlx(l.phone || '', para as any)
    if (!erro && comAEquipe(l)) {
      await fetch(`/api/leads/${l.id}/captacao-etapa`, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ etapa: 'todos' }),
      }).catch(() => undefined)
    }
    setSalvando(null)
    if (erro) {
      setMovidos((m) => { const n = { ...m }; delete n[l.id]; return n })
      window.alert(`Não mudou a etapa: ${erro}`)
      return
    }
    const voltaPara = de !== 'nova' ? de : null
    avisar(`Etapa alterada para ${NOME_DA_ETAPA[para] || para}`, voltaPara ? async () => {
      setMovidos((m) => ({ ...m, [l.id]: voltaPara }))
      const e = await mudarEtapaOlx(l.phone || '', voltaPara as any)
      if (e) throw new Error(e)
    } : undefined)
  }

  const caixinha = (f: { linha: Linha; rotulo: string }) => (
    <label key={f.linha} className="inline-flex items-center gap-1.5 text-[13px] cursor-pointer select-none" style={{ color: 'var(--wa-text)' }}>
      <input type="checkbox" checked={funil === f.linha} onChange={(e) => setFunil(e.target.checked ? f.linha : null)} />
      {f.rotulo}
    </label>
  )

  return (
    <div className="flex-1 min-w-0 min-h-0 flex flex-col">
      <div className="flex-shrink-0 flex flex-wrap items-center gap-x-4 gap-y-1.5 px-4 py-2" style={{ background: 'var(--wa-panel)', borderBottom: '1px solid var(--wa-divider)' }}>
        <span className="text-[15px] font-semibold" style={{ color: 'var(--wa-text)' }}>
          {funil ? FUNIS.find((f) => f.linha === funil)?.rotulo : 'Pipeline de atendimento'}
        </span>
        {!funil && <span className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>As etapas da Nay · {total} {total === 1 ? 'lead' : 'leads'}{busca.trim() ? ' com essa busca' : ''} · arraste o card para mudar a etapa</span>}
        {!funil && (
          <label className="wa-busca !h-8 w-full sm:w-[260px]">
            <MagnifyingGlass size={16} />
            <input value={busca} onChange={(e) => setBusca(e.target.value)} placeholder="Buscar lead (nome ou número)" aria-label="Buscar lead no pipeline"
                   onKeyDown={(e) => { if (e.key === 'Escape') setBusca('') }} />
            {busca && <button type="button" onClick={() => setBusca('')} aria-label="Limpar a busca"><X size={14} /></button>}
          </label>
        )}
        <span className="ml-auto flex flex-wrap items-center gap-3">{FUNIS.filter((f) => linhas.includes(f.linha)).map(caixinha)}</span>
      </div>

      {funil ? (
        <div className="pipeline-no-chat flex-1 min-w-0 min-h-0 flex flex-col">
          {organizationId && <PipelineBoard key={funil} organizationId={organizationId} linha={funil} />}
        </div>
      ) : (
        <div className="flex-1 min-h-0 overflow-x-auto overflow-y-hidden wa-rolagem" style={{ background: 'var(--wa-app)' }}>
          <div className="h-full flex gap-2.5 p-2.5" style={{ minWidth: 'max-content' }}>
            {COLUNAS.map((c) => {
              const dela = porColuna.get(c.chave) || []
              const alvo = sobre === c.chave && arrastando && c.chave !== 'nova'
              return (
                <section key={c.chave} className="w-[250px] flex-shrink-0 h-full flex flex-col rounded-xl"
                         style={{ background: 'var(--wa-panel)', outline: alvo ? `2px solid ${c.cor}` : 'none' }}
                         onDragOver={(e) => { if (c.chave !== 'nova') { e.preventDefault(); setSobre(c.chave) } }}
                         onDragLeave={() => setSobre((s) => (s === c.chave ? null : s))}
                         onDrop={(e) => {
                           e.preventDefault(); setSobre(null)
                           const l = leads.find((x) => x.id === e.dataTransfer.getData('text/plain'))
                           if (!l || (movidos[l.id] || etapaDe(l)) === c.chave) return
                           if (c.chave === 'visita') setParaVisita(l)
                           else void mover(l, c.chave)
                         }}>
                  <header className="flex-shrink-0 px-3 pt-2.5 pb-2" title={c.titulo}>
                    <span className="block h-[4px] rounded-full mb-2" style={{ background: c.cor }} />
                    <span className="flex items-center gap-2 text-[13.5px] font-semibold" style={{ color: 'var(--wa-text)' }}>
                      {c.rotulo}<span className="ml-auto text-[12px] font-normal" style={{ color: 'var(--wa-text-2)' }}>{dela.length}</span>
                    </span>
                  </header>
                  <div className="flex-1 min-h-0 overflow-y-auto wa-rolagem px-2 pb-2 flex flex-col gap-1.5">
                    {dela.map((l) => {
                      const k = cardDe(l)
                      return (
                        <button key={l.id} type="button" draggable onClick={() => aoAbrir(l.id)}
                                onDragStart={(e) => { e.dataTransfer.setData('text/plain', l.id); setArrastando(l.id) }}
                                onDragEnd={() => { setArrastando(null); setSobre(null) }}
                                className="w-full text-left rounded-lg px-2.5 py-2 flex flex-col gap-1"
                                style={{ background: 'var(--wa-app)', boxShadow: `inset 3px 0 0 ${k.cor}`, opacity: arrastando === l.id ? 0.5 : 1 }}
                                title="Abrir a conversa (arraste para mudar a etapa)">
                          <span className="flex items-center gap-1.5 min-w-0">
                            <span className="truncate text-[13.5px] font-medium" style={{ color: 'var(--wa-text)' }}>{formatPhone(l.title || l.phone || '')}</span>
                            {salvando === l.id && <CircleNotch size={12} className="animate-spin flex-shrink-0" />}
                            <span className="ml-auto text-[11px] flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}>
                              {quandoCurtoEmManaus(l.last_activity_at || l.created_at)}
                            </span>
                          </span>
                          <span className="flex items-center gap-1.5 text-[11.5px]">
                            <span className="rounded px-1 font-semibold text-white" style={{ background: k.cor }}>{k.tipo}</span>
                            <span className="ml-auto font-semibold" style={{ color: COR_DO_SELO[k.responde.tipo] }}>{k.responde.nome}</span>
                          </span>
                        </button>
                      )
                    })}
                  </div>
                </section>
              )
            })}
          </div>
        </div>
      )}
      {paraVisita && (
        <EscolherAVisita lead={paraVisita} aoFechar={() => setParaVisita(null)}
                         aoEscolher={() => { const l = paraVisita; setParaVisita(null); void mover(l, 'visita') }} />
      )}
    </div>
  )
}

const quandoDaVisita = (v: VisitaNaTela) => {
  const q = v.quando || v.quandoSugerido
  return q ? new Date(q).toLocaleString('pt-BR', { timeZone: 'America/Manaus', weekday: 'short', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })
    : 'sem horário'
}
const FIM_DA_VISITA = ['realizada', 'encerrada', 'cancelada', 'expirada']

/** o aviso "Cuidado": escolher uma visita aberta para este contato, ou criar uma nova */
function EscolherAVisita({ lead, aoFechar, aoEscolher }: { lead: LeadWithOwner; aoFechar: () => void; aoEscolher: () => void }) {
  const { visitas, carregando } = useVisitasParceria(true, 2)
  const [criando, setCriando] = useState(false)
  const [ligando, setLigando] = useState<number | null>(null)
  const [erro, setErro] = useState('')
  const abertas = visitas.filter((v) => v.aberta && !FIM_DA_VISITA.includes(v.estado))
    .sort((a, b) => new Date(a.quando || a.quandoSugerido || 0).getTime() - new Date(b.quando || b.quandoSugerido || 0).getTime())
  const ligar = async (v: VisitaNaTela) => {
    setLigando(v.id); setErro('')
    try { await organizar(lead.id, { visita: { id: v.id, ligar: true } }); aoEscolher() }
    catch (e: any) { setErro(e?.message || 'Não consegui ligar o contato à visita.'); setLigando(null) }
  }
  const nome = formatPhone(lead.title || lead.phone || '')
  return (
    <div className="fixed inset-0 z-[70] flex items-center justify-center p-4" style={{ background: 'rgba(0,0,0,0.45)' }} onMouseDown={aoFechar}>
      <div role="dialog" aria-label="Escolher a visita" onMouseDown={(e) => e.stopPropagation()}
           className="chat-theme w-full max-w-[480px] max-h-[88vh] flex flex-col rounded-2xl shadow-2xl overflow-hidden"
           style={{ background: 'var(--wa-panel)', color: 'var(--wa-text)', border: '2px solid #d97706' }}>
        <div className="px-4 py-3 flex items-start gap-2" style={{ background: 'color-mix(in srgb, #d97706 14%, transparent)' }}>
          <Warning size={22} weight="fill" style={{ color: '#d97706' }} className="flex-shrink-0 mt-0.5" />
          <div className="flex-1">
            <div className="text-[16px] font-bold">Cuidado</div>
            <div className="text-[13px]">Para mover {nome} para Visita, selecione a visita dele ou crie uma nova.</div>
          </div>
          <button type="button" onClick={aoFechar} className="wa-icone-btn" aria-label="Fechar"><X size={18} /></button>
        </div>
        <div className="p-3 flex flex-col gap-2 min-h-0 overflow-y-auto">
          {criando ? (
            <AgendarVisita leadDaConversa={lead.id} aoCancelar={() => setCriando(false)} aoAgendar={() => aoEscolher()} />
          ) : (
            <>
              <button type="button" onClick={() => setCriando(true)}
                      className="h-9 rounded-lg text-[13.5px] font-semibold text-white flex items-center justify-center gap-1.5" style={{ background: '#2563eb' }}>
                <CalendarBlank size={16} weight="bold" /> Criar uma nova visita
              </button>
              <div className="text-[12px] font-semibold mt-1" style={{ color: 'var(--wa-text-2)' }}>ou escolha uma visita aberta</div>
              {carregando && !visitas.length && <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Carregando as visitas…</p>}
              {!carregando && !abertas.length && <p className="text-[13px]" style={{ color: 'var(--wa-text-2)' }}>Nenhuma visita aberta agora.</p>}
              {abertas.map((v) => (
                <button key={v.id} type="button" disabled={ligando !== null} onClick={() => void ligar(v)}
                        className="w-full text-left rounded-lg px-3 py-2 flex flex-col gap-0.5 disabled:opacity-60"
                        style={{ background: 'var(--wa-app)', border: '1px solid var(--wa-divider)' }}>
                  <span className="flex items-center gap-1.5 text-[13.5px] font-semibold">
                    {ligando === v.id && <CircleNotch size={13} className="animate-spin" />}
                    {quandoDaVisita(v)} · {[v.imovel, v.codigo ? `#${v.codigo}` : null].filter(Boolean).join(' ') || 'imóvel'}
                  </span>
                  <span className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>
                    {[v.clienteNome || v.visitanteNome, v.corretorNome && `corretor ${v.corretorNome}`, v.proprietarioNome && `dono ${v.proprietarioNome}`]
                      .filter(Boolean).join(' · ') || (v.linha === 'leads' ? 'Nay Leads' : 'Parceria')}
                  </span>
                </button>
              ))}
              {erro && <p className="text-[13px]" style={{ color: '#dc2626' }}>{erro}</p>}
            </>
          )}
        </div>
      </div>
    </div>
  )
}
