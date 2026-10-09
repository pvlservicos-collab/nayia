'use client'

import { useState, useCallback, useEffect, useRef } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { useAuth, useStageHistory, useLeadPipelineStages, usePipeline, useIsMobile } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { LeadList, ChatWindow, LeadDetailsSidebar } from '@/components/Chat'
import { LeadWithOwner } from '@/lib/types'
import { CAMINHO_DA_LINHA, getLinhaWhatsapp, type LinhaWhatsapp } from '@/lib/leadChannel'
import { AVISO_DA_CAPTACAO, soRespondeNaCaptacao } from '@/lib/captacaoSoResponde'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import AbasParceria, { type AbaDaParceria } from './AbasParceria'
import VisitasAgendadas from './VisitasAgendadas'
import FechamentoChecklists from './FechamentoChecklists'
import BarraDeMetricas from './BarraDeMetricas'
import BarraDaCaptacao from './BarraDaCaptacao'
import BarraDoDisparoOficial from './BarraDoDisparoOficial'
import PainelContatoCaptacao from './PainelContatoCaptacao'
import PainelContatoParceria from './PainelContatoParceria'
import { usePuxador } from '@/hooks/usePuxador'
import { useCaptacaoDonos } from '@/hooks/useCaptacaoDonos'

/** Última conversa aberta nesta tela, pra reabrir no próximo acesso. */
const CHAVE_ULTIMA_CONVERSA = 'crm:ultima-conversa:whatsapp'
const CHAVE_PAINEL = 'crm:painel-do-contato-aberto'

/* A ETIQUETA DA LINHA (Tel, 26/09): a tela DIZ em qual linha você está, com
   o número, para ninguém precisar deduzir. Desde 29/09 ela fica no topo da
   lista, como o "WhatsApp" do WhatsApp Web. */
const IDENTIDADE_DA_LINHA: Record<LinhaWhatsapp, { titulo: string; numero: string }> = {
  oficial: { titulo: 'API Oficial (Meta)', numero: '+55 92 8456-0874' },
  parceria: { titulo: 'Parceria', numero: 'Z-API · +55 92 9445-3618' },
  captacao: { titulo: 'Captação', numero: 'Z-API · +55 92 8595-6408' },
}

/** Tela larga o bastante para o card do contato ficar ao lado (e não por cima). */
function useTelaLarga(): boolean {
  const [larga, setLarga] = useState(true)
  useEffect(() => {
    const mq = window.matchMedia('(min-width: 1280px)')
    const atualizar = () => setLarga(mq.matches)
    atualizar()
    mq.addEventListener('change', atualizar)
    return () => mq.removeEventListener('change', atualizar)
  }, [])
  return larga
}

export default function ChatWhatsApp({ linha }: { linha: LinhaWhatsapp }) {
  /* A chave é POR LINHA: sem isso, abrir a aba da parceria reabriria a
     última conversa da captação. */
  const chaveUltimaConversa = `${CHAVE_ULTIMA_CONVERSA}:${linha}`
  const ehParceria = linha === 'parceria'

  const { organizationId, loading, permissions, isMaster, roleName, currentOrganization, user, profileName } = useAuth()
  const { leads: globalLeads, loading: leadsLoading, moveLeadToStage, setLeads } = useLeadsContext()

  const searchParams = useSearchParams()
  const router = useRouter()
  const leadIdFromUrl = searchParams.get('leadId')
  /* Chave do pedido vindo do endereço: a conversa MAIS a marca de abertura que
     os links internos carregam (ver src/lib/links.ts). */
  const pedidoDaUrl = leadIdFromUrl ? `${leadIdFromUrl}|${searchParams.get('abrir') ?? ''}` : null

  // Cada aba mostra SÓ a sua linha de WhatsApp (Tel, 25/09).
  const allLeads = globalLeads.filter((l) => {
    if (getLinhaWhatsapp(l) !== linha) return false
    if (permissions?.leads?.view_own_only && currentOrganization?.id) {
      if (l.owner_member_id !== currentOrganization.id) return false
    }
    return true
  })

  const [selectedLead, setSelectedLead] = useState<LeadWithOwner | null>(null)
  const isMobile = useIsMobile()
  const telaLarga = useTelaLarga()
  const [mobileView, setMobileView] = useState<'list' | 'conversation'>('list')

  /* AS ABAS DA PARCERIA (Pedro, 29/09): Conversas e Visitas agendadas, na
     faixa de cima -- "no lugar de Z-API (parceria) +55 92 9445-3618". */
  const [aba, setAba] = useState<AbaDaParceria>('conversas')
  const [visitaDestaque, setVisitaDestaque] = useState<number | null>(null)
  const { marcas, nay } = useParceriaMarcas(ehParceria)

  /* O card do contato: ao lado em tela larga (lembrando se a pessoa fechou),
     por cima da conversa em tela menor -- aí começa fechado. */
  const [painelAberto, setPainelAberto] = useState(true)
  /* na Oficial, quem é dono em captação ganha o card da captação (Pedro, 09/10: "quero que apareça o imóvel do cara
     igual tem nos outros cards de proprietários") */
  const donosDaCaptacao = useCaptacaoDonos(linha === 'oficial')
  /* a lista da esquerda alarga puxando a borda (Pedro, 09/10); 30% da tela era o padrão do WhatsApp Web */
  const lista_ = usePuxador('crm:largura-lista', { min: 260, max: 640, padrao: 380, lado: 'direita' })
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

  /*
   * UMA fonte de verdade para a conversa aberta: o que a pessoa escolheu.
   * O endereço (`?leadId=`) é só ENTRADA (ver crm/CLAUDE.md).
   */
  const ultimaUrlVista = useRef<string | null>(null)

  const handleSelectLead = useCallback((lead: LeadWithOwner) => {
    setSelectedLead(lead)
    setMobileView('conversation')
    try { localStorage.setItem(chaveUltimaConversa, lead.id) } catch {}
  }, [chaveUltimaConversa])

  useEffect(() => {
    if (!leadIdFromUrl) return
    if (pedidoDaUrl === ultimaUrlVista.current) return
    ultimaUrlVista.current = pedidoDaUrl
    if (selectedLead?.id === leadIdFromUrl) return

    /* O LINK ABRE NA ABA DA LINHA DA CONVERSA (28/09). */
    const abrir = (alvo: LeadWithOwner) => {
      const linhaDoAlvo = getLinhaWhatsapp(alvo)
      if (linhaDoAlvo && linhaDoAlvo !== linha) {
        router.replace(`${CAMINHO_DA_LINHA[linhaDoAlvo]}?${searchParams.toString()}`)
        return
      }
      setSelectedLead(alvo)
      setAba('conversas')
      setMobileView('conversation')
    }

    const fromMemory = globalLeads.find((l) => l.id === leadIdFromUrl)
    if (fromMemory) { abrir(fromMemory); return }

    let cancelled = false
    ;(async () => {
      const res = await fetch(`/api/leads/${leadIdFromUrl}`)
      if (res.ok) {
        const { data } = await res.json()
        if (!cancelled && data) abrir(data as LeadWithOwner)
      }
    })()
    return () => { cancelled = true }
  }, [leadIdFromUrl, pedidoDaUrl, globalLeads, selectedLead?.id, linha, router, searchParams])

  /* Sem clique ainda, abre a conversa que estava no topo na hora de abrir a
     tela (ou a última aberta aqui) -- e fica nela. */
  const conversaInicial = useRef<string | null>(null)
  const linhaDoRef = useRef<LinhaWhatsapp | null>(null)
  if (linhaDoRef.current !== linha) {
    linhaDoRef.current = linha
    conversaInicial.current = null
  }
  if (!conversaInicial.current && allLeads.length > 0) {
    let guardada: string | null = null
    try { guardada = localStorage.getItem(chaveUltimaConversa) } catch {}
    conversaInicial.current = guardada && allLeads.some((l) => l.id === guardada) ? guardada : allLeads[0].id
  }
  const displayedLeadId = selectedLead?.id || conversaInicial.current
  /* O lead solto (fora do limite da lista) só vale se for desta linha: as
     três abas são o mesmo componente, e o React o reaproveita entre elas. */
  const soltoDestaLinha = selectedLead && getLinhaWhatsapp(selectedLead) === linha ? selectedLead : null
  const displayedLead = allLeads.find((l) => l.id === displayedLeadId) || soltoDestaLinha

  /* O funil (etapas, histórico de etapas, pipelines) só existe para o card
     antigo. O da Parceria não usa: sem estes três pedidos a conversa abre
     mais rápido (Pedro, 29/09: "que o clicar na conversa fique mais rápido"). */
  const usaFunil = !ehParceria
  const { stages: leadStages, loading: stagesLoading } = useLeadPipelineStages(usaFunil ? displayedLead?.stage_id : undefined)
  const { history: stageHistory, loading: historyLoading } = useStageHistory(usaFunil ? displayedLead?.id || '' : '')
  const { pipelines, stagesMap } = usePipeline(usaFunil ? organizationId || '' : '')
  const currentPipelineId = leadStages.length > 0 ? leadStages[0]?.pipeline_id : undefined

  const handleStageChange = useCallback(async (newStageId: string) => {
    if (!displayedLead) return
    const oldStageId = displayedLead.stage_id
    if (selectedLead) setSelectedLead({ ...selectedLead, stage_id: newStageId })
    try {
      await moveLeadToStage(displayedLead.id, newStageId, oldStageId)
    } catch {
      if (selectedLead) setSelectedLead({ ...selectedLead, stage_id: oldStageId })
    }
  }, [displayedLead, selectedLead, moveLeadToStage])

  const handlePipelineChange = useCallback(async (newPipelineId: string) => {
    if (!displayedLead || !organizationId) return
    try {
      let firstStageId: string | undefined
      const cachedStages = stagesMap ? stagesMap[newPipelineId] : undefined
      if (cachedStages && cachedStages.length > 0) firstStageId = cachedStages[0].id
      if (!firstStageId) {
        const stagesRes = await fetch(`/api/pipelines/${newPipelineId}/stages`)
        if (!stagesRes.ok) { console.error('Failed to fetch stages'); return }
        const { data: newStages } = await stagesRes.json()
        if (!newStages || newStages.length === 0) return
        firstStageId = newStages[0].id
      }
      if (!firstStageId) return
      await handleStageChange(firstStageId)
    } catch (err) {
      console.error('Failed to change pipeline:', err)
    }
  }, [displayedLead, organizationId, handleStageChange, stagesMap])

  const handleTagsChange = useCallback((targetLeadId: string, tagId: string, action: 'add' | 'remove', tagObj?: any) => {
    const mudar = (l: LeadWithOwner): LeadWithOwner => {
      let newTags = [...(l.lead_tags || [])]
      if (action === 'add') {
        if (!newTags.find((t) => t.tag_id === tagId)) newTags.push({ tag_id: tagId, tag: tagObj })
      } else {
        newTags = newTags.filter((t) => t.tag_id !== tagId)
      }
      return { ...l, lead_tags: newTags }
    }
    setLeads((prev) => prev.map((l) => (l.id === targetLeadId ? mudar(l) : l)))
    if (selectedLead?.id === targetLeadId) setSelectedLead((prev) => (prev ? mudar(prev) : prev))
  }, [setLeads, selectedLead])

  const handleChatMessageSent = useCallback((content: string) => {
    const memberId = currentOrganization?.id || ''
    const fullName = profileName || user?.name || user?.email || ''
    const leadId = displayedLead?.id
    // Só assume quem respondeu se o lead ainda não tem responsável.
    const alreadyHasOwner = !!displayedLead?.owner_member_id

    const atualizar = (l: LeadWithOwner): LeadWithOwner => {
      const shouldAssign = !l.owner_member_id && memberId
      return {
        ...l,
        last_message_content: content,
        last_message_sender_type: 'human' as const,
        last_activity_at: new Date().toISOString(),
        ...(!l.is_group && memberId && {
          autores_manuais: [memberId, ...(l.autores_manuais ?? []).filter((id) => id !== memberId)],
          em_atendimento_humano: true,
        }),
        owner_member_id: shouldAssign ? memberId : l.owner_member_id,
        owner: shouldAssign ? { id: memberId, profiles: { full_name: fullName, avatar_url: user?.image || undefined } } : l.owner,
      }
    }
    setLeads((prev) => prev.map((l) => (l.id === leadId ? atualizar(l) : l)))
    if (selectedLead && selectedLead.id === leadId) setSelectedLead((prev) => (prev ? atualizar(prev) : prev))

    if (leadId && memberId && !alreadyHasOwner) {
      fetch(`/api/leads/${leadId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ owner_member_id: memberId }),
      }).catch((err) => console.error('Failed to auto-assign owner:', err))
    }
  }, [displayedLead, selectedLead, setLeads, currentOrganization, user, profileName])

  const handleUpdateLead = useCallback((leadId: string, updates: Partial<LeadWithOwner>) => {
    setLeads((prev) => prev.map((l) => (l.id === leadId ? { ...l, ...updates } : l)))
  }, [setLeads])

  /* Da aba Visitas para a conversa do corretor, e do card para a visita. */
  const abrirConversaPorId = useCallback((leadId: string) => {
    const alvo = allLeads.find((l) => l.id === leadId)
    setAba('conversas')
    if (alvo) handleSelectLead(alvo)
  }, [allLeads, handleSelectLead])
  const verVisita = useCallback((visitaId: number) => {
    setVisitaDestaque(visitaId)
    setAba('visitas')
  }, [])

  const isAdmin = isMaster || roleName?.toLowerCase() === 'administrador' || roleName?.toLowerCase() === 'owner' || permissions?.['*']
  if (!loading && !isAdmin && permissions && !permissions.settings?.view_chat) return <NotAuthorized />

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
        <p className="text-muted">Nenhuma organização encontrada.</p>
      </div>
    )
  }

  const identidade = IDENTIDADE_DA_LINHA[linha]
  const naoLidas = allLeads.filter((l) => l.is_unread && !l.is_archived).length
  const visitasAbertas = new Set(Object.values(marcas).filter((m) => m.visitaAberta && m.visitaId).map((m) => m.visitaId)).size

  const lista = (
    <LeadList
      leads={allLeads}
      linha={linha}
      titulo={identidade.titulo}
      numero={identidade.numero}
      selectedLeadId={displayedLead?.id}
      onSelectLead={handleSelectLead}
      aoAbrirPorId={abrirConversaPorId}
      onUpdateLead={handleUpdateLead}
      loading={false}
      organizationId={organizationId}
    />
  )

  const conversa = (voltar?: () => void) => displayedLead ? (
    <ChatWindow
      // Uma conversa = uma área de tela: trocar de lead remonta tudo.
      key={displayedLead.id}
      lead={displayedLead}
      organizationId={organizationId}
      onMessageSent={handleChatMessageSent}
      linha={linha}
      marca={ehParceria ? marcas[displayedLead.id] : undefined}
      dono={linha === 'oficial' ? donosDaCaptacao[displayedLead.id] : undefined}
      painelAberto={painelAberto}
      aoAlternarPainel={alternarPainel}
      aoVoltar={voltar}
    />
  ) : (
    <div className="wa-papel flex flex-col items-center justify-center h-full gap-2 px-8 text-center">
      <span className="relative text-[15px] font-semibold" style={{ color: 'var(--wa-text)' }}>{identidade.titulo} · {identidade.numero}</span>
      <span className="relative text-[14px]" style={{ color: 'var(--wa-text-2)' }}>
        {linha === 'oficial'
          ? 'Nenhuma conversa aqui ainda. Esta aba mostra só o que passa pelo número oficial da Meta.'
          : 'Nenhuma conversa nesta linha ainda.'}
      </span>
    </div>
  )

  const painel = (modo: 'lateral' | 'gaveta') => {
    if (!displayedLead || !painelAberto) return null
    if (ehParceria) {
      return (
        <PainelContatoParceria
          key={displayedLead.id}
          lead={displayedLead}
          modo={modo}
          aoFechar={alternarPainel}
          aoVerVisita={verVisita}
          onTagsChange={handleTagsChange}
          onUpdateLead={handleUpdateLead}
        />
      )
    }
    /* A CAPTAÇÃO TEM O CARD DELA (Pedro, 01/10/2026): "quero reformular
       totalmente o card de proprietário lá do WhatsApp de captação, quero
       informações úteis lá no card". O card genérico do CRM (pedido, venda,
       agenda) não é desta linha: aqui só se fala com quem tem imóvel. */
    if (linha === 'captacao' || (linha === 'oficial' && donosDaCaptacao[displayedLead.id])) {
      return (
        <PainelContatoCaptacao
          key={displayedLead.id}
          lead={displayedLead}
          modo={modo}
          aoFechar={alternarPainel}
          oficial={linha === 'oficial'}
        />
      )
    }
    const antigo = (
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
        onClose={modo === 'gaveta' ? alternarPainel : undefined}
      />
    )
    if (modo === 'lateral') return antigo
    return (
      <div className="fixed inset-0 z-50 flex justify-end" onClick={alternarPainel}>
        <div className="absolute inset-0 bg-black/40" />
        <div className="relative h-full w-[min(380px,92vw)] flex shadow-2xl" onClick={(e) => e.stopPropagation()}>{antigo}</div>
      </div>
    )
  }

  const abas = ehParceria ? (
    <AbasParceria aba={aba} aoMudar={(k) => { setAba(k); if (k === 'conversas') setMobileView('list') }}
                  naoLidas={naoLidas} visitasAbertas={visitasAbertas}>
      <BarraDeMetricas leads={allLeads} marcas={marcas} nay={nay} aoAbrirConversa={abrirConversaPorId} />
    </AbasParceria>
  ) : linha === 'captacao' ? (
    // a barra da captação (Pedro, 29/09): hoje, as etapas e o relatório ao Tel
    <>
      {/* quem só responde na captação vê o aviso sempre que abre esta tela (Pedro, 02/10) */}
      {soRespondeNaCaptacao(profileName || user?.name) && (
        <div role="alert" className="px-4 py-2.5 text-[13.5px] font-medium leading-snug"
             style={{ background: '#FEF3C7', color: '#78350F', borderBottom: '1px solid #F59E0B' }}>
          ⚠️ {AVISO_DA_CAPTACAO}
        </div>
      )}
      <BarraDaCaptacao leads={allLeads} />
    </>
  ) : linha === 'oficial' ? (
    // a barrinha do disparo pela API oficial (Pedro, 09/10): qual lista está saindo e quanto falta
    <BarraDoDisparoOficial />
  ) : null

  /* ── Celular: uma tela por vez; na Parceria as abas ficam em cima ── */
  if (isMobile) {
    const naConversa = mobileView === 'conversation' && aba === 'conversas'
    return (
      <div className="chat-theme h-full flex flex-col">
        {!naConversa && abas}
        {ehParceria && aba === 'visitas' ? (
          <div className="flex-1 min-h-0 flex"><VisitasAgendadas aoAbrirConversa={abrirConversaPorId} destaque={visitaDestaque} /></div>
        ) : ehParceria && aba === 'fechamento' ? (
          <div className="flex-1 min-h-0 overflow-y-auto"><FechamentoChecklists /></div>
        ) : mobileView === 'list' ? (
          <div className="flex-1 min-h-0">{lista}</div>
        ) : (
          <div className="flex-1 min-h-0">{conversa(() => setMobileView('list'))}</div>
        )}
        {painelAberto && painel('gaveta')}
      </div>
    )
  }

  /* ── Computador: [abas da Parceria em cima] / lista | conversa | card do contato ── */
  return (
    <div className="chat-theme flex flex-col h-full min-h-0">
      {abas}
      <div className="flex flex-1 min-h-0">
        {ehParceria && aba === 'visitas' ? (
          <VisitasAgendadas aoAbrirConversa={abrirConversaPorId} destaque={visitaDestaque} />
        ) : ehParceria && aba === 'fechamento' ? (
          <div className="flex-1 min-h-0 overflow-y-auto"><FechamentoChecklists /></div>
        ) : (
          <>
            {/* A lista: largura de quem usa, puxando a borda direita dela */}
            <div className="relative flex-shrink-0 h-full min-h-0" style={{ width: lista_.largura, borderRight: '1px solid var(--wa-divider)' }}>
              {lista}
              <div {...lista_.puxador} />
            </div>
            <div className="flex-1 min-w-0 h-full min-h-0">{conversa()}</div>
            {painel(telaLarga ? 'lateral' : 'gaveta')}
          </>
        )}
      </div>
    </div>
  )
}
