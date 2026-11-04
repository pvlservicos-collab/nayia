'use client'

/**
 * O ATENDIMENTO DA V3 (Pedro, 04/11/2026): um WhatsApp só juntando Leads (8595) e Parceria (9445), em filas e etapas.
 * O pedido do desenho ("deixar fácil identificar de qual fila é o contato e quem está respondendo agora, removendo
 * informação repetida; não mude a lógica de negócio nem remova funcionalidades; só reorganize a interface"):
 *
 *   filtros     Todas / Locação (Diego) / Venda (Rayssa) / Corretores (Nay), com a bolinha da cor da fila
 *   card        3 linhas: nome e hora; a prévia; a barrinha das etapas (60 px), o nome da etapa e o selo de quem
 *               responde (IA roxo, a pessoa verde). O avatar tem o anel da cor da fila. Sem etiquetas (as anotações ficam
 *               no card do contato, à direita); o alfinete só se a conversa estiver fixada
 *   cabeçalho   anel no avatar; o nome e a pílula do tipo (Lead locação / Lead venda / Corretor); embaixo o telefone e o
 *               resumo da ficha (o pedido de agora da Nay: quartos, teto, bairros; do corretor, o CRECI); os botões de sempre
 *   etapas      a barra das 5 etapas embaixo do cabeçalho; clicar muda a etapa à mão (custom_attributes.etapa_v3, rota
 *               organizar); clicar na etapa escolhida à mão volta ao automático
 *   balões      IA roxo com o robô, humano verde com a pessoa (ou o celular): ActivityTimeline no modo v3
 *   quem responde  UMA barra em cima da caixa de mensagem: "IA respondendo · sai pelo Leads 8595" com Assumir, ou
 *               "Fulano está respondendo" com Devolver à IA (no lugar do "Sai pelo..." e do Pausar IA)
 *
 * A lógica é a de sempre: cada conversa é da linha dela (crm/CLAUDE.md) e a resposta sai pelo número dela; a Nay que atende
 * segue a origem. Assumir e Devolver usam o que já existe: no Leads a etapa manual da captação (com_o_tel cala a Nay Leads,
 * todos a solta: crm_captacao_etapa_manual, 398); na Parceria o Parar Nay / Nay voltar (crm_nay_parar / crm_nay_voltar). Os
 * dois também gravam quem assumiu (responsavel_v2, a regra da v2).
 *
 * AS ETAPAS AUTOMÁTICAS saem do passo da Nay Leads (520): Começar (perguntando o perfil), Filtrado (busca feita), Em
 * atendimento (imóveis enviados), Enviado opção (pediu visita), Visitas (confirmada, ou na etapa Visita). Na Parceria:
 * Visitas ou Em atendimento.
 */
import { useCallback, useEffect, useMemo, useState } from 'react'
import { CircleNotch, PushPin, Robot, User } from '@phosphor-icons/react'
import { useAuth, useOrganizationMembers } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import { useFechamentoV2 } from '@/hooks/useFechamentoV2'
import { useCorretoresDaCaptacao } from '@/hooks/useCorretoresDaCaptacao'
import { useOlxClientes } from '@/hooks/useOlxClientes'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useEquipeV2 } from '@/hooks/useEquipeV2'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { fim8 } from '@/lib/olxClientes'
import { etapaDaParceria } from '@/lib/etapaDaParceria'
import { tipoEscolhido } from '@/lib/organizacaoDoLead'
import { montarAtendentes } from '@/lib/atendentes'
import { primeiroNome, responsavelV2, usePapelV2 } from '@/lib/versaoDoCrm'
import { ModoV3, FILAS_V3, ETAPAS_V3, CLASSE_DO_AUTOR, type FilaV3 } from '@/lib/modoV3'
import { formatPhone } from '@/lib/utils'
import type { LeadWithOwner } from '@/lib/types'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import ChatJuntado from './ChatJuntado'
import OrganizarConversa, { EnviarParaDaParceria, organizar, type Organizado } from './OrganizarConversa'

const CINZA = '#888780'
const NUMERO: Record<string, string> = { captacao: 'Leads 8595', parceria: 'Parceria 9445' }
type Responde = { tipo: 'ia' | 'humano'; nome: string }

/** o login Tel (administrador de verdade): a v3 é só dele, por enquanto */
export function useEhTel(): boolean {
  const { profileName, user } = useAuth()
  const papel = usePapelV2()
  return papel.adminDeVerdade && primeiroNome(profileName || user?.name) === 'pedro'
}

const iniciais = (t: string) => t.trim().split(/\s+/).slice(0, 2).map((p) => p.charAt(0).toUpperCase()).join('') || '?'
const reais = (v: number) => v >= 1e6 ? `R$ ${(v / 1e6).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mi`
  : v >= 1000 ? `R$ ${(v / 1000).toLocaleString('pt-BR', { maximumFractionDigits: 1 })} mil` : `R$ ${v}`

/** a barrinha curta das etapas (card) */
function BarrinhaCurta({ atual }: { atual: number }) {
  return (
    <span className="flex items-center gap-[2px] w-[60px] flex-shrink-0">
      {ETAPAS_V3.map((e, i) => (
        <span key={e.curto} className="h-[4px] flex-1 rounded-full" style={{ background: i <= atual ? e.cor : 'var(--wa-row-selected)' }} />
      ))}
    </span>
  )
}

function Selo({ r }: { r: Responde }) {
  return (
    <span className={`${CLASSE_DO_AUTOR[r.tipo]} v3-selo flex-shrink-0 rounded-full px-1.5 text-[11px] font-medium leading-[16px]`}
          title={r.tipo === 'ia' ? 'A Nay (IA) está respondendo' : `${r.nome} está respondendo`}>{r.tipo === 'ia' ? 'IA' : r.nome}</span>
  )
}

/** o card da lista: exatamente 3 linhas */
function CardV3({ l, hora, aberta, abrir, menu, cor, etapa, r }: {
  l: LeadWithOwner; hora: string; aberta: boolean; abrir: () => void; menu: (e: React.MouseEvent) => void
  cor: string; etapa: number; r: Responde
}) {
  const nome = (l.title || '').trim() || formatPhone(l.phone || '') || 'Sem nome'
  const naoLida = !!l.is_unread
  return (
    <button type="button" data-lead-id={l.id} onClick={abrir} onContextMenu={menu}
            className="w-full flex items-center gap-3 px-3 py-2.5 text-left"
            style={{ background: aberta ? 'var(--wa-row-selected)' : undefined, borderBottom: '1px solid var(--wa-divider)' }}>
      <span className="w-11 h-11 rounded-full overflow-hidden flex-shrink-0 flex items-center justify-center text-[14px] font-medium"
            style={{ background: 'var(--wa-row-selected)', color: 'var(--wa-text-2)', boxShadow: `0 0 0 2px ${cor}` }}>
        {l.avatar_url ? <img src={l.avatar_url} alt="" className="w-full h-full object-cover" /> : iniciais(nome)}
      </span>
      <span className="flex-1 min-w-0 flex flex-col gap-[3px]">
        <span className="flex items-center gap-2">
          <span className="flex-1 truncate text-[15px]" style={{ color: 'var(--wa-text)', fontWeight: naoLida ? 600 : 400 }}>{nome}</span>
          <span className="text-[12px] flex-shrink-0" style={{ color: naoLida ? 'var(--wa-green)' : 'var(--wa-text-2)' }}>{hora}</span>
        </span>
        <span className="flex items-center gap-1.5">
          <span className="flex-1 truncate text-[13px]" style={{ color: 'var(--wa-text-2)' }}>{l.last_message_content || 'Sem mensagens'}</span>
          {l.is_pinned && <PushPin size={13} weight="fill" style={{ color: 'var(--wa-text-2)' }} aria-label="Fixada" />}
          {naoLida && <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: 'var(--wa-green)' }} aria-label="Não lida" />}
        </span>
        <span className="flex items-center gap-2">
          <BarrinhaCurta atual={etapa} />
          <span className="flex-1 truncate text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{ETAPAS_V3[etapa].rotulo}</span>
          <Selo r={r} />
        </span>
      </span>
    </button>
  )
}

/** a barra das 5 etapas embaixo do cabeçalho; cada uma é clicável (a escolhida à mão, clicada de novo, volta ao automático) */
function BarraDasEtapas({ l, atual, manual, aoMudar }: { l: LeadWithOwner; atual: number; manual: boolean; aoMudar: (o: Organizado) => void }) {
  const [salvando, setSalvando] = useState<number | null>(null)
  const escolher = async (i: number) => {
    setSalvando(i)
    try { aoMudar(await organizar(l.id, { etapaV3: manual && i === atual ? null : i })) }
    catch (e: any) { window.alert(e?.message || 'Não consegui mudar a etapa.') } finally { setSalvando(null) }
  }
  return (
    <div className="flex-shrink-0 grid grid-cols-5 gap-1.5 px-3 pt-2 pb-1.5" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
      {ETAPAS_V3.map((e, i) => (
        <button key={e.curto} type="button" onClick={() => void escolher(i)} disabled={salvando !== null}
                title={manual && i === atual ? 'Etapa escolhida à mão: clique para voltar ao automático' : `Mudar a etapa para ${e.rotulo}`}
                className="flex flex-col items-center gap-1 min-w-0 disabled:opacity-60">
          <span className="h-[5px] w-full rounded-full" style={{ background: e.cor, opacity: i <= atual ? 1 : 0.3 }} />
          <span className="text-[12px] truncate flex items-center gap-1"
                style={{ color: i === atual ? 'var(--wa-text)' : 'var(--wa-text-2)', fontWeight: i === atual ? 500 : 400 }}>
            {salvando === i && <CircleNotch size={11} className="animate-spin" />}{e.curto}{manual && i === atual ? ' · à mão' : ''}
          </span>
        </button>
      ))}
    </div>
  )
}

/** embaixo do nome no alto: o telefone e o resumo da ficha (o pedido de agora; do corretor, o CRECI) */
function SubtituloV3({ l, ehLead, creci }: { l: LeadWithOwner; ehLead: boolean; creci: string | null }) {
  const [resumo, setResumo] = useState<string | null>(null)
  useEffect(() => {
    setResumo(null)
    if (!ehLead) return
    let vivo = true
    fetch(`/api/leads/${l.id}/buscas`).then((r) => (r.ok ? r.json() : null)).then((j) => {
      const f = j?.ativa?.filtros
      if (!vivo || !f) return
      const onde = Array.isArray(f.bairros) && f.bairros.length ? f.bairros.slice(0, 2).join(', ') : f.condominio || null
      const partes = [f.quartos ? `${f.quartos} quarto${Number(f.quartos) > 1 ? 's' : ''}` : null, f.teto ? `até ${reais(Number(f.teto))}` : null, onde]
      setResumo(partes.filter(Boolean).join(' · ') || null)
    }).catch(() => undefined)
    return () => { vivo = false }
  }, [l.id, ehLead])
  const extra = ehLead ? resumo : creci ? `CRECI ${creci}` : null
  return <>{[formatPhone(l.phone || ''), extra].filter(Boolean).join(' · ')}</>
}

/** a barra de quem responde, em cima da caixa de mensagem: IA (roxo) com Assumir, ou a pessoa (verde) com Devolver à IA */
function QuemResponde({ l, r, aoMudar }: { l: LeadWithOwner; r: Responde; aoMudar: (r: Responde, o?: Organizado) => void }) {
  const { profileName, user } = useAuth()
  const [ocupado, setOcupado] = useState(false)
  const [pausa, setPausa] = useState<{ quem: string } | null>(null)
  const linha = getLinhaWhatsapp(l) || ''
  // o Leads também pausa sozinho 30 min depois que alguém da equipe escreve (pausa-da-nay): conta como a pessoa respondendo
  useEffect(() => {
    setPausa(null)
    if (linha !== 'captacao' || r.tipo === 'humano') return
    let vivo = true
    fetch(`/api/leads/${l.id}/pausa-da-nay`).then((x) => (x.ok ? x.json() : null)).then((j) => {
      if (vivo && j?.ate && Date.parse(j.ate) > Date.now()) setPausa({ quem: String(j.quem || 'Equipe').split(/\s+/)[0] })
    }).catch(() => undefined)
    return () => { vivo = false }
  }, [l.id, linha, r.tipo])
  const agora: Responde = r.tipo === 'ia' && pausa ? { tipo: 'humano', nome: pausa.quem } : r
  const eu = (() => { const p = primeiroNome(profileName || user?.name); return p ? p.charAt(0).toUpperCase() + p.slice(1) : 'Equipe' })()
  const postar = (url: string, corpo: unknown) => fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(corpo) })
    .then(async (x) => { if (!x.ok) { const j = await x.json().catch(() => ({})); throw new Error(j.error || j.message || 'Não consegui.') } })
  const assumir = async () => {
    setOcupado(true)
    try {
      await (linha === 'parceria' ? postar(`/api/leads/${l.id}/nay`, { acao: 'parar' }) : postar(`/api/leads/${l.id}/captacao-etapa`, { etapa: 'com_o_tel' }))
      aoMudar({ tipo: 'humano', nome: eu }, await organizar(l.id, { responsavel: { nome: eu } }))
    } catch (e: any) { window.alert(e?.message || 'Não consegui assumir.') } finally { setOcupado(false) }
  }
  const devolver = async () => {
    setOcupado(true)
    try {
      await (linha === 'parceria' ? postar(`/api/leads/${l.id}/nay`, { acao: 'voltar' }) : postar(`/api/leads/${l.id}/captacao-etapa`, { etapa: 'todos' }))
      setPausa(null)
      aoMudar({ tipo: 'ia', nome: 'IA' }, await organizar(l.id, { responsavel: null }))
    } catch (e: any) { window.alert(e?.message || 'Não consegui devolver à IA.') } finally { setOcupado(false) }
  }
  return (
    <div className={`${CLASSE_DO_AUTOR[agora.tipo]} v3-selo relative z-10 flex-shrink-0 mx-3 sm:mx-5 mt-1.5 px-3 h-9 rounded-lg flex items-center gap-2 text-[13px]`}>
      {agora.tipo === 'ia' ? <Robot size={16} weight="fill" /> : <User size={16} weight="fill" />}
      <span className="flex-1 truncate">
        {agora.tipo === 'ia' ? 'IA respondendo' : `${agora.nome} está respondendo`} · sai pelo {NUMERO[linha] || linha}
      </span>
      <button type="button" disabled={ocupado} onClick={() => void (agora.tipo === 'ia' ? assumir() : devolver())}
              className="flex items-center gap-1 h-7 px-2.5 rounded-md text-[12.5px] font-medium disabled:opacity-60"
              style={{ border: '1px solid currentColor' }}>
        {ocupado && <CircleNotch size={12} className="animate-spin" />}{agora.tipo === 'ia' ? 'Assumir' : 'Devolver à IA'}
      </button>
    </div>
  )
}

export default function ChatV3() {
  const { loading, organizationId } = useAuth()
  const ehTel = useEhTel()
  const { leads, setLeads } = useLeadsContext()
  const { ehProprietario, ehVisita, ehLocacao } = usePapelDoContato(true, true)
  const { emFechamento, podeVer } = useFechamentoV2()
  const corretoresDoLeads = useCorretoresDaCaptacao(true)
  const olx = useOlxClientes(true)
  const { marcas } = useParceriaMarcas(true)
  const equipeV2 = useEquipeV2(true)
  const { members } = useOrganizationMembers(organizationId || '')
  const equipe = useMemo(() => montarAtendentes(members || []), [members])
  // o que Assumir / Devolver acabou de fazer (até a próxima leitura das marcas e dos clientes confirmar)
  const [mudado, setMudado] = useState<Record<string, Responde>>({})

  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria').map((l) => fim8(l.phone)).filter(Boolean)), [leads])

  const daTela = useCallback((l: LeadWithOwner): boolean => {
    const linha = getLinhaWhatsapp(l)
    if (l.is_group || (linha !== 'captacao' && linha !== 'parceria')) return false
    if (linha === 'captacao' && pelaParceria.has(fim8(l.phone))) return false
    return podeVer(l)
  }, [pelaParceria, podeVer])

  /** a fila: Locação, Venda ou Corretores (proprietário e fechamento ficam só em Todas, com o anel cinza) */
  const filaDe = useCallback((l: LeadWithOwner): FilaV3 | null => {
    if (!daTela(l)) return null
    if (getLinhaWhatsapp(l) === 'parceria' || tipoEscolhido(l) === 'corretor' || corretoresDoLeads.has(fim8(l.phone))) return 'corretores'
    if (ehProprietario(l) || emFechamento(l)) return null
    return ehLocacao(l) ? 'locacao' : 'venda'
  }, [daTela, corretoresDoLeads, ehProprietario, emFechamento, ehLocacao])

  const etapaManual = (l: LeadWithOwner): number | null => {
    const n = (l.custom_attributes as any)?.etapa_v3?.n
    return Number.isInteger(n) && n >= 0 && n <= 4 ? n : null
  }
  /** a etapa de agora, 0 a 4: a escolhida à mão; senão a da Nay */
  const etapaDe = useCallback((l: LeadWithOwner): number => {
    const m = etapaManual(l)
    if (m !== null) return m
    if (getLinhaWhatsapp(l) === 'parceria') return etapaDaParceria(l as any, marcas[l.id]) === 'visitas' ? 4 : 2
    const passo = Number(olx[fim8(l.phone)]?.passo || 0)
    if (ehVisita(l) || passo >= 5) return 4
    return passo === 4 ? 3 : passo === 3 ? 2 : passo === 2 ? 1 : 0
  }, [marcas, olx, ehVisita])

  /** quem responde agora: a pessoa quando a Nay está parada nesta conversa; senão a IA */
  const respondeDe = useCallback((l: LeadWithOwner): Responde => {
    if (mudado[l.id]) return mudado[l.id]
    const marca = marcas[l.id]
    const parada = getLinhaWhatsapp(l) === 'parceria' ? !!marca?.telAtendendo : !!olx[fim8(l.phone)]?.humano
    if (!parada) return { tipo: 'ia', nome: 'IA' }
    const r = responsavelV2(l as any, equipeV2)
    const doMotivo = /^(\p{L}+):/u.exec(String(marca?.telMotivo || ''))?.[1]
    return { tipo: 'humano', nome: r && !r.nay ? r.nome : doMotivo || 'Equipe' }
  }, [mudado, marcas, olx, equipeV2])

  const aplicar = useCallback((leadId: string, o: Organizado) => {
    setLeads((p) => p.map((x) => (x.id === leadId ? {
      ...x, custom_attributes: o.custom_attributes,
      ...(o.last_activity_at ? { last_activity_at: new Date(o.last_activity_at).toISOString() } : {}),
      ...(typeof o.is_unread === 'boolean' ? { is_unread: o.is_unread } : {}),
    } : x)))
  }, [setLeads])

  const etapas = useMemo(() => [
    { chave: 'todas', rotulo: 'Todas', cor: CINZA, casa: daTela },
    ...(Object.keys(FILAS_V3) as FilaV3[]).map((f) => ({
      chave: f, rotulo: FILAS_V3[f].rotulo, quem: FILAS_V3[f].quem, cor: FILAS_V3[f].cor, casa: (l: LeadWithOwner) => filaDe(l) === f,
    })),
  ], [daTela, filaDe])

  if (loading) return null
  if (!ehTel) return <NotAuthorized />

  const corDe = (l: LeadWithOwner) => { const f = filaDe(l); return f ? FILAS_V3[f].cor : CINZA }
  return (
    <ModoV3.Provider value={true}>
      <div className="chat-theme h-full min-h-0">
        <ChatJuntado titulo="Atendimento" subtitulo="Leads e Parceria num lugar só · a resposta sai pelo número de cada conversa"
                     pertence={daTela} etapas={etapas} etapasEmLista semFaixaDaLinha chaveAbas="crm:abas-v3"
                     vazio="Nenhuma conversa aqui."
                     cadastrar={() => ({})}
                     itemDaLista={(l, x) => <CardV3 l={l} hora={x.hora} aberta={x.aberta} abrir={x.abrir} menu={x.menu}
                                                    cor={corDe(l)} etapa={etapaDe(l)} r={respondeDe(l)} />}
                     naConversa={{
                       anel: corDe,
                       pilula: (l) => {
                         const f = filaDe(l)
                         return f ? { texto: FILAS_V3[f].tipo, cor: FILAS_V3[f].cor }
                           : { texto: ehProprietario(l) ? 'Proprietário' : 'Fechamento', cor: CINZA }
                       },
                       subtitulo: (l) => <SubtituloV3 l={l} ehLead={getLinhaWhatsapp(l) === 'captacao' && filaDe(l) !== 'corretores'}
                                                      creci={marcas[l.id]?.creci || null} />,
                       abaixoDoTopo: (l) => <BarraDasEtapas l={l} atual={etapaDe(l)} manual={etapaManual(l) !== null}
                                                            aoMudar={(o) => aplicar(l.id, o)} />,
                       rodape: (l) => <QuemResponde key={l.id} l={l} r={respondeDe(l)}
                                                    aoMudar={(r, o) => { setMudado((m) => ({ ...m, [l.id]: r })); if (o) aplicar(l.id, o) }} />,
                       organizar: (l) => getLinhaWhatsapp(l) === 'parceria'
                         ? <EnviarParaDaParceria lead={l} aoMudar={(o) => aplicar(l.id, o)} />
                         : <OrganizarConversa lead={l} tipoDeduzido={null} equipe={equipe} naLocacao={ehLocacao(l)}
                                              aoMudar={(o) => aplicar(l.id, o)} />,
                     }} />
      </div>
    </ModoV3.Provider>
  )
}
