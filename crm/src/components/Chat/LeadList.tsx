'use client'

import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { LeadWithOwner, SearchHit } from '@/lib/types'
import { MagnifyingGlass, PushPin, Archive, ArrowCounterClockwise, ArrowLeft, Tag as TagIcon, Check, X, ChatCircleText, ChatCircleDots } from '@phosphor-icons/react'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import { useLeadSearch } from '@/hooks/useLeadSearch'
import { DIAS_CONVERSA_IMPORTADA } from '@/lib/conversas'
import { useTags, useOrganizationMembers } from '@/hooks'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useCaptacaoDonos } from '@/hooks/useCaptacaoDonos'
import { montarAtendentes, atendenteDaConversa, type Atendente } from '@/lib/atendentes'
import LeadListItem from './LeadListItem'
import ChatFilterTabs, { type ChatTab, type FiltroDaLista } from './ChatFilterTabs'
import { conversaEstaNaLinha, type LinhaWhatsapp } from '@/lib/leadChannel'

/*
 * FOLLOW-UP DA PARCERIA (Pedro, 29/09/2026): "Últimas 6h | Últimas 24h | Essa
 * semana -- todo mundo que a última mensagem foi da pessoa e não nossa,
 * baseado na janela de tempo". As janelas se somam (a de 24h tem a de 6h).
 * "Essa semana" = os últimos 7 dias. Reação ("Reagiu com 👍") não conta: ela
 * fecha a conversa, não pede resposta.
 */
const HORA = 3_600_000
const JANELAS_DE_FOLLOWUP: Array<[string, number]> = [['seg_6h', 6 * HORA], ['seg_24h', 24 * HORA], ['seg_semana', 7 * 24 * HORA]]
function esperandoResposta(l: { last_message_sender_type?: string | null; last_message_content?: string | null; last_activity_at?: string | null }, janela: number, agora: number) {
  if (l.last_message_sender_type !== 'lead') return false
  if (String(l.last_message_content || '').startsWith('Reagiu com')) return false
  const t = Date.parse(l.last_activity_at || '')
  return Number.isFinite(t) && agora - t <= janela
}

/*
 * AS ETIQUETAS DE CADA LINHA (Tel, 26/09/2026).
 *
 *   captacao: "Recebeu mensagem, Em atendimento, Atualizou cadastro do seu
 *              imovel, Sugeriu outro imovel" (Tel, 28/09)
 *
 * A API oficial é da captação também, e usa as mesmas etiquetas. Os nomes
 * abaixo batem com as etiquetas criadas no banco -- mudar um lado exige mudar
 * o outro.
 *
 * A PARCERIA NÃO FILTRA MAIS POR ETIQUETA (Pedro, 29/09/2026): "nas tags de
 * cima ... troca por TODOS, Não lidos, Proprietários (filtra conforme o banco
 * de dados, o sistema já sabe quem é), VISITAS, TEL (TAG TEL QUE É O TEL
 * ATENDENDO)". Proprietários, Visitas e Tel vêm da Nay (/api/parceria/marcas).
 */
const ETIQUETAS_DA_LINHA: Record<string, string[]> = {
  // um funil por número (29/09): as etapas da campanha, que o CRM põe sozinho (src/lib/funis.ts)
  captacao: ['Não respondeu', 'Respondeu', 'Disponível', 'Alugado', 'Vendido', 'Mandou os dados'],
  oficial: ['Recebeu mensagem', 'Em atendimento', 'Atualizou cadastro do seu imóvel', 'Sugeriu outro imóvel'],
}

interface LeadListProps {
  leads: LeadWithOwner[]
  /* De qual linha de WhatsApp é esta lista: sem isto a lista mostrava as
     conversas de todas as linhas. */
  linha?: LinhaWhatsapp
  /** O nome e o número da linha, no topo da lista (ex.: "Parceria", "+55 92 9445-3618") */
  titulo?: string
  numero?: string
  selectedLeadId?: string
  onSelectLead: (lead: LeadWithOwner) => void
  onUpdateLead?: (leadId: string, updates: Partial<LeadWithOwner>) => void
  loading: boolean
  organizationId?: string | null
}

const WEEKDAYS_PT = ['Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira', 'Quinta-feira', 'Sexta-feira', 'Sábado']

/** Como o WhatsApp: hora de hoje; "Ontem"; dia da semana; data. */
function formatRelativeTime(dateString?: string) {
  if (!dateString) return ''
  const date = new Date(dateString)
  const today = new Date()
  const dateDay = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  const todayDay = new Date(today.getFullYear(), today.getMonth(), today.getDate())
  const diffDays = Math.round((todayDay.getTime() - dateDay.getTime()) / 86400000)
  if (diffDays === 0) return `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}`
  if (diffDays === 1) return 'Ontem'
  if (diffDays >= 2 && diffDays <= 6) return WEEKDAYS_PT[date.getDay()]
  return `${String(date.getDate()).padStart(2, '0')}/${String(date.getMonth() + 1).padStart(2, '0')}/${date.getFullYear()}`
}

interface ContextMenuState {
  visible: boolean
  x: number
  y: number
  lead: LeadWithOwner | null
}

/**
 * Esta conversa aparece na lista?
 *
 *   1. Com mensagem registrada aqui — sempre aparece, por mais antiga que seja.
 *   2. Sem mensagem e sem `last_activity_type` — contato que nunca foi conversa
 *      (a planilha de 644 importada por CSV). Nunca aparece; a busca acha.
 *   3. Importada do WhatsApp e ainda sem mensagem aqui — aparece enquanto for
 *      recente. É o catálogo antigo do aparelho, que não pode enterrar o resto.
 */
function ehConversaVisivel(lead: LeadWithOwner): boolean {
  const temMensagemAqui = !!lead.last_message_content || !!lead.last_message_sender_type
  if (temMensagemAqui) return true
  if (!lead.last_activity_type) return false
  if (!lead.last_activity_at) return false
  const limite = Date.now() - DIAS_CONVERSA_IMPORTADA * 24 * 60 * 60 * 1000
  return new Date(lead.last_activity_at).getTime() >= limite
}

export default function LeadList({
  leads,
  linha,
  titulo,
  numero,
  selectedLeadId,
  onSelectLead,
  onUpdateLead,
  loading,
  organizationId,
}: LeadListProps) {
  const ehParceria = linha === 'parceria'
  const [search, setSearch] = useState('')
  const [buscaAberta, setBuscaAberta] = useState(false)
  const [activeTab, setActiveTab] = useState<ChatTab>('all')
  const [verArquivadas, setVerArquivadas] = useState(false)
  const [contextMenu, setContextMenu] = useState<ContextMenuState>({ visible: false, x: 0, y: 0, lead: null })

  const { marcas, nay } = useParceriaMarcas(ehParceria)
  // o dono e o imóvel de cada conversa da captação (29/09)
  const donos = useCaptacaoDonos(linha === 'captacao')

  // Filtro por etiqueta — multi-seleção, combina com o filtro de cima.
  const { allTags } = useTags(organizationId)

  // Quem está atendendo (captação / oficial): o time de atendimento.
  const { members } = useOrganizationMembers(organizationId || '')
  const atendentes = useMemo(() => montarAtendentes(members), [members])
  const atendentePorId = useMemo(() => {
    const mapa: Record<string, Atendente> = {}
    for (const a of atendentes) mapa[a.id] = a
    return mapa
  }, [atendentes])
  const [tagFilterOpen, setTagFilterOpen] = useState(false)
  const [selectedTagIds, setSelectedTagIds] = useState<string[]>([])
  const tagFilterRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!tagFilterOpen) return
    const handleClickOutside = (e: MouseEvent) => {
      if (tagFilterRef.current && !tagFilterRef.current.contains(e.target as Node)) setTagFilterOpen(false)
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [tagFilterOpen])

  const toggleTagFilter = (tagId: string) => {
    setSelectedTagIds((prev) => (prev.includes(tagId) ? prev.filter((id) => id !== tagId) : [...prev, tagId]))
  }

  const menuRef = useRef<HTMLDivElement>(null)
  const scrollContainerRef = useRef<HTMLDivElement>(null)

  /*
   * Precisão no clique: abre a conversa que estava embaixo do mouse/dedo na
   * hora do TOQUE, nunca a que está lá na hora de soltar.
   *
   * A lista se reordena sozinha (conversa com mensagem nova sobe pro topo). Um
   * clique é apertar + soltar; se a lista andar no meio, o navegador entrega o
   * clique pra linha que passou a ocupar aquele lugar — e abria outra conversa.
   *
   *   mouse: abre já ao apertar (botão esquerdo);
   *   toque: guarda qual linha foi tocada e abre essa quando o toque termina
   *          como toque (se virar rolagem, o navegador cancela e nada abre);
   *   teclado (Enter): abre a linha em foco.
   */
  const leadsNaTela = useRef<Record<string, LeadWithOwner>>({})
  const linhaApertada = useRef<{ id: string; em: number } | null>(null)

  const INITIAL_DISPLAY = 25
  const DISPLAY_INCREMENT = 20
  const [displayLimit, setDisplayLimit] = useState(INITIAL_DISPLAY)

  const { results: searchResults, loading: searching } = useLeadSearch(search)

  // Rolagem infinita
  useEffect(() => {
    const el = scrollContainerRef.current
    if (!el) return
    const handleScroll = () => {
      const { scrollTop, scrollHeight, clientHeight } = el
      if (scrollHeight - scrollTop - clientHeight < 200) setDisplayLimit((prev) => prev + DISPLAY_INCREMENT)
    }
    el.addEventListener('scroll', handleScroll, { passive: true })
    return () => el.removeEventListener('scroll', handleScroll)
  }, [])

  // Fecha o menu de contexto ao clicar fora ou rolar
  useEffect(() => {
    const handleClose = () => setContextMenu((prev) => ({ ...prev, visible: false }))
    if (contextMenu.visible) {
      document.addEventListener('click', handleClose)
      document.addEventListener('scroll', handleClose, true)
      return () => {
        document.removeEventListener('click', handleClose)
        document.removeEventListener('scroll', handleClose, true)
      }
    }
  }, [contextMenu.visible])

  // Ids já marcados nesta tela: a segunda via do clique chega aqui duas vezes.
  const jaMarcados = useRef<Set<string>>(new Set())

  /*
   * "MARCAR COMO NÃO LIDA" (Pedro, 29/09/2026: "quando clicar no contato com o
   * botão direito poder colocar como não lido, para quando eu abrir uma
   * conversa sem querer, em todos os números"). A conversa marcada fica não
   * lida até o próximo CLIQUE nela: a leitura automática (trocar de conversa,
   * voltar para a janela) não desfaz -- senão a aberta voltava a lida na hora.
   */
  const naoLerSozinho = useRef<Set<string>>(new Set())

  const markLeadAsRead = useCallback((leadId: string, porClique = false) => {
    if (porClique) naoLerSozinho.current.delete(leadId)
    else if (naoLerSozinho.current.has(leadId)) return
    const lead = leads.find((l) => l.id === leadId)
    if (lead?.is_unread && !jaMarcados.current.has(leadId)) {
      jaMarcados.current.add(leadId)
      if (onUpdateLead) onUpdateLead(lead.id, { is_unread: false })
      fetch(`/api/leads/${lead.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_unread: false }) })
        .finally(() => { jaMarcados.current.delete(leadId) })
    }
  }, [leads, onUpdateLead])

  // Marca como lida quando a conversa aberta muda (e a janela está em foco)
  useEffect(() => {
    if (selectedLeadId && document.hasFocus()) markLeadAsRead(selectedLeadId)
  }, [selectedLeadId, markLeadAsRead])

  useEffect(() => {
    const handleFocus = () => { if (selectedLeadId) markLeadAsRead(selectedLeadId) }
    window.addEventListener('focus', handleFocus)
    return () => window.removeEventListener('focus', handleFocus)
  }, [selectedLeadId, markLeadAsRead])

  const handleContextMenu = useCallback((e: React.MouseEvent, lead: LeadWithOwner) => {
    e.preventDefault()
    e.stopPropagation()
    setContextMenu({ visible: true, x: e.clientX, y: e.clientY, lead })
  }, [])

  const handleTogglePin = useCallback(async () => {
    if (!contextMenu.lead) return
    const lead = contextMenu.lead
    const newPinned = !lead.is_pinned
    if (onUpdateLead) onUpdateLead(lead.id, { is_pinned: newPinned })
    setContextMenu((prev) => ({ ...prev, visible: false }))
    try {
      await fetch(`/api/leads/${lead.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_pinned: newPinned }) })
    } catch (err) {
      console.error('Failed to toggle pin', err)
      if (onUpdateLead) onUpdateLead(lead.id, { is_pinned: !newPinned })
    }
  }, [contextMenu.lead, onUpdateLead])

  const handleToggleUnread = useCallback(async () => {
    if (!contextMenu.lead) return
    const lead = contextMenu.lead
    const novo = !lead.is_unread
    setContextMenu((prev) => ({ ...prev, visible: false }))
    if (novo) naoLerSozinho.current.add(lead.id)
    else naoLerSozinho.current.delete(lead.id)
    if (onUpdateLead) onUpdateLead(lead.id, { is_unread: novo })
    try {
      const r = await fetch(`/api/leads/${lead.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_unread: novo }) })
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
    } catch (err) {
      console.error('Failed to toggle unread', err)
      naoLerSozinho.current.delete(lead.id)
      if (onUpdateLead) onUpdateLead(lead.id, { is_unread: !novo })
    }
  }, [contextMenu.lead, onUpdateLead])

  const handleToggleArchive = useCallback(async () => {
    if (!contextMenu.lead) return
    const lead = contextMenu.lead
    const newArchived = !lead.is_archived
    if (onUpdateLead) onUpdateLead(lead.id, { is_archived: newArchived })
    setContextMenu((prev) => ({ ...prev, visible: false }))
    try {
      await fetch(`/api/leads/${lead.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_archived: newArchived }) })
    } catch (err) {
      console.error('Failed to toggle archive', err)
      if (onUpdateLead) onUpdateLead(lead.id, { is_archived: !newArchived })
    }
  }, [contextMenu.lead, onUpdateLead])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <LoadingSpinner text="Carregando conversas..." />
      </div>
    )
  }

  const handleLeadClick = (lead: LeadWithOwner) => {
    onSelectLead(lead)
    markLeadAsRead(lead.id, true)
  }

  /*
   * A LISTA É DA LINHA DESTA ABA (Tel, 26/09/2026): a lista renderiza o
   * resultado da busca (que puxa a lista GLOBAL), então o filtro pela linha
   * tem que ser aqui -- inclusive na busca do servidor.
   */
  const daLinha: SearchHit[] = linha ? searchResults.filter((hit) => conversaEstaNaLinha(hit.lead, linha)) : searchResults

  const ordenados: SearchHit[] = [...daLinha].sort((a, b) => {
    const ap = !!a.lead.is_pinned
    const bp = !!b.lead.is_pinned
    if (ap !== bp) return ap ? -1 : 1
    const rank = (h: SearchHit) => (h.matchType === 'message' ? 1 : 0)
    if (rank(a) !== rank(b)) return rank(a) - rank(b)
    const ta = new Date(a.lead.last_activity_at || a.lead.created_at).getTime()
    const tb = new Date(b.lead.last_activity_at || b.lead.created_at).getTime()
    return tb - ta
  })

  const arquivadas = ordenados.filter((hit) => hit.lead.is_archived)
  const semArquivados = ordenados.filter((hit) => !hit.lead.is_archived)

  // Lista de CONVERSAS, não de leads cadastrados (ver ehConversaVisivel). Na
  // busca a regra é suspensa: aí a pessoa procura alguém para começar a falar.
  const visiveis = verArquivadas
    ? arquivadas
    : search.trim() ? semArquivados : semArquivados.filter((hit) => ehConversaVisivel(hit.lead))

  /* ── Os filtros de cima ── */
  const atendenteDoLead: Record<string, Atendente | undefined> = {}
  const contagem: Record<string, number> = { all: visiveis.length }
  const soma = (k: string) => { contagem[k] = (contagem[k] ?? 0) + 1 }
  const agora = Date.now()
  for (const hit of visiveis) {
    const l = hit.lead
    if (l.is_unread) soma('nao_lidas')
    // quem da equipe mandou a última mensagem pelo CRM (29/09: Tel e Rayssa,
    // pelo login de cada um) -- vale também na Parceria agora
    const atendente = atendenteDaConversa(l.autores_manuais, atendentePorId)
    atendenteDoLead[l.id] = atendente
    if (ehParceria) {
      const m = marcas[l.id]
      if (m?.proprietario) soma('proprietarios')
      if (m?.visitaAberta) soma('visitas')
      // "Tel": a Nay diz que ele está com a conversa OU ele mandou pelo login dele
      if (m?.telAtendendo || atendente?.nome === 'Tel') soma('tel')
      if (atendente && atendente.nome !== 'Tel') soma(`atendente:${atendente.id}`)
      for (const [k, ms] of JANELAS_DE_FOLLOWUP) if (esperandoResposta(l, ms, agora)) soma(k)
    } else {
      for (const lt of (l.lead_tags || []) as any[]) soma(`tag:${lt.tag_id}`)
      if (atendente) soma(`atendente:${atendente.id}`)
    }
  }

  const filtros: FiltroDaLista[] = ehParceria
    ? [
        { chave: 'all', rotulo: 'Todas', contagem: undefined },
        { chave: 'nao_lidas', rotulo: 'Não lidas', contagem: contagem.nao_lidas },
        { chave: 'proprietarios', rotulo: 'Proprietários', contagem: contagem.proprietarios, titulo: 'Quem a Nay sabe que é dono de imóvel' },
        { chave: 'visitas', rotulo: 'Visitas', contagem: contagem.visitas, titulo: 'Com visita em andamento' },
        { chave: 'tel', rotulo: 'Tel', contagem: contagem.tel, titulo: 'O Tel está atendendo (a Nay parou por ele, ou ele mandou pelo login dele)' },
        ...atendentes.filter((a) => a.nome !== 'Tel').map((a) => ({
          chave: `atendente:${a.id}`, rotulo: a.nome, cor: a.cor, contagem: contagem[`atendente:${a.id}`],
          titulo: `Conversas em que ${a.nome} mandou a última mensagem da equipe, pelo login dela`,
        })),
      ]
    : [
        { chave: 'all', rotulo: 'Todas' },
        { chave: 'nao_lidas', rotulo: 'Não lidas', contagem: contagem.nao_lidas },
        ...atendentes.map((a) => ({ chave: `atendente:${a.id}`, rotulo: a.nome, cor: a.cor, contagem: contagem[`atendente:${a.id}`], titulo: `Conversas que ${a.nome} está atendendo` })),
        ...(ETIQUETAS_DA_LINHA[linha ?? ''] ?? [])
          .map((nome) => allTags.find((t: any) => t.name === nome))
          .filter(Boolean)
          .map((t: any) => ({ chave: `tag:${t.id}`, rotulo: t.name, cor: t.color || '#8b5cf6', contagem: contagem[`tag:${t.id}`] })),
      ]

  /* FOLLOW-UP (Pedro, 29/09): "os filtros finais de últimas 6h ficam fora das
     tags, no lugar daquela barra de pesquisar" -- a última mensagem é da pessoa
     e ninguém respondeu. Mesmo estado das etiquetas: um filtro por vez. */
  const filtrosDeFollowup: FiltroDaLista[] = ehParceria ? [
    { chave: 'seg_6h', rotulo: 'Últimas 6h', contagem: contagem.seg_6h, titulo: 'A pessoa escreveu por último nas últimas 6 horas e ainda não respondemos' },
    { chave: 'seg_24h', rotulo: 'Últimas 24h', contagem: contagem.seg_24h, titulo: 'A pessoa escreveu por último nas últimas 24 horas e ainda não respondemos' },
    { chave: 'seg_semana', rotulo: 'Essa semana', contagem: contagem.seg_semana, titulo: 'A pessoa escreveu por último nos últimos 7 dias e ainda não respondemos' },
  ] : []

  const passaNoFiltro = (hit: SearchHit): boolean => {
    const l = hit.lead
    if (activeTab === 'all') return true
    if (activeTab === 'nao_lidas') return !!l.is_unread || l.id === selectedLeadId
    if (activeTab === 'proprietarios') return !!marcas[l.id]?.proprietario
    if (activeTab === 'visitas') return !!marcas[l.id]?.visitaAberta
    if (activeTab === 'tel') return !!marcas[l.id]?.telAtendendo || atendenteDoLead[l.id]?.nome === 'Tel'
    const janela = JANELAS_DE_FOLLOWUP.find(([k]) => k === activeTab)
    if (janela) return esperandoResposta(l, janela[1], agora)
    if (activeTab.startsWith('tag:')) return (l.lead_tags || []).some((lt: any) => `tag:${lt.tag_id}` === activeTab)
    if (activeTab.startsWith('atendente:')) return `atendente:${atendenteDoLead[l.id]?.id}` === activeTab
    return true
  }

  const filtradas = visiveis
    .filter(passaNoFiltro)
    .filter((hit) => selectedTagIds.length === 0 || hit.lead.lead_tags?.some((lt: any) => selectedTagIds.includes(lt.tag_id)))

  const visibleHits = filtradas.slice(0, displayLimit)
  leadsNaTela.current = Object.fromEntries(visibleHits.map((hit) => [hit.lead.id, hit.lead]))

  const leadDaLinha = (alvo: EventTarget | null): LeadWithOwner | undefined => {
    const el = (alvo as HTMLElement | null)?.closest?.('[data-lead-id]') as HTMLElement | null
    const id = el?.dataset.leadId
    return id ? leadsNaTela.current[id] : undefined
  }

  const aoApertar = (e: React.PointerEvent) => {
    const lead = leadDaLinha(e.target)
    linhaApertada.current = null
    if (!lead) return
    if (e.pointerType === 'mouse' && e.button !== 0) return // direito é o menu
    linhaApertada.current = { id: lead.id, em: Date.now() }
    if (e.pointerType === 'mouse') handleLeadClick(lead)
  }

  /* Clique: SEMPRE abre alguma conversa, nunca engole (ver o histórico em git). */
  const aoClicar = (e: React.MouseEvent) => {
    const apertada = linhaApertada.current
    linhaApertada.current = null
    if (apertada && Date.now() - apertada.em < 1500) {
      const lead = leadsNaTela.current[apertada.id]
      if (lead) { handleLeadClick(lead); return }
    }
    const lead = leadDaLinha(e.target)
    if (lead) handleLeadClick(lead)
  }

  return (
    <div className="flex flex-col h-full" style={{ background: 'var(--wa-panel)' }}>
      {/* O topo, como no WhatsApp: o nome da linha, a busca e os filtros */}
      <div className="flex-shrink-0 relative">
        <div className="wa-topo gap-2 !min-h-[56px]">
          {verArquivadas ? (
            <>
              <button type="button" className="wa-icone-btn -ml-2" onClick={() => setVerArquivadas(false)} aria-label="Voltar">
                <ArrowLeft size={22} />
              </button>
              <h1 className="text-[19px] font-medium" style={{ color: 'var(--wa-text)' }}>Arquivadas</h1>
            </>
          ) : (
            <div className="min-w-0">
              <h1 className="text-[20px] font-bold leading-6 truncate" style={{ color: 'var(--wa-text)' }}>{titulo || 'Conversas'}</h1>
              {numero && <p className="text-[12px] leading-4 truncate" style={{ color: 'var(--wa-text-2)' }}>{numero}</p>}
            </div>
          )}

          <div className="ml-auto flex items-center gap-1">
            {!verArquivadas && (
              <button type="button" onClick={() => setBuscaAberta((v) => !v)} aria-expanded={buscaAberta}
                      className={`wa-icone-btn ${buscaAberta || search ? 'wa-icone-btn--on' : ''}`} title="Pesquisar conversa (nome ou número)">
                <MagnifyingGlass size={20} />
              </button>
            )}
            {allTags.length > 0 && !verArquivadas && (
              <div className="relative" ref={tagFilterRef}>
                <button
                  type="button"
                  onClick={() => setTagFilterOpen((v) => !v)}
                  className={`wa-icone-btn relative ${selectedTagIds.length > 0 ? 'wa-icone-btn--on' : ''}`}
                  title="Filtrar por etiqueta"
                >
                  <TagIcon size={20} />
                  {selectedTagIds.length > 0 && (
                    <span className="wa-badge absolute -top-0.5 -right-0.5 !min-w-[16px] !h-4 !text-[10px] !px-1">{selectedTagIds.length}</span>
                  )}
                </button>
                {tagFilterOpen && (
                  <div className="absolute z-50 right-0 top-full mt-1 w-60 max-h-80 overflow-y-auto rounded-xl py-1.5 shadow-xl wa-rolagem"
                       style={{ background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}>
                    <div className="flex items-center justify-between px-3 py-1.5">
                      <span className="text-[11px] font-semibold uppercase tracking-wider" style={{ color: 'var(--wa-text-2)' }}>Etiquetas</span>
                      {selectedTagIds.length > 0 && (
                        <button type="button" onClick={() => setSelectedTagIds([])} className="text-[12px] font-semibold hover:underline" style={{ color: 'var(--wa-green)' }}>
                          Limpar
                        </button>
                      )}
                    </div>
                    {allTags.map((tag) => {
                      const on = selectedTagIds.includes(tag.id)
                      return (
                        <button key={tag.id} type="button" onClick={() => toggleTagFilter(tag.id)}
                                className="w-full flex items-center gap-2.5 px-3 py-2 text-left text-[14px] hover:bg-[var(--wa-row-hover)]"
                                style={{ color: 'var(--wa-text)' }}>
                          <span className="w-4 h-4 rounded flex items-center justify-center flex-shrink-0 border-2"
                                style={{ borderColor: tag.color, backgroundColor: on ? tag.color : 'transparent' }}>
                            {on && <Check size={11} weight="bold" className="text-white" />}
                          </span>
                          <span className="truncate">{tag.name}</span>
                        </button>
                      )
                    })}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>

        {/* a busca: a lupa abre o campo para baixo (Pedro, 29/09) */}
        {buscaAberta && !verArquivadas && (
          <div className="px-3 pb-2">
            <label className="wa-busca">
              <MagnifyingGlass size={18} />
              <input
                autoFocus
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Escape') { setSearch(''); setBuscaAberta(false) } }}
                placeholder="Pesquisar nome ou número"
                aria-label="Pesquisar conversas"
              />
              <button type="button" onClick={() => { setSearch(''); setBuscaAberta(false) }} aria-label="Fechar a busca"><X size={16} /></button>
            </label>
          </div>
        )}

        {!verArquivadas && (
          <>
            {filtrosDeFollowup.length > 0 && (
              <div className="flex items-center gap-1 pl-4 -mb-1">
                <span className="text-[12px] flex-shrink-0" style={{ color: 'var(--wa-text-2)' }}>Sem resposta:</span>
                <div className="flex-1 min-w-0 -ml-3">
                  <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtrosDeFollowup} />
                </div>
              </div>
            )}
            <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtros} />
          </>
        )}
      </div>

      {/* As conversas */}
      <div ref={scrollContainerRef} className="flex-1 overflow-y-auto overflow-x-hidden wa-rolagem">
        {!verArquivadas && !search.trim() && arquivadas.length > 0 && (
          <button type="button" onClick={() => setVerArquivadas(true)}
                  className="wa-linha !min-h-[48px]" style={{ color: 'var(--wa-text)' }}>
            <span className="w-[49px] flex justify-center"><Archive size={20} style={{ color: 'var(--wa-green)' }} /></span>
            <span className="flex-1 text-[16px]">Arquivadas</span>
            <span className="text-[12px] font-semibold" style={{ color: 'var(--wa-green)' }}>{arquivadas.length}</span>
          </button>
        )}

        {filtradas.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-[70%] px-8 text-center text-[14px]" style={{ color: 'var(--wa-text-2)' }}>
            {searching ? 'Buscando…'
              : search.trim() ? 'Nenhuma conversa encontrada'
              : activeTab !== 'all' ? 'Nenhuma conversa neste filtro'
              : verArquivadas ? 'Nenhuma conversa arquivada'
              : 'Nenhuma conversa ainda. Só aparece aqui quem já trocou mensagem.'}
          </div>
        ) : (
          <div
            className="flex flex-col pb-2"
            onPointerDown={aoApertar}
            onPointerCancel={() => { linhaApertada.current = null }}
            onClick={aoClicar}
          >
            {visibleHits.map((hit) => {
              const lead = hit.lead
              return (
                <LeadListItem
                  key={lead.id}
                  lead={lead}
                  isSelected={selectedLeadId === lead.id}
                  timeStr={formatRelativeTime(lead.last_activity_at || lead.created_at)}
                  onClick={handleLeadClick}
                  onContextMenu={handleContextMenu}
                  hit={hit}
                  query={search}
                  atendente={atendenteDoLead[lead.id] ?? atendenteDaConversa(lead.autores_manuais, atendentePorId)}
                  marca={ehParceria ? marcas[lead.id] : undefined}
                  nay={ehParceria ? nay : undefined}
                  dono={donos[lead.id]}
                />
              )
            })}
          </div>
        )}
      </div>

      {/* Menu do botão direito */}
      {contextMenu.visible && (
        <div
          ref={menuRef}
          className="fixed z-50 rounded-xl py-1.5 min-w-[200px] shadow-xl animate-in fade-in zoom-in-95 duration-150"
          style={{ left: contextMenu.x, top: contextMenu.y, background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)' }}
        >
          <button onClick={handleTogglePin} className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3" style={{ color: 'var(--wa-text)' }}>
            <PushPin size={17} className={contextMenu.lead?.is_pinned ? '' : '-rotate-45'} style={{ color: 'var(--wa-icon)' }} />
            {contextMenu.lead?.is_pinned ? 'Desafixar conversa' : 'Fixar conversa'}
          </button>
          <button onClick={handleToggleUnread} className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3" style={{ color: 'var(--wa-text)' }}>
            {contextMenu.lead?.is_unread
              ? <ChatCircleText size={17} style={{ color: 'var(--wa-icon)' }} />
              : <ChatCircleDots size={17} style={{ color: 'var(--wa-icon)' }} />}
            {contextMenu.lead?.is_unread ? 'Marcar como lida' : 'Marcar como não lida'}
          </button>
          <button onClick={handleToggleArchive} className="w-full text-left px-4 py-2.5 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3" style={{ color: 'var(--wa-text)' }}>
            {contextMenu.lead?.is_archived
              ? <ArrowCounterClockwise size={17} style={{ color: 'var(--wa-icon)' }} />
              : <Archive size={17} style={{ color: 'var(--wa-icon)' }} />}
            {contextMenu.lead?.is_archived ? 'Desarquivar conversa' : 'Arquivar conversa'}
          </button>
        </div>
      )}
    </div>
  )
}
