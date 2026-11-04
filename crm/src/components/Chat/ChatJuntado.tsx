'use client'

/**
 * CHAT JUNTADO: as telas que reúnem conversas de mais de um número (Chat Administração e Chat Captação), com a cara do
 * WhatsApp Leads (Pedro, 03/11/2026: "esses chats novos separados estão vindo com um visual inferior aos outros chats, eu
 * quero cópias do visual do chat Leads para esses novos ... e tem que ter a lupinha de pesquisar contatos ou conversas que
 * nem tem no chat Leads e Parceria").
 *
 * O mesmo esqueleto da ChatWhatsApp: a lista que alarga puxando a borda (a mesma largura do Leads), o topo com o nome e a
 * lupa, as abas em chips, a conversa e o card do contato ao lado (o card da linha DA CONVERSA: Parceria ou o de dono da
 * captação). Cada conversa continua sendo da linha dela (crm/CLAUDE.md): a faixa diz por qual número fala, e a resposta
 * sai por ele. Quem entra é a tela que diz (`pertence`); o botão direito também (`menu`).
 */
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode, type MouseEvent as EventoDeMouse } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { Archive, Check, CircleNotch, EnvelopeSimple, MagnifyingGlass, Plus, PushPin, Tag, Trash, TreeStructure, X } from '@phosphor-icons/react'
import { useAuth, useIsMobile } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useTiposDeContato } from '@/hooks/useTiposDeContato'
import { usePuxador } from '@/hooks/usePuxador'
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { acharTipo, tipoEscolhido } from '@/lib/organizacaoDoLead'
import { CORES_DE_ETIQUETA, criarEtiqueta, marcarEtiqueta, useEtiquetas } from '@/lib/etiquetas'
import { dentroDe } from '@/lib/organizacaoDoLead'
import { organizar } from './OrganizarConversa'
import RelacionarA from './RelacionarA'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import LeadListItem, { ehEtapaComoTag } from './LeadListItem'
import ChatWindow from './ChatWindow'
import ChatFilterTabs, { type FiltroDaLista } from './ChatFilterTabs'
import { casaNaBusca } from './BuscaDaLista'
import PainelContatoParceria from './PainelContatoParceria'
import PainelContatoCaptacao, { type PainelV3 } from './PainelContatoCaptacao'
import CadastroImovelOlx from './CadastroImovelOlx'
import { acessoV2, usePapelV2, type QuemAtende } from '@/lib/versaoDoCrm'
import { mudouPara } from '@/lib/organizacaoDoLead'

export const NUMERO_DA_CONVERSA: Record<string, string> = {
  captacao: 'Pelo número Leads · 8595-6408', parceria: 'Pelo número Parceria · 9445-3618', oficial: 'Pelo número Oficial · 8456-0874',
}
const CHAVE_PAINEL = 'crm:painel-do-contato-aberto'

function hora(iso?: string) {
  if (!iso) return ''
  const d = new Date(iso)
  return d.toDateString() === new Date().toDateString()
    ? d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Manaus' })
    : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Manaus' })
}

/** Tela larga o bastante para o card do contato ficar ao lado (a mesma régua da ChatWhatsApp). */
function useTelaLarga(): boolean {
  const [larga, setLarga] = useState(true)
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 1366px)')
    const atualizar = () => setLarga(mq.matches)
    atualizar()
    mq.addEventListener('change', atualizar)
    return () => mq.removeEventListener('change', atualizar)
  }, [])
  return larga
}

interface Props {
  titulo: string
  subtitulo: string
  /** quem entra nesta tela */
  pertence: (l: LeadWithOwner) => boolean
  /** a tela é só do administrador (o Tel) */
  soAdmin?: boolean
  /** onde ficam as etiquetas escolhidas como aba (neste navegador) */
  chaveAbas: string
  /** o que diz a lista vazia e a conversa ainda não escolhida */
  vazio: string
  /** o botão direito numa conversa: os itens do menu (fechar = fecha o menu) */
  menu?: (lead: LeadWithOwner, fechar: () => void) => ReactNode
  /** ainda carregando quem entra (a lista de captação vem do servidor) */
  carregando?: boolean
  /** o que vem no alto do card do contato (o contexto da captação) */
  topoDoCard?: (lead: LeadWithOwner) => ReactNode
  /** o botão Cadastrar imóvel no alto da conversa (a barra do WhatsApp Leads, 535); devolve o link da OLX, se houver */
  cadastrar?: (lead: LeadWithOwner) => { linkInicial?: string }
  /** v2 (Pedro, 03/11, noite): a faixa preta/branca do imóvel e a borda com o nome em pé de quem atende, em cada conversa */
  enfeite?: (lead: LeadWithOwner) => { faixa?: string | null; borda?: QuemAtende | null } | null
  /** v2: a aba "Meus" (a padrão) para quem só vê os dele por padrão; "Todos" mostra o resto */
  meus?: (lead: LeadWithOwner) => boolean
  /** v2, aba Visita: as conversas em cards, um por visita (o topo de cada card, quem entra nele e a cor da borda).
   *  `removiveis` são os ids de quem pode sair do card (o x e o "Excluir da visita"); `aoRemover` tira. */
  grupos?: (visiveis: LeadWithOwner[]) => Array<{
    chave: string; topo: ReactNode; leads: LeadWithOwner[]; cor?: string
    removiveis?: Set<string>; aoRemover?: (leadId: string) => void
  }>
  /** v2, aba Proprietários (Pedro, 03/11: "cada contato um card único ... um espaço entre eles") */
  cards?: boolean
  /** v2, aba Visita: o + do alto faz outra coisa (relacionar à visita), no lugar de escolher as etiquetas */
  botaoMais?: { titulo: string; aoClicar: () => void }
  /** v2, aba Visita (Pedro, 04/11: "o Diego, da equipe, fica fixado fora dos cards ... no topo, antes de começar os cards"):
   *  as conversas fixadas em cima dos grupos, com o rótulo delas */
  fixos?: { rotulo: string; ids: Set<string> }
  /** 04/11: o que fica no card no lugar das etapas (no Chat Captação, o tipo do contato) */
  etapaDoCard?: (lead: LeadWithOwner) => ReactNode
  /** 04/11: a lupa também acha por isto (na aba Proprietários, o código do imóvel do dono) */
  casaExtra?: (texto: string, lead: LeadWithOwner) => boolean
  /** 04/11: o que aparece em cima dos resultados da lupa (na aba Proprietários, o dono do imóvel pesquisado) */
  buscaExtra?: (texto: string) => ReactNode
  /** 04/11: o que vem logo embaixo do título e do subtítulo (no Chat Captação, o Criar contato) */
  abaixoDoTitulo?: ReactNode
  /** v3 (Pedro, 04/11): os chips do alto são ESTAS etapas (e só elas), cada uma filtrando pela sua regra; a primeira abre */
  etapas?: Array<{ chave: string; rotulo: string; casa: (lead: LeadWithOwner) => boolean; quem?: string; cor?: string }>
  /** v3 (Pedro, 04/11, o desenho do Atendimento): as etapas em COLUNA (bolinha, nome e quem atende à direita), no lugar dos chips */
  etapasEmLista?: boolean
  /** v3: o que vai embaixo de cada conversa da lista (a barrinha das etapas e "etapa · quem atende") */
  rodapeDoItem?: (lead: LeadWithOwner) => ReactNode
  /** v3: o que a conversa aberta ganha (os botões do alto, o subtítulo, a barra das etapas, por onde sai a resposta) */
  naConversa?: {
    organizar?: (lead: LeadWithOwner) => ReactNode
    subtitulo?: (lead: LeadWithOwner) => ReactNode
    abaixoDoTopo?: (lead: LeadWithOwner) => ReactNode
    rodape?: (lead: LeadWithOwner) => ReactNode
    anel?: (lead: LeadWithOwner) => string | undefined
    pilula?: (lead: LeadWithOwner) => { texto: string; cor: string; no?: ReactNode } | undefined
  }
  /** v3: o card da lista é este (no lugar do LeadListItem); recebe a hora, se está aberta, abrir e o botão direito */
  itemDaLista?: (lead: LeadWithOwner, x: { hora: string; aberta: boolean; abrir: () => void; menu: (e: EventoDeMouse) => void }) => ReactNode
  /** v3 (Pedro, 04/11: o painel do lead no visual novo): o que o painel do lead do Leads ganha (anel, tipo, número, quem responde, etapa) */
  painelV3?: (lead: LeadWithOwner) => PainelV3
  /** v3 (Pedro, 04/11: Hoje · Não lidas · IA · Equipe): a linha de filtros rápidos embaixo das filas (recebe a fila escolhida) */
  filtrosRapidos?: (filaEscolhida: string) => ReactNode
  /** v3: o filtro rápido ligado; combina com a fila (as contagens das filas não mudam por ele) */
  filtroExtra?: (lead: LeadWithOwner) => boolean
  /** v3: a lista vazia por causa dos filtros rápidos ("Nenhuma conversa com esses filtros" e Limpar filtros) */
  vazioDosFiltros?: ReactNode
  /** v3: sem a faixa laranja "Pelo número ..." (a saída vai embaixo, em cima da caixa de mensagem) */
  semFaixaDaLinha?: boolean
}

export default function ChatJuntado({ titulo, subtitulo, pertence, soAdmin, chaveAbas, vazio, menu, carregando, topoDoCard, cadastrar, enfeite, meus, grupos, cards, botaoMais, fixos, casaExtra, buscaExtra, etapaDoCard, abaixoDoTitulo, etapas, etapasEmLista, rodapeDoItem, naConversa, semFaixaDaLinha, itemDaLista, painelV3, filtrosRapidos, filtroExtra, vazioDosFiltros }: Props) {
  const { organizationId, loading, permissions } = useAuth()
  // 04/11: o Visualizar por do administrador vale aqui (usePapelV2)
  const papel = usePapelV2()
  const ehAdmin = papel.admin
  const pode = soAdmin ? ehAdmin : ehAdmin || papel.adminDeVerdade || !!permissions?.settings?.view_chat
  const { leads, setLeads, loading: leadsLoading } = useLeadsContext()
  const { marcas } = useParceriaMarcas(true)
  const { tipos } = useTiposDeContato()
  const etiquetas = useEtiquetas()
  const isMobile = useIsMobile()
  const telaLarga = useTelaLarga()
  const lista_ = usePuxador('crm:largura-lista', { min: 260, max: 640, padrao: 380, lado: 'direita' })
  const router = useRouter()
  const searchParams = useSearchParams()

  const [aba, setAba] = useState<string>(etapas?.[0]?.chave ?? (meus ? 'meus' : 'all'))
  const [selecionada, setSelecionada] = useState<string | null>(null)
  const [verConversa, setVerConversa] = useState(false)
  const [abas, setAbas] = useState<string[]>([])
  const [escolhendo, setEscolhendo] = useState(false)
  const [buscaAberta, setBuscaAberta] = useState(false)
  const [busca, setBusca] = useState('')
  const [menuEm, setMenuEm] = useState<{ x: number; y: number; lead: LeadWithOwner } | null>(null)
  const [painelAberto, setPainelAberto] = useState(true)
  const [cadastroDe, setCadastroDe] = useState<string | null>(null)

  useEffect(() => {
    if (!telaLarga) { setPainelAberto(false); return }
    try { setPainelAberto(localStorage.getItem(CHAVE_PAINEL) !== 'nao') } catch { setPainelAberto(true) }
  }, [telaLarga])
  const alternarPainel = useCallback(() => {
    setPainelAberto((aberto) => {
      const novo = !aberto
      if (telaLarga) { try { localStorage.setItem(CHAVE_PAINEL, novo ? 'sim' : 'nao') } catch {} }
      return novo
    })
  }, [telaLarga])

  useEffect(() => { try { setAbas(JSON.parse(localStorage.getItem(chaveAbas) || '[]')) } catch {} }, [chaveAbas])
  const salvarAbas = (novas: string[]) => { setAbas(novas); try { localStorage.setItem(chaveAbas, JSON.stringify(novas)) } catch {} }

  useEffect(() => {
    if (!menuEm) return
    const fechar = () => setMenuEm(null)
    const tecla = (e: KeyboardEvent) => { if (e.key === 'Escape') setMenuEm(null) }
    window.addEventListener('click', fechar)
    window.addEventListener('scroll', fechar, true)
    window.addEventListener('keydown', tecla)
    return () => { window.removeEventListener('click', fechar); window.removeEventListener('scroll', fechar, true); window.removeEventListener('keydown', tecla) }
  }, [menuEm])

  /* a conversa que veio pelo endereço e ainda não está na lista (recém-aberta, sem mensagem): busca uma vez */
  const [solto, setSolto] = useState<LeadWithOwner | null>(null)
  const todas = useMemo(() => {
    // 04/11: quem só vê os números dele (a Rayssa: a Parceria) não vê o Leads aqui, a não ser o que foi enviado a ela
    const acesso = acessoV2(ehAdmin, papel.nome, papel.abas)
    const doNumeroDele = (l: LeadWithOwner) => !acesso.soOsNumerosDela
      || acesso.linhas.includes(getLinhaWhatsapp(l) as any) || acesso.linhas.includes(mudouPara(l) as any)
    const base = leads.filter((l) => !l.is_group && !l.is_archived && pertence(l) && doNumeroDele(l))
    if (solto && pertence(solto) && !base.some((l) => l.id === solto.id)) base.push(solto)
    return base.sort((a, b) => (Number(!!b.is_pinned) - Number(!!a.is_pinned))
      || new Date(b.last_activity_at || b.created_at).getTime() - new Date(a.last_activity_at || a.created_at).getTime())
  }, [leads, pertence, solto, ehAdmin, papel.nome, papel.abas])

  /* o endereço é só ENTRADA (crm/CLAUDE.md): ?leadId= abre aquela conversa uma vez */
  const pedidoVisto = useRef<string | null>(null)
  const leadIdDaUrl = searchParams.get('leadId')
  const pedido = leadIdDaUrl ? `${leadIdDaUrl}|${searchParams.get('abrir') ?? ''}` : null
  useEffect(() => {
    if (!pedido || pedido === pedidoVisto.current || !leadIdDaUrl || loading || leadsLoading) return
    pedidoVisto.current = pedido
    setSelecionada(leadIdDaUrl); setVerConversa(true)
    if (leads.some((l) => l.id === leadIdDaUrl)) return
    // sem cancelar na troca da lista: o pedido já foi marcado como visto e não volta a buscar
    fetch(`/api/leads/${leadIdDaUrl}`).then((r) => (r.ok ? r.json() : null))
      .then((j) => { if (j?.data) setSolto(j.data as LeadWithOwner) }).catch(() => {})
  }, [pedido, leadIdDaUrl, leads, loading, leadsLoading])

  const contagem = (tagId: string) => todas.filter((l) => (l.lead_tags || []).some((lt: any) => lt.tag_id === tagId)).length
  const buscando = busca.trim().length > 0
  const visiveis = todas.filter((l) => buscando ? casaNaBusca(busca, l) || !!casaExtra?.(busca, l)
    : etapas ? !!etapas.find((e) => e.chave === aba)?.casa(l) || l.id === selecionada
    : aba === 'all' ? true : aba === 'meus' ? !!meus?.(l) || l.id === selecionada
    : aba === 'nao_lidas' ? !!l.is_unread || l.id === selecionada
    : (l.lead_tags || []).some((lt: any) => lt.tag_id === aba))
    .filter((l) => buscando || !filtroExtra || filtroExtra(l) || l.id === selecionada)
  const aberta = todas.find((l) => l.id === selecionada) || null

  /* v2, aba Visita: os grupos (um por visita) calculados uma vez, para desenhar os cards e para o "Excluir da visita"
     do botão direito saber, de qualquer lead, se ele pode sair e por qual card (05/11, Pedro: "quero poder clicar com
     o botão direito no lead que faz parte da aba visita em todas as visitas e poder clicar em excluir da visita") */
  const gruposNaTela = useMemo(() => grupos ? grupos(visiveis.filter((l) => !fixos?.ids.has(l.id))) : null,
    [grupos, visiveis, fixos])
  const removerDaVisitaPor = useMemo(() => {
    const m = new Map<string, () => void>()
    for (const g of gruposNaTela || []) for (const id of g.removiveis || []) m.set(id, () => g.aoRemover?.(id))
    return m
  }, [gruposNaTela])

  const filtros: FiltroDaLista[] = etapas ? etapas.map((e) => ({ chave: e.chave as any, rotulo: e.rotulo, contagem: todas.filter(e.casa).length })) : [
    ...(meus ? [{ chave: 'meus' as any, rotulo: 'Meus', contagem: todas.filter((l) => meus(l)).length }] : []),
    { chave: 'all', rotulo: 'Todos', contagem: todas.length },
    { chave: 'nao_lidas' as any, rotulo: 'Não lidos', contagem: todas.filter((l) => l.is_unread).length },
    ...abas.flatMap((id) => {
      const t = etiquetas.find((x) => x.id === id)
      return t ? [{ chave: id as any, rotulo: t.name, contagem: contagem(id), cor: t.color }] : []
    }),
  ]

  /* O MENU DO BOTÃO DIREITO IGUAL AO DOS CHATS (Pedro, 04/11: "quero as mesmas opções de clicar com o botão direito em
     todos os chats; no de Proprietários só tem uma; põe o mesmo em todos"): Fixar, Não lida, Arquivar, Etiquetas…,
     Relacionar a… e Remover relacionamento (as mesmas da LeadList), e embaixo as da tela (o `menu`). */
  const [relacionando, setRelacionando] = useState<LeadWithOwner | null>(null)
  const [relOcupado, setRelOcupado] = useState(false)
  const [relErro, setRelErro] = useState('')
  const [menuDeTags, setMenuDeTags] = useState(false)
  const [buscaDeTag, setBuscaDeTag] = useState('')
  const raizDaLista = useRef<HTMLDivElement>(null)
  const mudarLead = async (l: LeadWithOwner, campos: Partial<LeadWithOwner>) => {
    setMenuEm(null)
    setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, ...campos } : x)))
    try {
      const r = await fetch(`/api/leads/${l.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(campos) })
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
    } catch {
      const volta = Object.fromEntries(Object.keys(campos).map((k) => [k, (l as any)[k]]))
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, ...volta } : x)))
    }
  }
  const relacionar = async (filho: LeadWithOwner, pai: LeadWithOwner) => {
    setRelOcupado(true); setRelErro('')
    try {
      const o = await organizar(filho.id, { dentroDe: { pai: pai.id, ligar: true } })
      setLeads((p) => p.map((x) => (x.id === filho.id ? { ...x, custom_attributes: o.custom_attributes } : x)))
      setRelacionando(null)
    } catch (e: any) { setRelErro(e?.message || 'Não consegui relacionar.') } finally { setRelOcupado(false) }
  }

  const abrir = (l: LeadWithOwner) => {
    if (relacionando) { if (l.id !== relacionando.id && !relOcupado) void relacionar(relacionando, l); return }
    setSelecionada(l.id); setVerConversa(true)
    if (l.is_unread) {
      setLeads((p) => p.map((x) => (x.id === l.id ? { ...x, is_unread: false } : x)))
      fetch(`/api/leads/${l.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_unread: false }) }).catch(() => {})
    }
  }
  const aoEnviar = (conteudo: string) => {
    if (!aberta) return
    setLeads((p) => p.map((x) => (x.id === aberta.id
      ? { ...x, last_message_content: conteudo, last_message_sender_type: 'human' as const, last_activity_at: new Date().toISOString() } : x)))
  }
  const aoMudarEtiqueta = (leadId: string, tagId: string, acao: 'add' | 'remove', tag?: any) => {
    setLeads((p) => p.map((x) => x.id !== leadId ? x : {
      ...x, lead_tags: acao === 'add'
        ? [...(x.lead_tags || []).filter((lt: any) => lt.tag_id !== tagId), { tag_id: tagId, tag } as any]
        : (x.lead_tags || []).filter((lt: any) => lt.tag_id !== tagId),
    }))
  }
  const aoMudarLead = (leadId: string, updates: Partial<LeadWithOwner>) => {
    setLeads((p) => p.map((l) => (l.id === leadId ? { ...l, ...updates } : l)))
  }

  if (loading || leadsLoading) return <div className="flex h-full items-center justify-center"><CircleNotch size={24} className="animate-spin" /></div>
  if (!pode) return <NotAuthorized />

  const linhaDe = (l: LeadWithOwner) => getLinhaWhatsapp(l) || ''

  /* uma conversa na lista; na v2, com a faixa do imóvel em cima e a borda de quem atende, o nome em pé ("pregado na parede") */
  const linhaDaLista = (l: LeadWithOwner) => {
    if (itemDaLista) return (
      <div key={l.id}>{itemDaLista(l, {
        hora: hora(l.last_activity_at || l.created_at), aberta: l.id === selecionada, abrir: () => abrir(l),
        menu: (e) => { e.preventDefault(); setMenuDeTags(false); setMenuEm({ x: e.clientX, y: e.clientY, lead: l }) },
      })}</div>
    )
    const item = (
      <LeadListItem lead={l} isSelected={l.id === selecionada} timeStr={hora(l.last_activity_at || l.created_at)}
                    onClick={abrir} query={busca}
                    onContextMenu={(e, lead) => { e.preventDefault(); setMenuDeTags(false); setMenuEm({ x: e.clientX, y: e.clientY, lead }) }}
                    faixaDaLinha={semFaixaDaLinha ? null : NUMERO_DA_CONVERSA[linhaDe(l)] || null}
                    tipoDoContato={acharTipo(tipos, tipoEscolhido(l))} cinzas />
    )
    const e = enfeite?.(l)
    if (rodapeDoItem) return (
      <div key={l.id} style={{ background: l.id === selecionada ? 'var(--wa-row-selected)' : undefined, borderBottom: '1px solid var(--wa-divider)' }}>
        {item}
        <div className="pl-[72px] pr-3 -mt-[6px] pb-2 cursor-pointer" onClick={() => abrir(l)}>{rodapeDoItem(l)}</div>
      </div>
    )
    if (!e || (!e.faixa && !e.borda)) return <div key={l.id} className={cards ? 'v2-card' : undefined}>{item}</div>
    return (
      <div key={l.id} className={`flex items-stretch${cards ? ' v2-card' : ''}`}>
        {e.borda && (
          <div className="w-[20px] flex-shrink-0 flex items-center justify-center" style={{ background: e.borda.cor }} title={`Quem atende: ${e.borda.nome}`}>
            <span className="text-[10px] font-bold text-white whitespace-nowrap tracking-wide" style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)' }}>
              {e.borda.nome}
            </span>
          </div>
        )}
        <div className="flex-1 min-w-0">
          {e.faixa && (
            <div className="v2-faixa px-3 py-[4px] text-[11.5px] font-semibold truncate" title={e.faixa}>
              {e.faixa}
            </div>
          )}
          {item}
        </div>
      </div>
    )
  }

  const lista = (
    <div className="flex flex-col h-full" style={{ background: 'var(--wa-panel)' }}>
      <div className="flex-shrink-0 relative">
        <div className="wa-topo gap-2 !min-h-[56px]">
          <div className="min-w-0">
            <h1 className="text-[20px] font-bold leading-6 truncate" style={{ color: 'var(--wa-text)' }}>{titulo}</h1>
            <p className="text-[12px] leading-4 truncate" style={{ color: 'var(--wa-text-2)' }}>{subtitulo}</p>
          </div>
          <div className="ml-auto flex items-center gap-1">
            <button type="button" onClick={() => setBuscaAberta((v) => !v)} aria-expanded={buscaAberta}
                    className={`wa-icone-btn ${buscaAberta || busca ? 'wa-icone-btn--on' : ''}`} title="Pesquisar conversa (nome ou número)">
              <MagnifyingGlass size={20} />
            </button>
            {etapas ? null : botaoMais ? (
              <button type="button" onClick={botaoMais.aoClicar} className="wa-icone-btn" title={botaoMais.titulo}>
                <Plus size={20} />
              </button>
            ) : (
              <button type="button" onClick={() => setEscolhendo((v) => !v)} aria-expanded={escolhendo}
                      className={`wa-icone-btn ${escolhendo ? 'wa-icone-btn--on' : ''}`} title="Escolher as etiquetas que viram aba aqui">
                {escolhendo ? <X size={20} /> : <Plus size={20} />}
              </button>
            )}
          </div>
        </div>
        {abaixoDoTitulo}
        {buscaAberta && (
          <div className="px-3 pb-2">
            <label className="wa-busca">
              <MagnifyingGlass size={18} />
              <input autoFocus value={busca} onChange={(e) => setBusca(e.target.value)}
                     onKeyDown={(e) => { if (e.key === 'Escape') { setBusca(''); setBuscaAberta(false) } }}
                     placeholder="Pesquisar nome ou número" aria-label="Pesquisar conversas" />
              <button type="button" onClick={() => { setBusca(''); setBuscaAberta(false) }} aria-label="Fechar a busca"><X size={16} /></button>
            </label>
          </div>
        )}
        {escolhendo && (
          <div className="mx-3 mb-2 p-2 rounded-lg flex flex-col gap-1 max-h-64 overflow-y-auto" style={{ border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}>
            <span className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>As etiquetas que viram aba aqui (a contagem é só de quem está nesta tela)</span>
            {etiquetas.filter((t) => !ehEtapaComoTag(t.name)).map((t) => (
              <label key={t.id} className="flex items-center gap-2 text-[13px] cursor-pointer">
                <input type="checkbox" checked={abas.includes(t.id)}
                       onChange={(e) => salvarAbas(e.target.checked ? [...abas, t.id] : abas.filter((x) => x !== t.id))} />
                <span className="w-2.5 h-2.5 rounded-full" style={{ background: t.color }} />
                <span className="flex-1">{t.name}</span>
                <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>{contagem(t.id)}</span>
              </label>
            ))}
            <button type="button" className="text-[12px] self-start mt-1" style={{ color: 'var(--wa-text-2)' }}
                    onClick={async () => {
                      const nome = window.prompt('Nome da nova etiqueta:')
                      if (!nome?.trim()) return
                      try { const t = await criarEtiqueta(nome, CORES_DE_ETIQUETA[6]); salvarAbas([...abas, t.id]) }
                      catch (e: any) { window.alert(e?.message || 'Não consegui criar a etiqueta.') }
                    }}>
              + Nova etiqueta…
            </button>
          </div>
        )}
        {!buscando && etapas && etapasEmLista ? (
          <>
          <div className="flex flex-col py-1.5" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
            {etapas.map((e) => (
              <button key={e.chave} type="button" onClick={() => setAba(e.chave)} aria-pressed={aba === e.chave}
                      className="mx-2 px-3 h-9 rounded-lg flex items-center gap-2.5 text-[14px] text-left"
                      style={{ background: aba === e.chave ? 'var(--wa-row-selected)' : 'transparent', color: 'var(--wa-text)' }}>
                <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: e.cor || 'var(--wa-text-2)' }} />
                <span className="flex-1">{e.rotulo}</span>
                <span className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>{e.quem ?? todas.filter(e.casa).length}</span>
              </button>
            ))}
          </div>
            {filtrosRapidos?.(aba)}
          </>
        ) : !buscando && <ChatFilterTabs ativo={aba as any} aoMudar={(k) => setAba(String(k))} filtros={filtros} />}
      </div>
      <div ref={raizDaLista} className="flex-1 overflow-y-auto overflow-x-hidden wa-rolagem">
        {buscando && buscaExtra?.(busca)}
        {buscando && visiveis.length > 0 && (
          <div className="px-4 pt-1 pb-1.5 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
            {visiveis.length} {visiveis.length === 1 ? 'conversa' : 'conversas'} nesta tela
          </div>
        )}
        {visiveis.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-[70%] px-8 text-center text-[14px]" style={{ color: 'var(--wa-text-2)' }}>
            {carregando ? 'Carregando…' : buscando ? 'Ninguém com esse nome ou número nesta tela'
              : filtroExtra && vazioDosFiltros ? vazioDosFiltros : aba !== 'all' ? 'Nenhuma conversa neste filtro' : vazio}
          </div>
        ) : (
          grupos && !buscando ? (
            /* um card por visita, com espaço entre um e outro (Pedro: "para ficar bem fácil de ver") */
            <div className="flex flex-col gap-4 p-2 pb-4">
              {fixos && visiveis.some((l) => fixos.ids.has(l.id)) && (
                <div className="flex flex-col gap-1.5">
                  <div className="px-1 text-[11.5px] font-semibold uppercase tracking-wide" style={{ color: 'var(--wa-text-2)' }}>{fixos.rotulo}</div>
                  {visiveis.filter((l) => fixos.ids.has(l.id)).map((l) => <div key={l.id} className="v2-card">{linhaDaLista(l)}</div>)}
                </div>
              )}
              {(gruposNaTela || []).map((g) => (
                <div key={g.chave} className="rounded-xl" style={{ border: `2px solid ${g.cor || '#2563eb'}` }}>
                  <div className="px-3 py-2 text-[13px] rounded-t-[10px]" style={{ background: `color-mix(in srgb, ${g.cor || '#2563eb'} 12%, transparent)`, color: 'var(--wa-text)' }}>{g.topo}</div>
                  <div className="rounded-b-[10px] overflow-hidden">
                    {g.leads.map((l) => (
                      <div key={l.id} className="relative">
                        {linhaDaLista(l)}
                        {g.removiveis?.has(l.id) && (
                          <button type="button" onClick={(e) => { e.preventDefault(); e.stopPropagation(); g.aoRemover?.(l.id) }}
                                  className="absolute right-2 top-1/2 -translate-y-1/2 z-[1] wa-icone-btn !w-6 !h-6"
                                  style={{ background: 'var(--wa-panel)', boxShadow: '0 1px 3px rgba(0, 0, 0, 0.22)' }}
                                  title="Remover esta pessoa da visita" aria-label="Remover esta pessoa da visita">
                            <X size={14} />
                          </button>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          ) : cards ? (
            <div className="flex flex-col gap-2.5 p-2 pb-4">{visiveis.map(linhaDaLista)}</div>
          ) : (
            <div className="flex flex-col pb-2">{visiveis.map(linhaDaLista)}</div>
          )
        )}
      </div>
    </div>
  )

  const conversa = (voltar?: () => void) => aberta ? (
    <ChatWindow key={aberta.id} lead={aberta} organizationId={organizationId || ''} onMessageSent={aoEnviar}
                linha={getLinhaWhatsapp(aberta) || undefined} marca={linhaDe(aberta) === 'parceria' ? marcas[aberta.id] : undefined}
                faixaDaLinha={semFaixaDaLinha ? null : NUMERO_DA_CONVERSA[linhaDe(aberta)] || null} onTagsChange={aoMudarEtiqueta}
                organizar={naConversa?.organizar?.(aberta)} subtituloDoTopo={naConversa?.subtitulo?.(aberta)}
                abaixoDoTopo={naConversa?.abaixoDoTopo?.(aberta)} rodapeDoChat={naConversa?.rodape?.(aberta)}
                anelDoAvatar={naConversa?.anel?.(aberta)} pilulaDoTopo={naConversa?.pilula?.(aberta)}
                painelAberto={painelAberto} aoAlternarPainel={alternarPainel} aoVoltar={voltar}
                aoCadastrarImovel={cadastrar ? () => setCadastroDe((x) => (x === aberta.id ? null : aberta.id)) : undefined}
                cadastroAberto={cadastroDe === aberta.id} />
  ) : (
    <div className="wa-papel flex flex-col items-center justify-center h-full gap-2 px-8 text-center">
      <span className="relative text-[15px] font-semibold" style={{ color: 'var(--wa-text)' }}>{titulo}</span>
      <span className="relative text-[14px]" style={{ color: 'var(--wa-text-2)' }}>{todas.length ? 'Escolha uma conversa.' : vazio}</span>
    </div>
  )

  /* o card do contato: o da linha DA CONVERSA, como no misto da ChatWhatsApp */
  const painel = (modo: 'lateral' | 'gaveta') => {
    if (!aberta || !painelAberto) return null
    if (linhaDe(aberta) === 'parceria') {
      return <PainelContatoParceria key={aberta.id} lead={aberta} modo={modo} aoFechar={alternarPainel} topo={topoDoCard?.(aberta)} trocaDaEtapa={etapaDoCard?.(aberta)}
                                    aoVerVisita={() => router.push('/chat/parceria')} onTagsChange={aoMudarEtiqueta} onUpdateLead={aoMudarLead} />
    }
    return <PainelContatoCaptacao key={aberta.id} lead={aberta} modo={modo} aoFechar={alternarPainel} topo={topoDoCard?.(aberta)} trocaDaEtapa={etapaDoCard?.(aberta)}
                                  v3={painelV3?.(aberta)}
                                  oficial={linhaDe(aberta) === 'oficial'} onTagsChange={aoMudarEtiqueta} />
  }
  const cadastro = (modo: 'lateral' | 'gaveta') => aberta && cadastrar && cadastroDe === aberta.id
    ? <CadastroImovelOlx key={aberta.id} lead={aberta} modo={modo} aoFechar={() => setCadastroDe(null)} linkInicial={cadastrar(aberta).linkInicial} />
    : null

  const item = 'w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3'
  const l = menuEm?.lead
  const atual = l ? (leads.find((x) => x.id === l.id) || l) : null
  const etiquetasDoMenu = etiquetas.filter((t) => !ehEtapaComoTag(t.name)
    && (!buscaDeTag.trim() || t.name.toLowerCase().includes(buscaDeTag.trim().toLowerCase())))
  const menuAberto = menuEm && atual && (
    <div className="fixed z-50 rounded-xl py-1.5 min-w-[230px] max-h-[80vh] overflow-y-auto shadow-xl"
         style={{ left: Math.min(menuEm.x, window.innerWidth - 250), top: Math.min(menuEm.y, window.innerHeight - 340),
                  background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}
         onClick={(e) => e.stopPropagation()} onContextMenu={(e) => e.preventDefault()}>
      {menuDeTags ? (
        <div className="px-2 pb-1">
          <div className="flex items-center gap-2 px-2 py-1.5">
            <button type="button" onClick={() => setMenuDeTags(false)} className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>‹ Voltar</button>
            <input autoFocus value={buscaDeTag} onChange={(e) => setBuscaDeTag(e.target.value)} placeholder="Buscar etiqueta"
                   className="flex-1 h-7 px-2 rounded-md text-[13px] outline-none" style={{ background: 'var(--wa-search)', color: 'var(--wa-text)' }} />
          </div>
          {etiquetasDoMenu.map((t) => {
            const tem = (atual.lead_tags || []).some((lt: any) => lt.tag_id === t.id)
            return (
              <button key={t.id} type="button" className={item + ' !py-2'}
                      onClick={async () => {
                        aoMudarEtiqueta(atual.id, t.id, tem ? 'remove' : 'add', t)
                        try { await marcarEtiqueta(atual.id, t.id, !tem) }
                        catch (e: any) { aoMudarEtiqueta(atual.id, t.id, tem ? 'add' : 'remove', t); window.alert(e?.message || 'Não consegui mudar a etiqueta.') }
                      }}>
                <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: t.color }} />
                <span className="flex-1">{t.name}</span>
                {tem ? <Check size={15} style={{ color: 'var(--wa-green)' }} /> : <span className="text-[11px]" style={{ color: 'var(--wa-text-2)' }}>pôr</span>}
              </button>
            )
          })}
          <button type="button" className={item + ' !py-2 text-[13px]'} style={{ color: 'var(--wa-text-2)' }}
                  onClick={async () => {
                    const nome = window.prompt('Nome da nova etiqueta:')
                    if (!nome?.trim()) return
                    try { const t = await criarEtiqueta(nome, CORES_DE_ETIQUETA[5]); aoMudarEtiqueta(atual.id, t.id, 'add', t); await marcarEtiqueta(atual.id, t.id, true) }
                    catch (e: any) { window.alert(e?.message || 'Não consegui criar a etiqueta.') }
                  }}>
            <Plus size={15} /> Nova etiqueta…
          </button>
        </div>
      ) : (
        <>
          <button type="button" className={item} onClick={() => void mudarLead(atual, { is_pinned: !atual.is_pinned })}>
            <PushPin size={17} style={{ color: 'var(--wa-icon)' }} /> {atual.is_pinned ? 'Desafixar conversa' : 'Fixar conversa'}
          </button>
          <button type="button" className={item} onClick={() => void mudarLead(atual, { is_unread: !atual.is_unread })}>
            <EnvelopeSimple size={17} style={{ color: 'var(--wa-icon)' }} /> {atual.is_unread ? 'Marcar como lida' : 'Marcar como não lida'}
          </button>
          <button type="button" className={item} onClick={() => void mudarLead(atual, { is_archived: !atual.is_archived })}>
            <Archive size={17} style={{ color: 'var(--wa-icon)' }} /> {atual.is_archived ? 'Desarquivar' : 'Arquivar conversa'}
          </button>
          <button type="button" className={item} onClick={() => { setMenuDeTags(true); setBuscaDeTag('') }}>
            <Tag size={17} style={{ color: 'var(--wa-icon)' }} /> <span className="flex-1">Etiquetas…</span>
          </button>
          <button type="button" className={item} onClick={() => { setMenuEm(null); setRelacionando(atual); setRelErro('') }}>
            <TreeStructure size={17} style={{ color: 'var(--wa-icon)' }} /> <span className="flex-1">Relacionar a…</span>
          </button>
          {dentroDe(atual).length > 0 && (
            <button type="button" className={item}
                    onClick={async () => {
                      setMenuEm(null)
                      try { const o = await organizar(atual.id, { soltar: true }); setLeads((p) => p.map((x) => (x.id === atual.id ? { ...x, custom_attributes: o.custom_attributes } : x))) }
                      catch (e: any) { window.alert(e?.message || 'Não consegui remover o relacionamento.') }
                    }}>
              <X size={17} style={{ color: 'var(--wa-icon)' }} /> <span className="flex-1">Remover relacionamento</span>
            </button>
          )}
          {/* 05/11 (Pedro: "quero poder clicar com o botão direito no lead que faz parte da aba visita em todas as
              visitas e poder clicar em excluir da visita"): o mesmo x do card, aqui no botão direito, para toda
              pessoa do card (removerDaVisitaPor). */}
          {removerDaVisitaPor.has(atual.id) && (
            <button type="button" className={item} style={{ color: 'var(--wa-tag-tel)' }}
                    onClick={() => { setMenuEm(null); removerDaVisitaPor.get(atual.id)!() }}>
              <Trash size={17} style={{ color: 'var(--wa-tag-tel)' }} /> <span className="flex-1">Excluir da visita</span>
            </button>
          )}
          {menu && <div className="my-1" style={{ borderTop: '1px solid var(--wa-divider)' }} />}
          {menu?.(atual, () => setMenuEm(null))}
        </>
      )}
    </div>
  )
  const faixaDoRelacionar = relacionando && (
    <RelacionarA nome={relacionando.title || relacionando.phone || 'esta conversa'} alvo={raizDaLista} ocupado={relOcupado} erro={relErro}
                 aoCancelar={() => { setRelacionando(null); setRelErro('') }} />
  )

  if (isMobile) {
    return (
      <div className="chat-theme h-full flex flex-col">
        <div className="flex-1 min-h-0">{verConversa && aberta ? conversa(() => setVerConversa(false)) : lista}</div>
        {painel('gaveta')}
        {cadastro('gaveta')}
        {menuAberto}
        {faixaDoRelacionar}
      </div>
    )
  }
  return (
    <div className="chat-theme flex flex-col h-full min-h-0">
      <div className="flex flex-1 min-h-0">
        <div className="relative flex-shrink-0 h-full min-h-0" style={{ width: lista_.largura, borderRight: '1px solid var(--wa-divider)' }}>
          {lista}
          <div {...lista_.puxador} />
        </div>
        <div className="flex-1 min-w-0 h-full min-h-0">{conversa()}</div>
        {painel(telaLarga ? 'lateral' : 'gaveta')}
        {cadastro(telaLarga ? 'lateral' : 'gaveta')}
      </div>
      {menuAberto}
      {faixaDoRelacionar}
    </div>
  )
}
