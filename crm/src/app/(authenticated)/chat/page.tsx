'use client'

import { useState, useCallback, useEffect, useRef } from 'react'
import { useSearchParams } from 'next/navigation'
import { useAuth, useStageHistory, useLeadPipelineStages, usePipeline, useIsMobile } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { LeadList, ChatWindow, LeadDetailsSidebar, LeadOrderStatusBadges } from '@/components/Chat'
import { LeadWithOwner } from '@/lib/types'
import { getInitials } from '@/lib/utils'
import { getLeadChannel } from '@/lib/leadChannel'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import { CaretLeft, Info } from '@phosphor-icons/react'

/** Última conversa aberta nesta tela, pra reabrir no próximo acesso. */
const CHAVE_ULTIMA_CONVERSA = 'crm:ultima-conversa:whatsapp'

export default function ChatPage() {
  const { organizationId, loading, permissions, isMaster, roleName, currentOrganization, user, profileName } = useAuth()

  const { leads: globalLeads, loading: leadsLoading, moveLeadToStage, setLeads } = useLeadsContext()

  const searchParams = useSearchParams()
  const leadIdFromUrl = searchParams.get('leadId')
  /*
   * Chave do pedido vindo do endereço: a conversa MAIS a marca de abertura que
   * os links internos carregam (ver src/lib/links.ts). Sem a marca, clicar duas
   * vezes no mesmo link seria o mesmo valor e a segunda vez não abriria nada.
   */
  const pedidoDaUrl = leadIdFromUrl ? `${leadIdFromUrl}|${searchParams.get('abrir') ?? ''}` : null

  // Aba WhatsApp API — Instagram tem aba própria em /chat/instagram
  const allLeads = globalLeads.filter(l => {
    if (getLeadChannel(l) === 'instagram') return false
    if (permissions?.leads?.view_own_only && currentOrganization?.id) {
      if (l.owner_member_id !== currentOrganization.id) return false;
    }
    return true;
  })

  const [selectedLead, setSelectedLead] = useState<LeadWithOwner | null>(null)
  const isMobile = useIsMobile()
  const [mobileView, setMobileView] = useState<'list' | 'conversation'>('list')
  const [showMobileDetails, setShowMobileDetails] = useState(false)

  /*
   * UMA fonte de verdade para a conversa aberta: o que a pessoa escolheu.
   *
   * O endereço (`?leadId=`) é só ENTRADA — serve pra chegar aqui pelo link do
   * aviso no grupo, pelo "Ver conversa" do Pipeline ou pela busca. Clicar numa
   * conversa não escreve mais no endereço, e é isso que mata de vez uma família
   * inteira de bugs: enquanto os dois lados escreviam, existia sempre um quadro
   * em que a seleção dizia uma coisa e o endereço ainda dizia outra, e alguém
   * tinha que ceder — foi assim que a tela ora abria a conversa errada, ora
   * congelava na anterior, ora não abria nada.
   *
   * Recarregar a página continua reabrindo a última conversa, agora pelo
   * navegador (localStorage) em vez do endereço. Guardar isso não pode
   * atrapalhar nada: se falhar, a tela só abre na conversa do topo.
   */
  /** Último pedido do endereço que este efeito viu — só pedido NOVO manda. */
  const ultimaUrlVista = useRef<string | null>(null)

  const handleSelectLead = useCallback((lead: LeadWithOwner) => {
    setSelectedLead(lead)
    setMobileView('conversation')
    // Pra reabrir aqui no próximo acesso. Best-effort: navegador anônimo ou
    // armazenamento bloqueado não pode impedir a conversa de abrir.
    try {
      localStorage.setItem(CHAVE_ULTIMA_CONVERSA, lead.id)
    } catch {}
  }, [])

  // Sync `?leadId=` from URL (pushed by GlobalSearch and notification links)
  // into selectedLead. Handles leads that are NOT in the in-memory 1000-row
  // cap by fetching them directly from Supabase with the same joins
  // LeadsContext uses, so downstream consumers (ChatWindow, sidebar) render
  // with full data.
  useEffect(() => {
    if (!leadIdFromUrl) return
    if (pedidoDaUrl === ultimaUrlVista.current) return
    ultimaUrlVista.current = pedidoDaUrl
    if (selectedLead?.id === leadIdFromUrl) return

    const fromMemory = globalLeads.find(l => l.id === leadIdFromUrl)
    if (fromMemory) {
      setSelectedLead(fromMemory)
      // Sem isso, um link tipo /chat?leadId=... resolvia o lead certo em segundo plano
      // mas no celular a tela continuava mostrando a lista de conversas — a pessoa
      // precisava tocar de novo pra entrar na conversa de verdade.
      setMobileView('conversation')
      return
    }

    let cancelled = false
    ;(async () => {
      const res = await fetch(`/api/leads/${leadIdFromUrl}`)
      if (res.ok) {
        const { data } = await res.json()
        if (!cancelled && data) {
          setSelectedLead(data as LeadWithOwner)
          setMobileView('conversation')
        }
      }
    })()
    return () => { cancelled = true }
  }, [leadIdFromUrl, pedidoDaUrl, globalLeads, selectedLead?.id])

  // Resolve the displayed lead: prefer the freshest version from context; fall back
  // to the clicked `selectedLead` when the lead isn't in memory (search hits can
  // point at leads outside the 1000-row Supabase cap loaded by LeadsContext).
  // Sem clique ainda, abre a conversa do topo — mas a que estava no topo na
  // hora de abrir a tela, e fica nela. Antes era "a do topo agora": com a lista
  // se reordenando sozinha, a conversa na tela trocava sem ninguém clicar.
  const conversaInicial = useRef<string | null>(null)
  if (!conversaInicial.current && allLeads.length > 0) {
    // A última que esta pessoa abriu, se ainda estiver na lista; senão a do topo.
    let guardada: string | null = null
    try {
      guardada = localStorage.getItem(CHAVE_ULTIMA_CONVERSA)
    } catch {}
    conversaInicial.current =
      guardada && allLeads.some((l) => l.id === guardada) ? guardada : allLeads[0].id
  }
  const displayedLeadId = selectedLead?.id || conversaInicial.current
  const displayedLead = allLeads.find(l => l.id === displayedLeadId) || selectedLead
  // Pass the lead's stage_id directly — the hook resolves the pipeline internally
  const { stages: leadStages, loading: stagesLoading } = useLeadPipelineStages(displayedLead?.stage_id)
  const { history: stageHistory, loading: historyLoading } = useStageHistory(displayedLead?.id || '')
  const { pipelines, stagesMap, loading: pipelinesLoading } = usePipeline(organizationId || '')

  // Derive the current pipeline id from the lead's stage
  const currentPipelineId = leadStages.length > 0 ? leadStages[0]?.pipeline_id : undefined

  const handleStageChange = useCallback(async (newStageId: string) => {
    if (!displayedLead) return
    const oldStageId = displayedLead.stage_id
    // Optimistic UI update for the selected lead
    if (selectedLead) {
      setSelectedLead({ ...selectedLead, stage_id: newStageId })
    }
    try {
      await moveLeadToStage(displayedLead.id, newStageId, oldStageId)
    } catch {
      // Revert on error
      if (selectedLead) {
        setSelectedLead({ ...selectedLead, stage_id: oldStageId })
      }
    }
  }, [displayedLead, selectedLead, moveLeadToStage])

  const handlePipelineChange = useCallback(async (newPipelineId: string) => {
    if (!displayedLead || !organizationId) return
    try {
      let firstStageId: string | undefined;

      // Optimistic Check: Do we already have the stages for this pipeline in memory?
      // usePipeline's stages map might have it if it was ever loaded or is the default.
      const cachedStages = stagesMap ? stagesMap[newPipelineId] : undefined;
      if (cachedStages && cachedStages.length > 0) {
        firstStageId = cachedStages[0].id;
      }

      // Fallback: Fetch from database if we don't have it in memory
      if (!firstStageId) {
        const stagesRes = await fetch(`/api/pipelines/${newPipelineId}/stages`)
        if (!stagesRes.ok) { console.error('Failed to fetch stages'); return }
        const { data: newStages } = await stagesRes.json()
        if (!newStages || newStages.length === 0) return
        firstStageId = newStages[0].id
      }

      if (!firstStageId) {
        console.error('Could not find first stage for pipeline', newPipelineId);
        return;
      }

      await handleStageChange(firstStageId)
    } catch (err) {
      console.error('Failed to change pipeline:', err)
    }
  }, [displayedLead, organizationId, handleStageChange, stagesMap])

  const handleTagsChange = useCallback((targetLeadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => {
    setLeads((prevLeads) => prevLeads.map((l) => {
      if (l.id !== targetLeadId) return l

      let newTags = [...(l.lead_tags || [])]
      if (action === 'add') {
        if (!newTags.find((t) => t.tag_id === tagId)) {
          newTags.push({ tag_id: tagId, tag: tagObj })
        }
      } else {
        newTags = newTags.filter((t) => t.tag_id !== tagId)
      }
      return { ...l, lead_tags: newTags }
    }))

    // Note: selectedLead doesn't strictly need manual matching if it falls back to displayedLead reading from allLeads, but we'll update it just in case
    if (selectedLead?.id === targetLeadId) {
      setSelectedLead((prev) => {
        if (!prev) return prev
        let newTags = [...(prev.lead_tags || [])]
        if (action === 'add') {
          if (!newTags.find((t) => t.tag_id === tagId)) {
            newTags.push({ tag_id: tagId, tag: tagObj })
          }
        } else {
          newTags = newTags.filter((t) => t.tag_id !== tagId)
        }
        return { ...prev, lead_tags: newTags }
      })
    }
  }, [setLeads, selectedLead])

  const handleChatMessageSent = useCallback((content: string) => {
    const memberId = currentOrganization?.id || ''
    const fullName = profileName || user?.name || user?.email || ''
    const leadId = displayedLead?.id
    // Só assume automaticamente quem respondeu se o lead ainda não tem responsável —
    // nunca sobrescreve uma atribuição manual feita por outra pessoa.
    const alreadyHasOwner = !!displayedLead?.owner_member_id

    setLeads(prev => prev.map(l => {
      if (l.id === leadId) {
        const shouldAssign = !l.owner_member_id && memberId
        return {
          ...l,
          last_message_content: content,
          last_message_sender_type: 'human' as const,
          last_activity_at: new Date().toISOString(),
          // A lista recalcula no servidor a cada poucos segundos; isto só evita
          // a etiqueta de quem respondeu demorar a aparecer.
          ...(!l.is_group && memberId && {
            autores_manuais: [memberId, ...(l.autores_manuais ?? []).filter(id => id !== memberId)],
            em_atendimento_humano: true,
          }),
          owner_member_id: shouldAssign ? memberId : l.owner_member_id,
          owner: shouldAssign ? { id: memberId, profiles: { full_name: fullName, avatar_url: user?.image || undefined } } : l.owner,
        }
      }
      return l
    }))
    // Also update selectedLead so the sidebar refreshes immediately
    if (selectedLead && selectedLead.id === leadId) {
      setSelectedLead(prev => {
        if (!prev) return prev
        const shouldAssign = !prev.owner_member_id && memberId
        return {
          ...prev,
          last_message_content: content,
          last_message_sender_type: 'human' as const,
          last_activity_at: new Date().toISOString(),
          owner_member_id: shouldAssign ? memberId : prev.owner_member_id,
          owner: shouldAssign ? { id: memberId, profiles: { full_name: fullName, avatar_url: user?.image || undefined } } : prev.owner,
        }
      })
    }

    if (leadId && memberId && !alreadyHasOwner) {
      fetch(`/api/leads/${leadId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ owner_member_id: memberId }),
      }).catch((err) => console.error('Failed to auto-assign owner:', err))
    }
  }, [displayedLead, selectedLead, setLeads, currentOrganization, user, profileName])

  const handleUpdateLead = useCallback((leadId: string, updates: Partial<LeadWithOwner>) => {
    setLeads(prev => prev.map(l => l.id === leadId ? { ...l, ...updates } : l))
  }, [setLeads])

  const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']
  if (!loading && !isAdmin && permissions && !permissions.settings?.view_chat) {
    return <NotAuthorized />
  }

  if (loading || leadsLoading || (!isAdmin && !permissions)) {
    return (
      <div className="flex items-center justify-center h-full">
        <LoadingSpinner text="Carregando..." size="lg" />
      </div>
    )
  }

  if (!organizationId) {
    return (
      <div className="flex items-center justify-center h-full">
        <p className="text-muted">Nenhuma organização encontrada. Execute o seed.sql no Supabase.</p>
      </div>
    )
  }

  // Mobile: uma tela por vez (lista OU conversa), detalhes do lead viram overlay
  // em tela cheia em vez de coluna fixa. Desktop abaixo continua como sempre foi.
  if (isMobile) {
    return (
      <div className="chat-theme h-full flex flex-col">
        {mobileView === 'list' && (
          <LeadList
            leads={allLeads}
            selectedLeadId={displayedLead?.id}
            onSelectLead={handleSelectLead}
            onUpdateLead={handleUpdateLead}
            loading={false}
            organizationId={organizationId}
          />
        )}

        {mobileView === 'conversation' && (
          displayedLead ? (
            <div className="flex flex-col h-full min-h-0">
              <div className="glass-soft rounded-none border-x-0 border-t-0 flex items-center gap-3 h-14 px-2 flex-shrink-0">
                <button onClick={() => setMobileView('list')} className="btn-icon w-9 h-9 text-[var(--chat-text-primary)]" aria-label="Voltar">
                  <CaretLeft size={20} />
                </button>
                <div className="w-8 h-8 rounded-full bg-[var(--chat-bg-hover)] flex items-center justify-center overflow-hidden flex-shrink-0">
                  {displayedLead.avatar_url ? (
                    <img src={displayedLead.avatar_url} alt={displayedLead.title} className="w-full h-full object-cover" />
                  ) : (
                    <span className="text-xs font-bold text-[var(--chat-accent)]">{getInitials(displayedLead.title)}</span>
                  )}
                </div>
                <span className="flex-1 min-w-0 truncate text-sm font-medium text-[var(--chat-text-primary)]">{displayedLead.title}</span>
                <LeadOrderStatusBadges key={displayedLead.id} leadId={displayedLead.id} />
                <button onClick={() => setShowMobileDetails(true)} className="btn-icon w-9 h-9" aria-label="Detalhes do contato">
                  <Info size={20} />
                </button>
              </div>
              <div className="flex-1 min-h-0">
                <ChatWindow
                  // Uma conversa = uma área de tela: trocar de lead remonta tudo, e
                  // nada da conversa anterior (mensagens, rascunho, fixadas) sobra.
                  key={displayedLead.id}
                  lead={displayedLead}
                  organizationId={organizationId}
                  onMessageSent={handleChatMessageSent}
                />
              </div>
            </div>
          ) : (
            <div className="flex items-center justify-center h-full bg-[var(--chat-bg-conversation)] text-[var(--chat-text-muted)]">
              Integre alguma fonte de conversas
            </div>
          )
        )}

        {showMobileDetails && displayedLead && (
          <div className="fixed inset-0 z-50 flex bg-[var(--chat-bg-base)]">
            {/* flex: o painel estica até a altura da tela e rola por dentro. Sem isso
                ele crescia do tamanho do conteúdo e o fim ficava cortado, sem rolar. */}
            <LeadDetailsSidebar
              key={displayedLead.id}
              lead={displayedLead}
              stages={leadStages}
              stageHistory={stageHistory}
              stageHistoryLoading={historyLoading || stagesLoading}
              onStageChange={handleStageChange}
              onTagsChange={handleTagsChange}
              onUpdateLead={handleUpdateLead}
              pipelines={pipelines}
              currentPipelineId={currentPipelineId}
              onPipelineChange={handlePipelineChange}
              onClose={() => setShowMobileDetails(false)}
            />
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="chat-theme flex h-full gap-0">
      {/* Left — Lead List */}
      <div className="w-[340px] border-r border-[var(--chat-border)] flex-shrink-0">
        <LeadList
          leads={allLeads}
          selectedLeadId={displayedLead?.id}
          onSelectLead={handleSelectLead}
          onUpdateLead={handleUpdateLead}
          loading={false}
          organizationId={organizationId}
        />
      </div>

      {/* Center — Chat */}
      <div className="flex-1 min-w-0">
        {displayedLead ? (
          <ChatWindow
            // Uma conversa = uma área de tela: trocar de lead remonta tudo, e
            // nada da conversa anterior (mensagens, rascunho, fixadas) sobra.
            key={displayedLead.id}
            lead={displayedLead}
            organizationId={organizationId}
            onMessageSent={handleChatMessageSent}
          />
        ) : (
          <div className="flex items-center justify-center h-full bg-[var(--chat-bg-conversation)] text-[var(--chat-text-muted)]">
            Integre alguma fonte de conversas
          </div>
        )}
      </div>

      {/* Right — Lead Details Sidebar */}
      {displayedLead && (
        <LeadDetailsSidebar
          key={displayedLead.id}
          lead={displayedLead}
          stages={leadStages}
          stageHistory={stageHistory}
          stageHistoryLoading={historyLoading || stagesLoading}
          onStageChange={handleStageChange}
          onTagsChange={handleTagsChange}
          onUpdateLead={handleUpdateLead}
          pipelines={pipelines}
          currentPipelineId={currentPipelineId}
          onPipelineChange={handlePipelineChange}
        />
      )}
    </div>
  )
}

