'use client'

import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { LeadWithOwner, SearchHit } from '@/lib/types'
import { MagnifyingGlass, PushPin, Archive, ArrowCounterClockwise, Tag as TagIcon, Check } from '@phosphor-icons/react'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import { useSession } from 'next-auth/react'
import { useLeadSearch } from '@/hooks/useLeadSearch'
import { DIAS_CONVERSA_IMPORTADA } from '@/lib/conversas'
import { useTags, useOrganizationMembers } from '@/hooks'
import { montarAtendentes, atendenteDaConversa, type Atendente } from '@/lib/atendentes'
import LeadListItem from './LeadListItem'
import ChatFilterTabs, { type ChatTab } from './ChatFilterTabs'
import { getWhatsAppWindowState } from '@/lib/whatsappWindow'

function isUrgent(lead: LeadWithOwner): boolean {
  const state = getWhatsAppWindowState(lead.last_activity_at)
  return state?.zone === 'warning' || state?.zone === 'critical'
}

/**
 * Conversa com o time: alguém respondeu à mão (pelo CRM ou pelo celular) ou o
 * lead respondeu a mensagem automática — é quando o funil passa pro humano.
 * Antes era só "a última mensagem foi nossa", e a conversa saía da aba assim
 * que o lead respondia. `last_message_sender_type` fica como reserva enquanto a
 * lista não chegou com o campo calculado.
 */
function isHumano(lead: LeadWithOwner): boolean {
  if (lead.is_group) return false
  return !!lead.em_atendimento_humano || lead.last_message_sender_type === 'human'
}

interface LeadListProps {
  leads: LeadWithOwner[]
  selectedLeadId?: string
  onSelectLead: (lead: LeadWithOwner) => void
  onUpdateLead?: (leadId: string, updates: Partial<LeadWithOwner>) => void
  loading: boolean
  organizationId?: string | null
}

const WEEKDAYS_PT = [
  'Domingo', 'Segunda-feira', 'Terça-feira', 'Quarta-feira',
  'Quinta-feira', 'Sexta-feira', 'Sábado',
]

function formatRelativeTime(dateString?: string) {
  if (!dateString) return ''
  const date = new Date(dateString)
  const today = new Date()

  const dateDay = new Date(date.getFullYear(), date.getMonth(), date.getDate())
  const todayDay = new Date(today.getFullYear(), today.getMonth(), today.getDate())

  const diffTime = todayDay.getTime() - dateDay.getTime()
  const diffDays = Math.round(diffTime / (1000 * 60 * 60 * 24))

  const hours = String(date.getHours()).padStart(2, '0')
  const minutes = String(date.getMinutes()).padStart(2, '0')
  const timeStr = `${hours}:${minutes}`

  if (diffDays === 0) return timeStr
  if (diffDays === 1) return `Ontem ${timeStr}`

  if (diffDays >= 2 && diffDays <= 6) {
    return `${WEEKDAYS_PT[date.getDay()]} ${timeStr}`
  }

  const d = String(date.getDate()).padStart(2, '0')
  const m = String(date.getMonth() + 1).padStart(2, '0')
  const y = date.getFullYear()
  return `${d}/${m}/${y}`
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
 * Três casos, nesta ordem:
 *   1. Com mensagem registrada aqui — sempre aparece, por mais antiga que seja.
 *      É conversa de verdade e não some nunca.
 *   2. Sem mensagem e sem `last_activity_type` — contato que nunca foi conversa
 *      (a planilha de 644 importada por CSV). Nunca aparece; a busca acha.
 *   3. Importada do WhatsApp e ainda sem mensagem aqui — aparece enquanto for
 *      recente. É o catálogo antigo do aparelho, que não pode enterrar o resto.
 */
function ehConversaVisivel(lead: LeadWithOwner): boolean {
  // Ter mensagem basta, com marcador de atividade ou sem: leads que só
  // receberam a mensagem do funil ficaram sem o marcador (bug corrigido na
  // origem) e sumiam do chat até a pessoa responder.
  const temMensagemAqui = !!lead.last_message_content || !!lead.last_message_sender_type
  if (temMensagemAqui) return true

  if (!lead.last_activity_type) return false

  if (!lead.last_activity_at) return false
  const limite = Date.now() - DIAS_CONVERSA_IMPORTADA * 24 * 60 * 60 * 1000
  return new Date(lead.last_activity_at).getTime() >= limite
}

export default function LeadList({
  leads,
  selectedLeadId,
  onSelectLead,
  onUpdateLead,
  loading,
  organizationId,
}: LeadListProps) {
  const [search, setSearch] = useState('')
  const [activeTab, setActiveTab] = useState<ChatTab>('all')
  const [contextMenu, setContextMenu] = useState<ContextMenuState>({
    visible: false, x: 0, y: 0, lead: null
  })
  const [seenReplies, setSeenReplies] = useState<Record<string, string>>({})

  // Filtro por etiqueta — multi-seleção, combina com a aba ativa (ex: "Não lidas" +
  // etiqueta "VIP" ao mesmo tempo) em vez de ser mais uma aba.
  const { allTags } = useTags(organizationId)

  // Abas por pessoa: só o time de atendimento (Augusto, Michele, Cau).
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
      if (tagFilterRef.current && !tagFilterRef.current.contains(e.target as Node)) {
        setTagFilterOpen(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [tagFilterOpen])

  const toggleTagFilter = (tagId: string) => {
    setSelectedTagIds((prev) => (prev.includes(tagId) ? prev.filter((id) => id !== tagId) : [...prev, tagId]))
  }

  // Load "seen" map from localStorage on mount
  useEffect(() => {
    try {
      const stored = localStorage.getItem('lead_seen_replies')
      if (stored) setSeenReplies(JSON.parse(stored))
    } catch {}
  }, [])

  const markReplySeen = useCallback((leadId: string, lastActivityAt?: string) => {
    if (!lastActivityAt) return
    setSeenReplies(prev => {
      if (prev[leadId] === lastActivityAt) return prev
      const next = { ...prev, [leadId]: lastActivityAt }
      try { localStorage.setItem('lead_seen_replies', JSON.stringify(next)) } catch {}
      return next
    })
  }, [])
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
   *
   * Fica na lista e não em cada linha porque, quando a lista anda, o "soltar"
   * cai em OUTRA linha — só quem enxerga todas sabe qual foi a tocada.
   */
  const leadsNaTela = useRef<Record<string, LeadWithOwner>>({})
  /** Linha apertada e quando — o clique seguinte abre ESTA, não a que estiver lá. */
  const linhaApertada = useRef<{ id: string; em: number } | null>(null)

  const INITIAL_DISPLAY = 20
  const DISPLAY_INCREMENT = 15
  const [displayLimit, setDisplayLimit] = useState(INITIAL_DISPLAY)

  const { results: searchResults, loading: searching } = useLeadSearch(search)

  // Infinite scroll
  useEffect(() => {
    const el = scrollContainerRef.current
    if (!el) return

    const handleScroll = () => {
      const { scrollTop, scrollHeight, clientHeight } = el
      if (scrollHeight - scrollTop - clientHeight < 200) {
        setDisplayLimit(prev => prev + DISPLAY_INCREMENT)
      }
    }

    el.addEventListener('scroll', handleScroll, { passive: true })
    return () => el.removeEventListener('scroll', handleScroll)
  }, [])

  // Close context menu on outside click or scroll
  useEffect(() => {
    const handleClose = () => setContextMenu(prev => ({ ...prev, visible: false }))
    if (contextMenu.visible) {
      document.addEventListener('click', handleClose)
      document.addEventListener('scroll', handleClose, true)
      return () => {
        document.removeEventListener('click', handleClose)
        document.removeEventListener('scroll', handleClose, true)
      }
    }
  }, [contextMenu.visible])

  // Ids já marcados nesta tela. Com a segunda via do clique (linha + lista), o
  // mesmo lead chega aqui duas vezes no mesmo instante; sem isto sairiam dois
  // PATCH iguais pra rede.
  const jaMarcados = useRef<Set<string>>(new Set())

  const markLeadAsRead = useCallback((leadId: string) => {
    const lead = leads.find(l => l.id === leadId)
    if (lead?.is_unread && !jaMarcados.current.has(leadId)) {
      jaMarcados.current.add(leadId)
      // Optimistic Update immediately to prevent duplicate network requests
      if (onUpdateLead) {
        onUpdateLead(lead.id, { is_unread: false })
      }

      // Send network request without awaiting here to avoid blocking
      fetch(`/api/leads/${lead.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_unread: false }) })
    }
  }, [leads, onUpdateLead])

  // Mark as read whenever the selected lead changes and has unread messages
  useEffect(() => {
    if (selectedLeadId && document.hasFocus()) {
      markLeadAsRead(selectedLeadId)
      const lead = leads.find(l => l.id === selectedLeadId)
      if (lead) markReplySeen(lead.id, lead.last_activity_at)
    }
  }, [selectedLeadId, markLeadAsRead, markReplySeen, leads])

  // Mark as read when the window gains focus (if reading currently)
  useEffect(() => {
    const handleFocus = () => {
      if (selectedLeadId) {
        markLeadAsRead(selectedLeadId)
      }
    }

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

    // Optimistic update
    if (onUpdateLead) {
      onUpdateLead(lead.id, { is_pinned: newPinned })
    }

    setContextMenu(prev => ({ ...prev, visible: false }))

    try {
      await fetch(`/api/leads/${lead.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_pinned: newPinned }) })
    } catch (err) {
      console.error('Failed to toggle pin', err)
      // Revert
      if (onUpdateLead) {
        onUpdateLead(lead.id, { is_pinned: !newPinned })
      }
    }
  }, [contextMenu.lead, onUpdateLead])

  const handleToggleArchive = useCallback(async () => {
    if (!contextMenu.lead) return
    const lead = contextMenu.lead
    const newArchived = !lead.is_archived

    // Optimistic update
    if (onUpdateLead) {
      onUpdateLead(lead.id, { is_archived: newArchived })
    }

    setContextMenu(prev => ({ ...prev, visible: false }))

    try {
      await fetch(`/api/leads/${lead.id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ is_archived: newArchived }) })
    } catch (err) {
      console.error('Failed to toggle archive', err)
      // Revert
      if (onUpdateLead) {
        onUpdateLead(lead.id, { is_archived: !newArchived })
      }
    }
  }, [contextMenu.lead, onUpdateLead])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-full">
        <LoadingSpinner text="Carregando leads..." />
      </div>
    )
  }

  const handleLeadClick = async (lead: LeadWithOwner) => {
    onSelectLead(lead)
    markLeadAsRead(lead.id)
    markReplySeen(lead.id, lead.last_activity_at)
  }

  const filteredHits: SearchHit[] = [...searchResults].sort((a, b) => {
    const ap = !!a.lead.is_pinned
    const bp = !!b.lead.is_pinned
    if (ap !== bp) return ap ? -1 : 1
    const rank = (h: SearchHit) => (h.matchType === 'message' ? 1 : 0)
    if (rank(a) !== rank(b)) return rank(a) - rank(b)
    const ta = new Date(a.lead.last_activity_at || a.lead.created_at).getTime()
    const tb = new Date(b.lead.last_activity_at || b.lead.created_at).getTime()
    return tb - ta
  })

  // Arquivada some das outras abas (igual WhatsApp) — só a aba "Arquivados" mostra.
  const semArquivados = filteredHits.filter((hit) => !hit.lead.is_archived)

  // Lista de CONVERSAS, não de leads cadastrados. Um lead sem nenhuma mensagem
  // não é conversa: depois de importar uma planilha de 644 contatos, o chat
  // virava 644 entradas vazias e a conversa de verdade sumia no meio.
  //
  // `last_activity_type` é o marcador certo: nulo até a primeira mensagem, e
  // preenchido por qualquer caminho que registre atividade. `last_activity_at`
  // não serve — a importação preenche.
  //
  // Durante uma busca a regra é suspensa de propósito: aí a pessoa está
  // procurando alguém específico pra começar a falar, e esconder quem ainda não
  // tem conversa impediria justamente isso.
  const nonArchivedHits = search.trim()
    ? semArquivados
    : semArquivados.filter((hit) => ehConversaVisivel(hit.lead))

  const tabCounts: Record<string, number> = { all: nonArchivedHits.length, human: 0, urgent: 0 }
  const atendenteDoLead: Record<string, Atendente | undefined> = {}
  for (const hit of nonArchivedHits) {
    if (isHumano(hit.lead)) tabCounts.human++
    if (isUrgent(hit.lead)) tabCounts.urgent++
    const atendente = atendenteDaConversa(hit.lead.autores_manuais, atendentePorId)
    atendenteDoLead[hit.lead.id] = atendente
    if (atendente) tabCounts[`atendente:${atendente.id}`] = (tabCounts[`atendente:${atendente.id}`] ?? 0) + 1
  }

  const tabFilteredHitsBeforeTags = activeTab === 'all'
    ? nonArchivedHits
    : activeTab === 'human'
      ? nonArchivedHits.filter((hit) => isHumano(hit.lead))
      : activeTab === 'urgent'
        ? nonArchivedHits.filter((hit) => isUrgent(hit.lead))
        : nonArchivedHits.filter((hit) => `atendente:${atendenteDoLead[hit.lead.id]?.id}` === activeTab)

  // Etiqueta é um filtro à parte, combinado com a aba ativa — não substitui, só
  // restringe mais. Mantém quem tem pelo menos uma das etiquetas marcadas.
  const tabFilteredHits = selectedTagIds.length === 0
    ? tabFilteredHitsBeforeTags
    : tabFilteredHitsBeforeTags.filter((hit) =>
        hit.lead.lead_tags?.some((lt: any) => selectedTagIds.includes(lt.tag_id))
      )

  const visibleHits = tabFilteredHits.slice(0, displayLimit)
  leadsNaTela.current = Object.fromEntries(visibleHits.map((hit) => [hit.lead.id, hit.lead]))

  const leadDaLinha = (alvo: EventTarget | null): LeadWithOwner | undefined => {
    const linha = (alvo as HTMLElement | null)?.closest?.('[data-lead-id]') as HTMLElement | null
    const id = linha?.dataset.leadId
    return id ? leadsNaTela.current[id] : undefined
  }

  const aoApertar = (e: React.PointerEvent) => {
    const lead = leadDaLinha(e.target)
    linhaApertada.current = null
    if (!lead) return
    if (e.pointerType === 'mouse' && e.button !== 0) return // direito é o menu
    linhaApertada.current = { id: lead.id, em: Date.now() }
    // Mouse abre já no apertar; toque espera virar clique (senão rolar a lista
    // abriria conversa a cada arrasto).
    if (e.pointerType === 'mouse') handleLeadClick(lead)
  }

  /*
   * Clique: SEMPRE abre alguma conversa, nunca engole.
   *
   * A versão anterior tinha um estado de "já abri no apertar" que suprimia o
   * clique. Quando esse estado ficava preso (o apertar terminou fora da lista,
   * por exemplo), o clique seguinte era descartado e nada abria. Agora não há
   * supressão: vale a linha APERTADA se o apertar foi agora há pouco, senão a
   * linha onde o clique caiu. Abrir a mesma conversa duas vezes não faz mal.
   */
  const aoClicar = (e: React.MouseEvent) => {
    const apertada = linhaApertada.current
    linhaApertada.current = null
    if (apertada && Date.now() - apertada.em < 1500) {
      const lead = leadsNaTela.current[apertada.id]
      if (lead) {
        handleLeadClick(lead)
        return
      }
    }
    const lead = leadDaLinha(e.target) // teclado, ou linha que saiu da tela
    if (lead) handleLeadClick(lead)
  }

  return (
    <div className="flex flex-col h-full border-r border-[var(--chat-border)] bg-[var(--chat-bg-base)] surface-rail">
      {/* Search Bar */}
      <div className="p-3 border-b border-[var(--chat-border)]">
        <div className="flex items-center gap-2">
          <div className="relative flex-1">
            <MagnifyingGlass className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-[var(--chat-text-muted)]" />
            <input
              type="text"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Buscar leads..."
              className="glass-sunken w-full pl-9 pr-3 py-2 text-sm rounded-xl focus:outline-none focus:ring-2 focus:ring-white/10 focus:border-[var(--chat-accent)]/40 text-[var(--chat-text-primary)] placeholder-[var(--chat-text-muted)] transition-all"
            />
          </div>

          {allTags.length > 0 && (
            <div className="relative flex-shrink-0" ref={tagFilterRef}>
              <button
                type="button"
                onClick={() => setTagFilterOpen((v) => !v)}
                className={`relative flex items-center justify-center w-9 h-9 rounded-xl border transition-colors ${
                  selectedTagIds.length > 0
                    ? 'border-[var(--chat-accent)] text-[var(--chat-accent)] bg-white/[0.08]'
                    : 'border-[var(--chat-border)] text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] hover:bg-white/[0.06]'
                }`}
                title="Filtrar por etiqueta"
              >
                <TagIcon size={16} />
                {selectedTagIds.length > 0 && (
                  <span className="absolute -top-1.5 -right-1.5 min-w-[16px] h-4 px-1 rounded-full bg-[var(--chat-accent)] text-[var(--chat-bg-conversation)] text-[10px] font-bold flex items-center justify-center">
                    {selectedTagIds.length}
                  </span>
                )}
              </button>

              {tagFilterOpen && (
                <div className="glass-raised absolute z-50 right-0 top-full mt-1.5 w-56 max-h-80 overflow-y-auto rounded-xl py-1.5">
                  <div className="flex items-center justify-between px-3 py-1.5">
                    <span className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)]">
                      Etiquetas
                    </span>
                    {selectedTagIds.length > 0 && (
                      <button
                        type="button"
                        onClick={() => setSelectedTagIds([])}
                        className="text-[11px] font-semibold text-[var(--chat-accent)] hover:underline"
                      >
                        Limpar
                      </button>
                    )}
                  </div>
                  {allTags.map((tag) => {
                    const isSelected = selectedTagIds.includes(tag.id)
                    return (
                      <button
                        key={tag.id}
                        type="button"
                        onClick={() => toggleTagFilter(tag.id)}
                        className="w-full flex items-center gap-2.5 px-3 py-2 text-left text-sm text-[var(--chat-text-primary)] hover:bg-white/[0.07] transition-colors"
                      >
                        <span
                          className={`w-4 h-4 rounded flex items-center justify-center flex-shrink-0 border-2 transition-colors`}
                          style={{
                            borderColor: tag.color,
                            backgroundColor: isSelected ? tag.color : 'transparent',
                          }}
                        >
                          {isSelected && <Check size={11} weight="bold" className="text-white" />}
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

      <ChatFilterTabs activeTab={activeTab} onChange={setActiveTab} counts={tabCounts} atendentes={atendentes} />

      {/* Leads List */}
      <div ref={scrollContainerRef} className="flex-1 overflow-y-auto overflow-x-hidden chat-dark-scroll">
        {tabFilteredHits.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full px-6 text-center text-[var(--chat-text-muted)] text-sm">
            {searching ? (
              'Buscando…'
            ) : search.trim() ? (
              'Nenhum lead encontrado'
            ) : (
              <>
                <p>Nenhuma conversa ainda.</p>
                <p className="text-xs mt-1.5 leading-relaxed">
                  Só aparece aqui quem já trocou mensagem. Para começar uma, use
                  o botão <span className="text-[var(--chat-text-primary)]">Enviar mensagem</span> em
                  Configurações → Leads, ou busque a pessoa pelo nome acima.
                </p>
              </>
            )}
          </div>
        ) : (
          <div
            className="flex flex-col min-h-full"
            onPointerDown={aoApertar}
            onPointerCancel={() => { linhaApertada.current = null }}
            onClick={aoClicar}
          >
            {visibleHits.map((hit) => {
              const lead = hit.lead
              const isSelected = selectedLeadId === lead.id
              const timeStr = formatRelativeTime(lead.last_activity_at || lead.created_at)
              const hideReplyHighlight = !!lead.last_activity_at && seenReplies[lead.id] === lead.last_activity_at

              return (
                <LeadListItem
                  key={lead.id}
                  lead={lead}
                  isSelected={isSelected}
                  timeStr={timeStr}
                  onClick={handleLeadClick}
                  onContextMenu={handleContextMenu}
                  hit={hit}
                  query={search}
                  hideReplyHighlight={hideReplyHighlight}
                  atendente={atendenteDoLead[lead.id] ?? atendenteDaConversa(lead.autores_manuais, atendentePorId)}
                />
              )
            })}
          </div>
        )}
      </div>

      {/* Context Menu */}
      {contextMenu.visible && (
        <div
          ref={menuRef}
          className="glass-raised fixed z-50 rounded-xl py-1.5 min-w-[180px] animate-in fade-in zoom-in-95 duration-150"
          style={{
            left: contextMenu.x,
            top: contextMenu.y,
          }}
        >
          <button
            onClick={handleTogglePin}
            className="w-full text-left px-4 py-2 text-sm text-[var(--chat-text-primary)] hover:bg-white/[0.07] flex items-center gap-2.5 transition-colors"
          >
            <PushPin size={16} weight={contextMenu.lead?.is_pinned ? 'regular' : 'fill'} className={contextMenu.lead?.is_pinned ? 'text-[var(--chat-text-muted)]' : 'text-[var(--chat-accent)] -rotate-45'} />
            {contextMenu.lead?.is_pinned ? 'Desafixar conversa' : 'Fixar conversa'}
          </button>
          <button
            onClick={handleToggleArchive}
            className="w-full text-left px-4 py-2 text-sm text-[var(--chat-text-primary)] hover:bg-white/[0.07] flex items-center gap-2.5 transition-colors"
          >
            {contextMenu.lead?.is_archived ? (
              <ArrowCounterClockwise size={16} className="text-[var(--chat-text-muted)]" />
            ) : (
              <Archive size={16} className="text-[var(--chat-text-muted)]" />
            )}
            {contextMenu.lead?.is_archived ? 'Desarquivar conversa' : 'Arquivar conversa'}
          </button>
        </div>
      )}
    </div>
  )
}
