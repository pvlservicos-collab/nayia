'use client'

import { useState, useRef, useEffect } from 'react'
import {
  EnvelopeSimple,
  Phone,
  Flag,
  Sparkle,
  Plus,
  User,
  X,
  Tag as PhosphorTag,
  CalendarBlank,
  MapPin,
  PencilSimple,
  Check,
  CaretDown,
  CaretRight,
  Pause,
  ChatText,
  ShoppingCart,
  Trash,
  InstagramLogo,
  Briefcase,
  Database,
} from '@phosphor-icons/react'
import { CustomFieldDefinition, LeadWithOwner, PipelineStage, LeadStageHistory, Pipeline } from '@/lib/types'
import { useSession } from 'next-auth/react'
import { getInitials, formatPhone, formatRelativeTime } from '@/lib/utils'
import { getWhatsAppWindowState, WHATSAPP_WINDOW_ZONE_COLOR } from '@/lib/whatsappWindow'
import FunnelMiniMap from './FunnelMiniMap'
import LeadHistoryTimeline from './LeadHistoryTimeline'
import { useTags, useCustomFields, useChatButtonSettings, useAuth } from '@/hooks'
import { useOrganizationMembers } from '@/hooks/useOrganizationMembers'
import { useNotification } from '@/contexts/NotificationContext'
import { ChatButtonKey } from '@/hooks/useChatButtonSettings'
import DebouncedInput from '@/components/Shared/DebouncedInput'
import IntegrationBadge from '@/components/Shared/IntegrationBadge'
import LeadBadges from '@/components/Shared/LeadBadges'
import CustomFieldSelect from '@/components/Shared/CustomFieldSelect'
import CustomFieldMultiSelect from '@/components/Shared/CustomFieldMultiSelect'
import OrderModal from './OrderModal'
import LeadOrderCard from './LeadOrderCard'
import LeadAgendaCard from './LeadAgendaCard'

interface LeadDetailsSidebarProps {
  lead: LeadWithOwner
  stages: PipelineStage[]
  stageHistory: LeadStageHistory[]
  stageHistoryLoading?: boolean
  onStageChange?: (newStageId: string) => void
  onTagsChange?: (leadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => void
  onUpdateLead?: (leadId: string, updates: Partial<LeadWithOwner>) => void
  pipelines?: Pipeline[]
  currentPipelineId?: string
  onPipelineChange?: (pipelineId: string) => void
  /** Só passado quando renderizado como overlay em tela cheia no mobile — exibe um botão de fechar. */
  onClose?: () => void
  /** Só passado por quem abre esse painel de fora de uma conversa já ativa (ex: Pipeline)
   * — exibe um botão "Ver conversa". O próprio Chat não passa, já está dentro dela. */
  onGoToConversation?: () => void
}

interface Appointment {
  id: string
  title: string
  date: string
}

const PROFESSIONAL_FIELDS: { key: 'profession' | 'company' | 'role'; label: string; placeholder: string }[] = [
  { key: 'profession', label: 'Profissão', placeholder: 'Adicionar profissão...' },
  { key: 'company', label: 'Empresa', placeholder: 'Adicionar empresa...' },
  { key: 'role', label: 'Cargo', placeholder: 'Adicionar cargo...' },
]


export default function LeadDetailsSidebar({
  lead,
  stages,
  stageHistory,
  stageHistoryLoading,
  onStageChange,
  onTagsChange,
  onUpdateLead,
  pipelines,
  currentPipelineId,
  onPipelineChange,
  onClose,
  onGoToConversation,
}: LeadDetailsSidebarProps) {
  const ownerName = lead.owner?.profiles?.full_name || ''
  const ownerInitials = ownerName
    ? ownerName.split(' ').map((n) => n[0]).join('').slice(0, 2).toUpperCase()
    : ''

  const { currentOrganization, user, profileName, isMaster, roleName } = useAuth()
  const { addNotification } = useNotification()
  const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner'
  const [deletingHistory, setDeletingHistory] = useState(false)

  const { allTags, leadTags, addTagToLead, removeTagFromLead, loading: tagsLoading } = useTags(lead.organization_id, lead.id)
  const { categories, definitions, values, updateFieldValue } = useCustomFields(lead.organization_id, lead.id, lead.custom_attributes)
  const { settings: chatButtonSettings, fireWebhook } = useChatButtonSettings()
  const { members: orgMembers } = useOrganizationMembers(lead.organization_id)
  const [showTagMenu, setShowTagMenu] = useState(false)
  const tagMenuRef = useRef<HTMLDivElement>(null)
  const [showOwnerMenu, setShowOwnerMenu] = useState(false)
  const [savingOwner, setSavingOwner] = useState(false)
  const ownerMenuRef = useRef<HTMLDivElement>(null)

  const [collapsedCategories, setCollapsedCategories] = useState<Set<string>>(new Set())

  const [isEditingName, setIsEditingName] = useState(false)
  const [editingNameValue, setEditingNameValue] = useState(lead.title)
  const editNameInputRef = useRef<HTMLInputElement>(null)

  const [showOrderModal, setShowOrderModal] = useState(false)
  const [orderRefreshKey, setOrderRefreshKey] = useState(0)

  // Recalcula a janela de 24h a cada minuto — sem isso, a barra e o rótulo
  // ficariam parados no valor de quando o componente montou.
  const [, forceTick] = useState(0)
  useEffect(() => {
    const interval = setInterval(() => forceTick((t) => t + 1), 60_000)
    return () => clearInterval(interval)
  }, [])
  const windowState = getWhatsAppWindowState(lead.last_activity_at)

  // Central de DADOS — agenda de compromissos e definições profissionais. Sem
  // tabela própria ainda, fica só na sessão (não persiste ao recarregar).
  const [appointments, setAppointments] = useState<Appointment[]>([])
  const [newAppointmentTitle, setNewAppointmentTitle] = useState('')
  const [newAppointmentDate, setNewAppointmentDate] = useState('')
  const [professionalInfo, setProfessionalInfo] = useState<Record<string, string>>({})
  const [webhookStatus, setWebhookStatus] = useState<{
    key: ChatButtonKey
    status: 'sending' | 'success' | 'error'
  } | null>(null)

  const handleSidebarWebhook = async (key: ChatButtonKey) => {
    setWebhookStatus({ key, status: 'sending' })
    const ok = await fireWebhook(key, { ...lead, stageName: stages.find((s) => s.id === lead.stage_id)?.name })
    setWebhookStatus({ key, status: ok ? 'success' : 'error' })
    setTimeout(() => setWebhookStatus(null), 2500)
  }

  const getSidebarButtonStyles = (key: ChatButtonKey, hoverClass: string) => {
    const isThisButton = webhookStatus?.key === key
    const status = isThisButton ? webhookStatus?.status : null

    const base = "flex flex-col items-center justify-center gap-1.5 h-[76px] px-2 border rounded-xl transition-all duration-200 active:scale-[0.96]"

    if (status === 'success') return `${base} bg-emerald-500/10 border-emerald-500/30 shadow-sm ring-1 ring-emerald-500/10`
    if (status === 'error') return `${base} bg-red-500/10 border-red-500/30 shadow-sm ring-1 ring-red-500/10`
    if (status === 'sending') return `${base} bg-[var(--chat-bg-field)] border-[var(--chat-border)] opacity-80 cursor-wait`

    return `${base} bg-[var(--chat-bg-field)] border-[var(--chat-border)] hover:${hoverClass}`
  }

  const renderSidebarButtonIcon = (key: ChatButtonKey, DefaultIcon: any, colorClass: string) => {
    const isThisButton = webhookStatus?.key === key
    const status = isThisButton ? webhookStatus?.status : null

    if (status === 'success') return <Check size={24} weight="bold" className="text-emerald-400 animate-in zoom-in duration-200" />
    if (status === 'error') return <X size={24} weight="bold" className="text-red-400 animate-in zoom-in duration-200" />
    if (status === 'sending') return (
      <svg className="animate-spin h-5 w-5 text-[var(--chat-text-tertiary)]" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
      </svg>
    )

    return <DefaultIcon size={24} className={colorClass} />
  }

  const getSidebarButtonTextClass = (key: ChatButtonKey) => {
    const isThisButton = webhookStatus?.key === key
    const status = isThisButton ? webhookStatus?.status : null

    if (status === 'success') return 'text-emerald-400'
    if (status === 'error') return 'text-red-400'
    return 'text-[var(--chat-text-secondary)]'
  }

  useEffect(() => {
    setEditingNameValue(lead.title)
  }, [lead.title])

  useEffect(() => {
    if (isEditingName && editNameInputRef.current) {
      editNameInputRef.current.focus()
    }
  }, [isEditingName])

  // Close tag menu on click outside
  useEffect(() => {
    if (!showTagMenu) return
    function handleClickOutside(e: MouseEvent) {
      if (tagMenuRef.current && !tagMenuRef.current.contains(e.target as Node)) {
        setShowTagMenu(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [showTagMenu])

  // Close owner menu on click outside
  useEffect(() => {
    if (!showOwnerMenu) return
    function handleClickOutside(e: MouseEvent) {
      if (ownerMenuRef.current && !ownerMenuRef.current.contains(e.target as Node)) {
        setShowOwnerMenu(false)
      }
    }
    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [showOwnerMenu])

  const handleAssignOwner = async (memberId: string | null) => {
    setShowOwnerMenu(false)
    if (memberId === (lead.owner_member_id || null)) return
    setSavingOwner(true)
    try {
      const res = await fetch(`/api/leads/${lead.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ owner_member_id: memberId }),
      })
      if (!res.ok) { const d = await res.json().catch(() => ({})); throw new Error(d.error || 'Falha ao atribuir responsável') }
      const member = memberId ? orgMembers.find((m) => m.id === memberId) : null
      if (onUpdateLead) {
        onUpdateLead(lead.id, {
          owner_member_id: memberId || undefined,
          owner: member ? { id: member.id, profiles: { full_name: member.profiles?.full_name || '', avatar_url: member.profiles?.avatar_url } } : undefined,
        })
      }
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Falha ao atribuir responsável',
        message: err instanceof Error ? err.message : 'Erro desconhecido.',
      })
    } finally {
      setSavingOwner(false)
    }
  }

  const handleSaveName = async () => {
    const trimmed = editingNameValue.trim()
    setIsEditingName(false)
    if (!trimmed || trimmed === lead.title) {
      setEditingNameValue(lead.title)
      return
    }

    const oldName = lead.title

    // Optimistic update
    if (onUpdateLead) {
      onUpdateLead(lead.id, { title: trimmed })
    }

    const res = await fetch(`/api/leads/${lead.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: trimmed }),
    })

    if (!res.ok) {
      console.error('Failed to update lead name')
      if (onUpdateLead) onUpdateLead(lead.id, { title: oldName })
      setEditingNameValue(oldName)
    } else {
      await fetch(`/api/leads/${lead.id}/activities`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          type: 'system',
          content: `Membro renomeou o lead de "${formatPhone(oldName)}" para "${formatPhone(trimmed)}".`,
          metadata: { source: 'rename', sender_name: profileName || user?.email || 'Usuário' },
        }),
      })
    }
  }

  // Salva um campo de contato/endereço direto (sem modo de edição separado, como o
  // nome tem) — mesmo padrão debounced já usado nos campos customizados abaixo.
  const saveContactField = async (field: string, value: string) => {
    const trimmed = value.trim()
    const prevValue = (lead as any)[field] ?? null
    if (trimmed === (prevValue || '')) return

    if (onUpdateLead) onUpdateLead(lead.id, { [field]: trimmed || null } as any)

    try {
      const res = await fetch(`/api/leads/${lead.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ [field]: trimmed || null }),
      })
      if (!res.ok) throw new Error('Falha ao salvar')
    } catch (err) {
      console.error(`Failed to update lead field ${field}`, err)
      if (onUpdateLead) onUpdateLead(lead.id, { [field]: prevValue } as any)
    }
  }

  const addAppointment = () => {
    const title = newAppointmentTitle.trim()
    if (!title || !newAppointmentDate) return
    setAppointments(prev => [...prev, { id: `apt-${Date.now()}`, title, date: newAppointmentDate }].sort((a, b) => a.date.localeCompare(b.date)))
    setNewAppointmentTitle('')
    setNewAppointmentDate('')
  }

  const removeAppointment = (id: string) => {
    setAppointments(prev => prev.filter(a => a.id !== id))
  }

  const handleDeleteHistory = async () => {
    if (deletingHistory) return
    if (!confirm(`Apagar todo o histórico de mensagens da conversa com "${formatPhone(lead.title)}"? O contato continua no CRM, só as mensagens somem. Essa ação não pode ser desfeita.`)) return

    setDeletingHistory(true)
    try {
      const res = await fetch(`/api/leads/${lead.id}/messages`, { method: 'DELETE' })
      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        throw new Error(err.error || 'Falha ao apagar histórico.')
      }
      if (onUpdateLead) {
        onUpdateLead(lead.id, { last_message_content: undefined, last_message_sender_type: undefined })
      }
      addNotification({ type: 'success', title: 'Histórico apagado', message: 'As mensagens da conversa foram removidas.' })
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Falha ao apagar histórico',
        message: err instanceof Error ? err.message : 'Erro desconhecido.',
      })
    } finally {
      setDeletingHistory(false)
    }
  }

  // Only fallback to lead.lead_tags while the hook is still loading.
  // Once loaded, trust the hook data (even if empty — that means no tags exist).
  const displayTags = tagsLoading ? (lead.lead_tags || []) : leadTags

  return (
    <>
    <div className="w-full md:w-72 border-l border-[var(--chat-border)] flex flex-col flex-shrink-0 overflow-y-auto bg-[var(--chat-bg-base)] surface-rail chat-dark-scroll">
      {onClose && (
        <div className="flex items-center justify-between px-4 h-14 border-b border-[var(--chat-border)] flex-shrink-0 md:hidden">
          <span className="text-sm font-semibold text-[var(--chat-text-primary)]">Detalhes do contato</span>
          <button onClick={onClose} className="w-8 h-8 flex items-center justify-center rounded-lg text-[var(--chat-text-muted)] hover:text-[var(--chat-text-primary)] hover:bg-[var(--chat-bg-field)] transition-colors">
            <X size={20} />
          </button>
        </div>
      )}
      <div className="p-5 space-y-5">
        {/* Lead Avatar + Name + Tags */}
        <div className="text-center flex flex-col items-center">
          <div className="relative inline-block mb-3">
            <div className="w-16 h-16 rounded-full bg-[var(--chat-bg-hover)] flex items-center justify-center overflow-hidden border-2 border-[var(--chat-bg-base)] shadow-sm">
              {lead.avatar_url ? (
                <img src={lead.avatar_url} alt={lead.title} className="w-full h-full object-cover" />
              ) : (
                <span className="text-xl font-bold text-[var(--chat-accent)]">{getInitials(lead.title)}</span>
              )}
            </div>
            <IntegrationBadge lead={lead} size="lg" />
          </div>

          <div className="flex items-center justify-center group mb-3 w-full px-2">
            {isEditingName ? (
              <div className="flex items-center flex-1 max-w-[85%] gap-2 mb-1 mt-0.5">
                <input
                  ref={editNameInputRef}
                  type="text"
                  value={editingNameValue}
                  onChange={(e) => setEditingNameValue(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === 'Enter') handleSaveName()
                    if (e.key === 'Escape') {
                      setIsEditingName(false)
                      setEditingNameValue(lead.title)
                    }
                  }}
                  onBlur={handleSaveName}
                  className="w-full text-center font-display font-bold text-xl text-[var(--chat-text-primary)] focus:outline-none px-1 py-0.5 bg-transparent border-b-2 border-[var(--chat-border)] focus:border-[var(--chat-accent)] min-w-0 transition-colors"
                />
                <button
                  onMouseDown={(e) => { e.preventDefault(); handleSaveName(); }}
                  className="bg-[var(--chat-bg-hover)] hover:bg-[var(--chat-accent)] hover:text-[var(--chat-bg-conversation)] text-[var(--chat-accent)] p-1 rounded transition-colors flex-shrink-0"
                  title="Salvar (Enter)"
                >
                  <Check weight="bold" size={16} />
                </button>
              </div>
            ) : (
              <h2 className="font-display font-bold text-xl text-[var(--chat-text-primary)] group-hover:text-[var(--chat-text-secondary)] transition-colors relative inline-flex items-center max-w-[85%]">
                <span className="truncate" title={lead.title}>{formatPhone(lead.title)}</span>
                <button
                  onClick={() => setIsEditingName(true)}
                  className="p-1 text-[var(--chat-text-muted)] hover:text-[var(--chat-accent)] hover:bg-[var(--chat-bg-hover)] rounded-full transition-all opacity-0 group-hover:opacity-100 absolute left-full ml-1"
                  title="Renomear"
                >
                  <PencilSimple weight="bold" size={16} />
                </button>
              </h2>
            )}
          </div>

          {/* @usuário do Instagram, pequeno, embaixo do nome */}
          {lead.custom_attributes?.instagram_username && (
            <a
              href={`https://instagram.com/${lead.custom_attributes.instagram_username}`}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-1 text-[11px] text-[var(--chat-text-muted)] hover:text-[var(--chat-accent)] hover:underline mb-2 -mt-2"
            >
              <InstagramLogo size={11} className="flex-shrink-0" />
              @{lead.custom_attributes.instagram_username}
            </a>
          )}

          {(lead.is_group || lead.integration?.type === 'instagram_direct' || lead.integration?.type === 'whatsapp_evolution') && (
            <div className="flex items-center justify-center flex-wrap gap-1.5 mb-3">
              <LeadBadges lead={lead} size="md" />
            </div>
          )}

          {onGoToConversation && (
            <button
              onClick={onGoToConversation}
              className="w-full mb-3 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl text-sm font-bold bg-[var(--chat-accent)] text-[var(--chat-bg-conversation)] hover:opacity-90 transition-opacity"
            >
              <ChatText size={16} weight="bold" />
              Ver conversa
            </button>
          )}

          <style>{`
            .tag-pill .tag-x {
              opacity: 0;
              pointer-events: none;
              transition: opacity 0.2s ease;
              margin-left: 2px;
            }
            .tag-pill:hover .tag-x {
              opacity: 1;
              pointer-events: auto;
            }
          `}</style>

          {/* Tags row */}
          {displayTags.length > 0 && (
            <div className="flex items-center justify-center gap-1.5 flex-wrap mb-2">
              {displayTags.map((lt: any) => {
                const tag = lt.tag || allTags.find(t => t.id === lt.tag_id)
                if (!tag) return null
                const tagColor = tag.color?.startsWith('#') ? tag.color : 'var(--chat-accent)'

                return (
                  <span
                    key={lt.tag_id}
                    className="tag-pill text-[9px] uppercase font-bold tracking-wide px-2 py-0.5 rounded-full flex items-center cursor-default"
                    style={{
                      backgroundColor: `${tagColor}1A`,
                      color: tagColor,
                    }}
                  >
                    {tag.name}
                    <button
                      onClick={(e) => {
                        e.stopPropagation()
                        e.preventDefault()
                        removeTagFromLead(lt.tag_id)
                        if (onTagsChange) onTagsChange(lead.id, lt.tag_id, 'remove')
                      }}
                      className="tag-x focus:outline-none flex items-center"
                      style={{ color: tagColor }}
                    >
                      <X size={9} weight="bold" />
                    </button>
                  </span>
                )
              })}
            </div>
          )}

          {/* Adicionar tags button — always below */}
          <div className="text-center mt-3 relative">
            <div className="inline-block relative" ref={tagMenuRef}>
              <button
                onClick={() => setShowTagMenu(!showTagMenu)}
                className="text-[11px] font-bold px-4 py-2.5 rounded-full border transition-colors hover:opacity-80"
                style={{
                  color: 'var(--chat-accent)',
                  borderColor: 'rgba(83,189,235,0.3)',
                  backgroundColor: 'rgba(83,189,235,0.1)',
                }}
              >
                + Adicionar tags
              </button>

              {showTagMenu && (() => {
                const assignedIds = new Set(displayTags.map((lt: any) => lt.tag_id))
                const availableTags = allTags.filter(t => !assignedIds.has(t.id))
                return (
                  <div className="glass-raised absolute top-full mt-1.5 left-1/2 -translate-x-1/2 w-48 rounded-xl py-2 z-10 text-left">
                    {availableTags.length === 0 ? (
                      <div className="px-4 py-2 text-xs text-[var(--chat-text-muted)]">
                        {allTags.length === 0 ? 'Nenhuma tag disponível' : 'Todas as tags já atribuídas'}
                      </div>
                    ) : (
                      availableTags.map(tag => (
                        <button
                          key={tag.id}
                          onClick={() => {
                            addTagToLead(tag.id)
                            if (onTagsChange) onTagsChange(lead.id, tag.id, 'add', tag)
                          }}
                          className="w-full text-left px-4 py-1.5 hover:bg-[var(--chat-bg-hover)] flex items-center"
                        >
                          <span
                            className="text-[9px] uppercase font-bold tracking-wide px-2 py-0.5 rounded-full"
                            style={tag.color?.startsWith('#') ? { backgroundColor: `${tag.color}1A`, color: tag.color } : {}}
                          >
                            {tag.name}
                          </span>
                        </button>
                      ))
                    )}
                  </div>
                )
              })()}
            </div>
          </div>
        </div>

        {/* Contadores + janela de 24h do WhatsApp */}
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            <div className="glass-soft rounded-xl px-3 py-2.5">
              <p className="text-[9px] font-bold uppercase tracking-wider text-[var(--chat-text-tertiary)] mb-0.5">No funil há</p>
              <p className="text-[13px] font-bold text-[var(--chat-text-secondary)]">{formatRelativeTime(lead.created_at)}</p>
            </div>
            <div className="glass-soft rounded-xl px-3 py-2.5">
              <p className="text-[9px] font-bold uppercase tracking-wider text-[var(--chat-text-tertiary)] mb-0.5">Última mensagem</p>
              <p className="text-[13px] font-bold text-[var(--chat-text-secondary)]">{lead.last_activity_at ? formatRelativeTime(lead.last_activity_at) : '—'}</p>
            </div>
          </div>

          {windowState && (
            <div className="glass-soft rounded-xl px-3 py-2.5">
              <div className="flex items-center justify-between mb-1.5">
                <p className="text-[9px] font-bold uppercase tracking-wider text-[var(--chat-text-tertiary)]">Janela de 24h</p>
                <p className="text-[11px] font-bold" style={{ color: WHATSAPP_WINDOW_ZONE_COLOR[windowState.zone] }}>
                  {windowState.remainingLabel}
                </p>
              </div>
              <div className="h-1.5 rounded-full bg-[var(--chat-bg-hover)] overflow-hidden">
                <div
                  className="h-full rounded-full transition-all"
                  style={{ width: `${windowState.percentRemaining}%`, backgroundColor: WHATSAPP_WINDOW_ZONE_COLOR[windowState.zone] }}
                />
              </div>
            </div>
          )}
        </div>

        {/* Pedido do cliente — status de pagamento/entrega visíveis e editáveis */}
        <LeadOrderCard lead={lead} refreshKey={orderRefreshKey} />

        {/* Marcar Venda */}
        <button
          onClick={() => setShowOrderModal(true)}
          className="w-full py-2.5 px-4 rounded-xl text-sm font-bold flex items-center justify-center gap-2 bg-green-500/10 border border-green-500/30 text-green-400 hover:bg-green-500/20 transition-colors"
        >
          <ShoppingCart size={16} weight="fill" />
          Marcar venda concluída
        </button>

        <div className="h-px hairline-x" />

        {/* Responsável */}
        <div className="relative" ref={ownerMenuRef}>
          <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-2">
            Responsável
          </p>
          <button
            type="button"
            onClick={() => setShowOwnerMenu((v) => !v)}
            disabled={savingOwner}
            className="w-full flex items-center gap-2 group/owner rounded-lg -mx-1 px-1 py-1 hover:bg-[var(--chat-bg-hover)] transition-colors disabled:opacity-60"
          >
            {ownerName ? (
              <>
                <div className="w-8 h-8 rounded-full bg-[var(--chat-bg-hover)] flex items-center justify-center overflow-hidden flex-shrink-0">
                  {lead.owner?.profiles?.avatar_url ? (
                    <img src={lead.owner.profiles.avatar_url} alt={ownerName} className="w-full h-full object-cover" />
                  ) : (
                    <span className="text-xs font-bold text-[var(--chat-accent)]">
                      {ownerInitials}
                    </span>
                  )}
                </div>
                <span className="text-sm font-medium text-[var(--chat-text-secondary)]">
                  {ownerName}
                </span>
              </>
            ) : (
              <>
                <div className="w-8 h-8 rounded-full bg-[var(--chat-bg-hover)] flex items-center justify-center flex-shrink-0">
                  <User size={16} className="text-[var(--chat-text-muted)]" />
                </div>
                <span className="text-sm text-[var(--chat-text-muted)]">Sem responsável</span>
              </>
            )}
            <CaretDown size={12} weight="bold" className="text-[var(--chat-text-tertiary)] opacity-0 group-hover/owner:opacity-100 transition-opacity ml-auto flex-shrink-0" />
          </button>

          {showOwnerMenu && (
            <div className="glass-raised absolute top-full mt-1.5 left-0 right-0 rounded-xl py-2 z-10 max-h-56 overflow-y-auto">
              <button
                onClick={() => handleAssignOwner(null)}
                className="w-full text-left px-4 py-1.5 hover:bg-[var(--chat-bg-hover)] flex items-center gap-2 text-sm text-[var(--chat-text-muted)]"
              >
                <User size={14} /> Sem responsável
                {!lead.owner_member_id && <Check size={14} weight="bold" className="ml-auto text-[var(--chat-accent)]" />}
              </button>
              {orgMembers.map((m) => (
                <button
                  key={m.id}
                  onClick={() => handleAssignOwner(m.id)}
                  className="w-full text-left px-4 py-1.5 hover:bg-[var(--chat-bg-hover)] flex items-center gap-2 text-sm text-[var(--chat-text-secondary)]"
                >
                  <div className="w-5 h-5 rounded-full bg-[var(--chat-bg-hover)] flex items-center justify-center overflow-hidden flex-shrink-0">
                    {m.profiles?.avatar_url ? (
                      <img src={m.profiles.avatar_url} alt={m.profiles?.full_name} className="w-full h-full object-cover" />
                    ) : (
                      <span className="text-[9px] font-bold text-[var(--chat-accent)]">
                        {(m.profiles?.full_name || '?').charAt(0).toUpperCase()}
                      </span>
                    )}
                  </div>
                  <span className="truncate">{m.profiles?.full_name || 'Sem nome'}</span>
                  {lead.owner_member_id === m.id && <Check size={14} weight="bold" className="ml-auto text-[var(--chat-accent)] flex-shrink-0" />}
                </button>
              ))}
            </div>
          )}
        </div>

        {/* Action Buttons */}
        {(() => {
          const pauseEnabled = chatButtonSettings.pausar_ia?.enabled && chatButtonSettings.pausar_ia?.position === 'sidebar'
          const suggestEnabled = chatButtonSettings.sugerir_passos?.enabled && chatButtonSettings.sugerir_passos?.position === 'sidebar'
          const flagEnabled = chatButtonSettings.sinalizar_ajuste?.enabled && chatButtonSettings.sinalizar_ajuste?.position === 'sidebar'
          const summarizeEnabled = chatButtonSettings.resumir_conversa?.enabled && chatButtonSettings.resumir_conversa?.position === 'sidebar'

          const anyEnabled = pauseEnabled || suggestEnabled || flagEnabled || summarizeEnabled

          if (!anyEnabled) return null

          return (
            <div className="grid grid-cols-2 gap-2">
              {pauseEnabled && (
                <button disabled={webhookStatus?.key === 'pausar_ia' && webhookStatus.status === 'sending'} onClick={() => handleSidebarWebhook('pausar_ia')} className={getSidebarButtonStyles('pausar_ia', 'bg-[var(--chat-bg-hover)]')}>
                  {renderSidebarButtonIcon('pausar_ia', Pause, 'text-purple-400')}
                  <span className={`text-[11px] font-bold flex items-center text-center leading-tight ${getSidebarButtonTextClass('pausar_ia')}`}>
                    Pausar IA
                  </span>
                </button>
              )}
              {suggestEnabled && (
                <button disabled={webhookStatus?.key === 'sugerir_passos' && webhookStatus.status === 'sending'} onClick={() => handleSidebarWebhook('sugerir_passos')} className={getSidebarButtonStyles('sugerir_passos', 'bg-[var(--chat-bg-hover)]')}>
                  {renderSidebarButtonIcon('sugerir_passos', Sparkle, 'text-[var(--chat-icon)]')}
                  <span className={`text-[11px] font-bold flex items-center text-center leading-tight ${getSidebarButtonTextClass('sugerir_passos')}`}>
                    Sugerir<br />Passos
                  </span>
                </button>
              )}
              {flagEnabled && (
                <button disabled={webhookStatus?.key === 'sinalizar_ajuste' && webhookStatus.status === 'sending'} onClick={() => handleSidebarWebhook('sinalizar_ajuste')} className={getSidebarButtonStyles('sinalizar_ajuste', 'bg-[var(--chat-bg-hover)]')}>
                  {renderSidebarButtonIcon('sinalizar_ajuste', Flag, 'text-orange-400')}
                  <span className={`text-[11px] font-bold flex items-center text-center leading-tight ${getSidebarButtonTextClass('sinalizar_ajuste')}`}>
                    Sinalizar<br />Ajuste
                  </span>
                </button>
              )}
              {summarizeEnabled && (
                <button disabled={webhookStatus?.key === 'resumir_conversa' && webhookStatus.status === 'sending'} onClick={() => handleSidebarWebhook('resumir_conversa')} className={getSidebarButtonStyles('resumir_conversa', 'bg-[var(--chat-bg-hover)]')}>
                  {renderSidebarButtonIcon('resumir_conversa', ChatText, 'text-[var(--chat-accent)]')}
                  <span className={`text-[11px] font-bold flex items-center text-center leading-tight ${getSidebarButtonTextClass('resumir_conversa')}`}>
                    Resumir<br />Conversa
                  </span>
                </button>
              )}
            </div>
          )
        })()}

        <div className="h-px hairline-x" />

        {/* Informações de Contato */}
        <div>
          <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-3">
            Informações de Contato
          </p>
          <div className="space-y-3">
            {lead.custom_attributes?.instagram_username && (
              <div className="flex items-center gap-2.5">
                <InstagramLogo size={16} className="text-[var(--chat-text-muted)] flex-shrink-0" />
                <div>
                  <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)]">
                    Instagram
                  </p>
                  <a
                    href={`https://instagram.com/${lead.custom_attributes.instagram_username}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm text-[var(--chat-accent)] hover:underline break-all"
                  >
                    @{lead.custom_attributes.instagram_username}
                  </a>
                </div>
              </div>
            )}
            <div className="flex items-center gap-2.5">
              <EnvelopeSimple size={16} className="text-[var(--chat-text-muted)] flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)]">
                  E-mail
                </p>
                <DebouncedInput
                  type="email"
                  className="w-full text-sm text-[var(--chat-text-secondary)] border-b border-transparent hover:border-[var(--chat-border)] focus:border-[var(--chat-accent)] focus:outline-none bg-transparent placeholder-[var(--chat-text-tertiary)] pb-0.5 transition-colors"
                  placeholder="Adicionar e-mail..."
                  value={lead.email || ''}
                  onChange={(val) => saveContactField('email', String(val))}
                  debounceTime={700}
                />
              </div>
            </div>
            <div className="flex items-center gap-2.5">
              <Phone size={16} className="text-[var(--chat-text-muted)] flex-shrink-0" />
              <div className="flex-1 min-w-0">
                <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)]">
                  Telefone
                </p>
                <DebouncedInput
                  type="tel"
                  className="w-full text-sm text-[var(--chat-text-secondary)] border-b border-transparent hover:border-[var(--chat-border)] focus:border-[var(--chat-accent)] focus:outline-none bg-transparent placeholder-[var(--chat-text-tertiary)] pb-0.5 transition-colors"
                  placeholder="Adicionar telefone..."
                  value={lead.phone || ''}
                  onChange={(val) => saveContactField('phone', String(val))}
                  debounceTime={700}
                />
              </div>
            </div>
          </div>
        </div>

        <div className="h-px hairline-x" />

        {/* Central de DADOS */}
        <div>
          <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-muted)] mb-3 flex items-center gap-1.5">
            <Database size={12} weight="bold" />
            DADOS
          </p>

          <div className="space-y-4">
            {/* Bloco: a agenda que a pessoa montou no site. Some sozinho quando
                o lead não veio da Agenda em Ascensão. */}
            <LeadAgendaCard leadId={lead.id} />

            {/* Bloco: Agenda de compromissos */}
            <div className="glass-soft rounded-xl p-3 space-y-2.5">
              <div className="flex items-center gap-1.5">
                <CalendarBlank size={13} className="text-[var(--chat-accent)]" weight="bold" />
                <p className="text-[11px] font-bold text-[var(--chat-text-secondary)]">Agenda de compromissos</p>
              </div>

              {appointments.length === 0 ? (
                <p className="text-[12px] text-[var(--chat-text-tertiary)]">Nenhum compromisso agendado.</p>
              ) : (
                <div className="space-y-1.5">
                  {appointments.map((apt) => (
                    <div key={apt.id} className="flex items-center justify-between gap-2 text-[12px]">
                      <div className="min-w-0">
                        <p className="text-[var(--chat-text-secondary)] truncate">{apt.title}</p>
                        <p className="text-[10px] text-[var(--chat-text-tertiary)]">
                          {new Date(apt.date).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' })}
                        </p>
                      </div>
                      <button
                        onClick={() => removeAppointment(apt.id)}
                        className="text-[var(--chat-text-tertiary)] hover:text-red-400 flex-shrink-0"
                        aria-label="Remover compromisso"
                      >
                        <X size={12} />
                      </button>
                    </div>
                  ))}
                </div>
              )}

              <div className="flex items-center gap-1.5 pt-1">
                <input
                  type="text"
                  placeholder="Título..."
                  value={newAppointmentTitle}
                  onChange={(e) => setNewAppointmentTitle(e.target.value)}
                  className="flex-1 min-w-0 text-[12px] border-b border-[var(--chat-border)] pb-1 focus:outline-none focus:border-[var(--chat-accent)] bg-transparent text-[var(--chat-text-secondary)] placeholder-[var(--chat-text-tertiary)]"
                />
                <input
                  type="datetime-local"
                  value={newAppointmentDate}
                  onChange={(e) => setNewAppointmentDate(e.target.value)}
                  className="text-[11px] border-b border-[var(--chat-border)] pb-1 focus:outline-none focus:border-[var(--chat-accent)] bg-transparent text-[var(--chat-text-secondary)]"
                />
                <button
                  onClick={addAppointment}
                  className="w-6 h-6 flex-shrink-0 flex items-center justify-center rounded-full bg-[var(--chat-accent)] text-white disabled:opacity-40"
                  disabled={!newAppointmentTitle.trim() || !newAppointmentDate}
                  aria-label="Adicionar compromisso"
                >
                  <Plus size={12} weight="bold" />
                </button>
              </div>
            </div>

            {/* Bloco: Definições profissionais */}
            <div className="glass-soft rounded-xl p-3 space-y-3">
              <div className="flex items-center gap-1.5">
                <Briefcase size={13} className="text-[var(--chat-accent)]" weight="bold" />
                <p className="text-[11px] font-bold text-[var(--chat-text-secondary)]">Definições profissionais</p>
              </div>
              <div className="space-y-3">
                {PROFESSIONAL_FIELDS.map(({ key, label, placeholder }) => (
                  <div key={key}>
                    <p className="text-[10px] font-bold uppercase tracking-wider text-[var(--chat-text-tertiary)] mb-1">
                      {label}
                    </p>
                    <DebouncedInput
                      type="text"
                      className="w-full text-[13px] font-medium border-b border-[var(--chat-border)] pb-1 focus:outline-none focus:border-[var(--chat-accent)] bg-transparent text-[var(--chat-text-secondary)] placeholder-[var(--chat-text-tertiary)]"
                      placeholder={placeholder}
                      value={professionalInfo[key] || ''}
                      onChange={(val) => setProfessionalInfo((prev) => ({ ...prev, [key]: String(val) }))}
                      debounceTime={400}
                    />
                  </div>
                ))}
              </div>
            </div>
          </div>
        </div>

        <div className="h-px hairline-x" />

        {/* Campos Customizados */}
        <div>
          {definitions.length === 0 ? (
            <p className="text-sm text-[var(--chat-text-muted)]">
              Nenhum campo configurado na conta.
            </p>
          ) : (
            <div className="space-y-6">
              {(() => {
                // Agrupar definições por category_id
                const grouped = definitions.reduce((acc, def) => {
                  const catId = def.category_id || 'uncategorized'
                  if (!acc[catId]) acc[catId] = []
                  acc[catId].push(def)
                  return acc
                }, {} as Record<string, typeof definitions>)

                // Ordenar as categorias baseadas no rank
                const sortedCatIds = Object.keys(grouped).sort((a, b) => {
                  if (a === 'uncategorized') return 1
                  if (b === 'uncategorized') return -1
                  const catA = categories.find(c => c.id === a)
                  const catB = categories.find(c => c.id === b)
                  return (catA?.rank || 0) - (catB?.rank || 0)
                })

                return sortedCatIds.map(catId => {
                  const isCollapsed = collapsedCategories.has(catId)
                  const toggleCollapse = () => {
                    setCollapsedCategories(prev => {
                      const newSet = new Set(prev)
                      if (newSet.has(catId)) newSet.delete(catId)
                      else newSet.add(catId)
                      return newSet
                    })
                  }

                  const categoryName = catId === 'uncategorized'
                    ? 'Outros Campos'
                    : categories.find(c => c.id === catId)?.name || 'Outros Campos'

                  const catDefs = grouped[catId]

                  return (
                    <div key={catId}>
                      <div
                        className="flex items-center gap-1.5 cursor-pointer group mb-3"
                        onClick={toggleCollapse}
                      >
                        <p className="text-[10px] font-bold text-[var(--chat-text-muted)] uppercase tracking-wider group-hover:text-[var(--chat-text-secondary)] transition-colors">
                          {categoryName}
                        </p>
                        <span className="text-[var(--chat-text-muted)] group-hover:text-[var(--chat-text-secondary)] transition-colors">
                          {isCollapsed ? <CaretRight size={12} weight="bold" /> : <CaretDown size={12} weight="bold" />}
                        </span>
                      </div>

                      {!isCollapsed && (
                        <div className="space-y-4">
                          {catDefs.map(def => {
                            const valObj = values.find(v => v.field_id === def.id)
                            let displayVal: string | number | undefined = ''
                            if (valObj) {
                              if (def.field_type === 'text') displayVal = valObj.value_text
                              else if (def.field_type === 'number') displayVal = valObj.value_number
                              else if (def.field_type === 'datetime') {
                                // datetime is now stored in value_text (value_date is date-only)
                                const raw = valObj.value_text || valObj.value_date || ''
                                if (raw && raw.includes('T')) {
                                  displayVal = raw.slice(0, 16) // "YYYY-MM-DDTHH:mm"
                                } else if (raw) {
                                  displayVal = raw + 'T00:00'
                                }
                              } else if (def.field_type === 'date') displayVal = valObj.value_date
                              else displayVal = valObj.value_text || '' // fallback
                            }

                            return (
                              <div key={def.id}>
                                <p className="text-[10px] font-semibold uppercase tracking-wider text-[var(--chat-text-muted)] mb-1">
                                  {def.name}
                                </p>
                                {def.field_type === 'select' ? (
                                  <CustomFieldSelect
                                    options={Array.isArray(def.schema?.options) ? def.schema.options : []}
                                    value={valObj?.value_json?.selected || ''}
                                    onChange={(val) => updateFieldValue(def.id, 'json', { selected: val })}
                                  />
                                ) : def.field_type === 'multi_select' ? (
                                  <CustomFieldMultiSelect
                                    options={Array.isArray(def.schema?.options) ? def.schema.options : []}
                                    value={Array.isArray(valObj?.value_json?.selected) ? valObj.value_json.selected : []}
                                    onChange={(val) => updateFieldValue(def.id, 'json', { selected: val })}
                                  />
                                ) : (
                                  <DebouncedInput
                                    type={def.field_type === 'number' ? 'number' : def.field_type === 'date' ? 'date' : def.field_type === 'datetime' ? 'datetime-local' : 'text'}
                                    className="w-full text-[13px] font-medium border-b border-[var(--chat-border)] pb-1 focus:outline-none focus:border-[var(--chat-accent)] bg-transparent text-[var(--chat-text-secondary)] placeholder-[var(--chat-text-tertiary)]"
                                    placeholder="Adicionar..."
                                    value={displayVal || ''}
                                    onChange={(val) => updateFieldValue(def.id, def.field_type, val)}
                                    debounceTime={700}
                                  />
                                )}
                              </div>
                            )
                          })}
                        </div>
                      )}
                    </div>
                  )
                })
              })()}
            </div>
          )}
        </div>

        <div className="h-px hairline-x" />

        {/* Funil de Vendas — FunnelMiniMap */}
        {stages.length > 0 && lead.stage_id && (
          <FunnelMiniMap
            stages={stages}
            currentStageId={lead.stage_id}
            history={stageHistory}
            loading={stageHistoryLoading}
            onStageClick={onStageChange}
            pipelines={pipelines}
            currentPipelineId={currentPipelineId}
            onPipelineChange={onPipelineChange}
          />
        )}

        <div className="h-px hairline-x" />

        {/* Histórico */}
        <LeadHistoryTimeline
          organizationId={lead.organization_id}
          leadId={lead.id}
        />

        {isAdmin && (
          <>
            <div className="h-px hairline-x" />
            <button
              onClick={handleDeleteHistory}
              disabled={deletingHistory}
              className="w-full py-2.5 px-4 rounded-xl text-sm font-bold flex items-center justify-center gap-2 bg-red-500/10 border border-red-500/30 text-red-400 hover:bg-red-500/20 transition-colors disabled:opacity-60 disabled:cursor-wait"
            >
              <Trash size={16} weight="fill" />
              {deletingHistory ? 'Apagando...' : 'Apagar histórico da conversa'}
            </button>
          </>
        )}
      </div>
    </div>

    {showOrderModal && (
      <OrderModal
        lead={lead}
        organizationId={lead.organization_id}
        onClose={() => setShowOrderModal(false)}
        onSuccess={() => setOrderRefreshKey(k => k + 1)}
      />
    )}
    </>
  )
}
