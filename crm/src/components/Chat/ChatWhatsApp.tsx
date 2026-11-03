'use client'

import { useState, useCallback, useEffect, useRef } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { useAuth, useStageHistory, useLeadPipelineStages, usePipeline, useIsMobile, useOrganizationMembers } from '@/hooks'
import { montarAtendentes } from '@/lib/atendentes'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { LeadList, ChatWindow, LeadDetailsSidebar } from '@/components/Chat'
import { LeadWithOwner } from '@/lib/types'
import { CAMINHO_DA_LINHA, getLinhaWhatsapp, type LinhaWhatsapp } from '@/lib/leadChannel'
import { AVISO_DA_CAPTACAO, soRespondeNaCaptacao } from '@/lib/captacaoSoResponde'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import AbasParceria, { type AbaDaParceria } from './AbasParceria'
import ArquiteturaDosAgentes from './ArquiteturaDosAgentes'
import VisitasAgendadas from './VisitasAgendadas'
import PipelineBoard from '@/components/Pipeline/PipelineBoard'
import FechamentoChecklists from './FechamentoChecklists'
import ContadorDeVisitas from './ContadorDeVisitas'
import BarraDoDisparoOficial from './BarraDoDisparoOficial'
import BarraDoCustoOficial from './BarraDoCustoOficial'
import PainelContatoCaptacao from './PainelContatoCaptacao'
import CadastroImovelOlx from './CadastroImovelOlx'
import EnviarImovelPelaCaptacao from './EnviarImovelPelaCaptacao'
import PainelContatoParceria from './PainelContatoParceria'
import OrganizarConversa, { organizar, EnviarParaAdministracaoParceria } from './OrganizarConversa'
import { apareceNaAba, faixaDeOutraLinha, mostrarTambemEm, mudouPara, LINHAS_MISTAS, NOME_DA_LINHA } from '@/lib/organizacaoDoLead'
import type { Organizado } from './OrganizarConversa'
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
  // 19/10 (Pedro: "coloque o nome do número de captação como Leads (imobeasy)")
  captacao: { titulo: 'Leads (imobeasy)', numero: 'Z-API · +55 92 8595-6408' },
}

/** Tela larga o bastante para o card do contato ficar ao lado (e não por cima). */
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

export default function ChatWhatsApp({ linha }: { linha: LinhaWhatsapp }) {
  /* A chave é POR LINHA: sem isso, abrir a aba da parceria reabriria a
     última conversa da captação. */
  const chaveUltimaConversa = `${CHAVE_ULTIMA_CONVERSA}:${linha}`
  const ehParceria = linha === 'parceria'

  const { organizationId, loading, permissions, isMaster, roleName, currentOrganization, user, profileName } = useAuth()
  const { leads: globalLeads, loading: leadsLoading, moveLeadToStage, setLeads } = useLeadsContext()
  /* 03/11: a equipe que o administrador pode adicionar à conversa (Adicionar pessoa) */
  const { members: membrosDaOrg } = useOrganizationMembers(organizationId || '')
  const equipeDaConversa = montarAtendentes(membrosDaOrg || [])

  const searchParams = useSearchParams()
  const router = useRouter()
  const leadIdFromUrl = searchParams.get('leadId')
  /* Chave do pedido vindo do endereço: a conversa MAIS a marca de abertura que
     os links internos carregam (ver src/lib/links.ts). */
  const pedidoDaUrl = leadIdFromUrl ? `${leadIdFromUrl}|${searchParams.get('abrir') ?? ''}` : null

  // Cada aba mostra SÓ a sua linha de WhatsApp (Tel, 25/09).
  const allLeads = globalLeads.filter((l) => {
    // 03/11 (Pedro): misto de leads -- a conversa de outra linha posta também nesta aba aparece aqui
    if (!apareceNaAba(l, linha)) return false
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
  const { marcas } = useParceriaMarcas(ehParceria)

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
  /* 535 (Pedro, 30/10: "uma segunda barra à direita, essa de cadastrar o imóvel desse contato"): a barra de cadastro
     pelo link da OLX, só no WhatsApp Leads; é de uma conversa só (trocar de conversa fecha) */
  const [cadastroDe, setCadastroDe] = useState<string | null>(null)
  /*
   * UMA fonte de verdade para a conversa aberta: o que a pessoa escolheu.
   * O endereço (`?leadId=`) é só ENTRADA (ver crm/CLAUDE.md).
   */
  const ultimaUrlVista = useRef<string | null>(null)

  /* 03/11: a aba em que a conversa foi escolhida -- a de outra linha, achada na lupa, abre AQUI (misto) */
  const abaDaEscolha = useRef<LinhaWhatsapp | null>(null)
  const handleSelectLead = useCallback((lead: LeadWithOwner) => {
    abaDaEscolha.current = linha
    setSelectedLead(lead)
    setMobileView('conversation')
    try { localStorage.setItem(chaveUltimaConversa, lead.id) } catch {}
  }, [chaveUltimaConversa, linha])

  useEffect(() => {
    if (!leadIdFromUrl) return
    if (pedidoDaUrl === ultimaUrlVista.current) return
    ultimaUrlVista.current = pedidoDaUrl
    if (selectedLead?.id === leadIdFromUrl) return

    /* O LINK ABRE NA ABA DA LINHA DA CONVERSA (28/09). */
    const abrir = (alvo: LeadWithOwner) => {
      const linhaDoAlvo = getLinhaWhatsapp(alvo)
      if (linhaDoAlvo && linhaDoAlvo !== linha && !apareceNaAba(alvo, linha)) {
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
  const soltoDestaLinha = selectedLead && (apareceNaAba(selectedLead, linha)
    || (abaDaEscolha.current === linha && LINHAS_MISTAS.includes(linha))) ? selectedLead : null
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

  /* 03/11: o que a organização da conversa gravou (tipo, misto, dentro de) entra na lista na hora */
  const aplicarOrganizacao = useCallback((leadId: string, o: Organizado) => {
    const junta = (l: LeadWithOwner): LeadWithOwner => ({
      ...l, custom_attributes: o.custom_attributes,
      ...(o.last_activity_at ? { last_activity_at: new Date(o.last_activity_at).toISOString() } : {}),
      ...(typeof o.is_unread === 'boolean' ? { is_unread: o.is_unread } : {}),
    })
    setLeads((prev) => prev.map((l) => (l.id === leadId ? junta(l) : l)))
    setSelectedLead((prev) => (prev && prev.id === leadId ? junta(prev) : prev))
  }, [setLeads])

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
    /* 03/11 (Pedro: "se o Lucas mandar mensagem para um corretor que já tem conversa lá no número Parceria, essa conversa
       fica no número Leads, com a bordinha Falando pelo número Parceria"): quem escreve de uma aba numa conversa de outra
       linha deixa a conversa também nesta aba */
    if (displayedLead && leadId && getLinhaWhatsapp(displayedLead) !== linha && LINHAS_MISTAS.includes(linha)
        && !mostrarTambemEm(displayedLead).includes(linha)) {
      organizar(leadId, { mostrarEm: { linha, ligar: true } }).then((o) => aplicarOrganizacao(leadId, o)).catch(() => undefined)
    }

    if (leadId && memberId && !alreadyHasOwner) {
      fetch(`/api/leads/${leadId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ owner_member_id: memberId }),
      }).catch((err) => console.error('Failed to auto-assign owner:', err))
    }
  }, [displayedLead, selectedLead, setLeads, currentOrganization, user, profileName, linha, aplicarOrganizacao])

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

  const isAdmin = isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || permissions?.['*']
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
      onTagsChange={handleTagsChange}
      aoOrganizar={aplicarOrganizacao}
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
      // a linha DA CONVERSA (no misto, a de outra aba): é por ela que a mensagem sai
      linha={getLinhaWhatsapp(displayedLead) || linha}
      faixaDaLinha={faixaDeOutraLinha(displayedLead, linha)}
      organizar={mudouPara(displayedLead) === linha && getLinhaWhatsapp(displayedLead) !== linha
        ? <OrganizarConversa lead={displayedLead} soDevolver={NOME_DA_LINHA[getLinhaWhatsapp(displayedLead) || 'captacao']}
                             aoMudar={(o) => aplicarOrganizacao(displayedLead.id, o)} />
        : linha === 'parceria' && getLinhaWhatsapp(displayedLead) === 'parceria'
        ? <EnviarParaAdministracaoParceria lead={displayedLead} aoMudar={(o) => aplicarOrganizacao(displayedLead.id, o)} />
        : linha === 'captacao'
        ? <OrganizarConversa lead={displayedLead} tipoDeduzido={getLinhaWhatsapp(displayedLead) === 'parceria' ? 'corretor' : null}
                             equipe={isAdmin ? equipeDaConversa : undefined}
                             aoMudar={(o) => aplicarOrganizacao(displayedLead.id, o)} />
        : undefined}
      marca={ehParceria ? marcas[displayedLead.id] : undefined}
      dono={linha === 'oficial' ? donosDaCaptacao[displayedLead.id] : undefined}
      painelAberto={painelAberto}
      aoAlternarPainel={alternarPainel}
      aoVoltar={voltar}
      onTagsChange={handleTagsChange}
      aoCadastrarImovel={linha === 'captacao' ? () => setCadastroDe((x) => (x === displayedLead.id ? null : displayedLead.id)) : undefined}
      cadastroAberto={cadastroDe === displayedLead.id}
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

  const cadastro = (modo: 'lateral' | 'gaveta') =>
    displayedLead && linha === 'captacao' && cadastroDe === displayedLead.id
      ? <CadastroImovelOlx key={displayedLead.id} lead={displayedLead} modo={modo} aoFechar={() => setCadastroDe(null)} />
      : null

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
          onTagsChange={handleTagsChange}
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
        // 17/10 (Pedro: "libera o botão enviar imóveis para todos os leads dos 2 números"): na Oficial, quem não é dono
        // da campanha também recebe imóvel -- sai pelo 8595
        extra={linha === 'oficial' ? (
          <div>
            <p className="text-[11px] font-semibold uppercase tracking-wider mb-2 text-[var(--chat-text-muted)]">Enviar imóvel</p>
            <EnviarImovelPelaCaptacao leadId={displayedLead.id} telefone={displayedLead.phone} oficial />
          </div>
        ) : undefined}
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
                  naoLidas={naoLidas} visitasAbertas={visitasAbertas}
                  abas={['conversas', 'visitas', 'pipeline', 'fechamento']} rotuloPipeline="Pipeline">
      {/* 01/11 (Pedro): o contador de visitas, meta de 3 por dia, no lugar das métricas */}
      <ContadorDeVisitas linha="parceria" />
    </AbasParceria>
  ) : linha === 'captacao' ? (
    // a barra da captação (Pedro, 29/09): hoje, as etapas e o relatório ao Tel
    <>
      {/* 18/10 (Pedro: "a agenda não está lá no número de captação ... todos os números compartilhando a mesma
          agenda"): Conversas e Visitas agendadas também aqui; a agenda é a mesma da Parceria */}
      <AbasParceria aba={aba} aoMudar={(k) => { setAba(k); if (k === 'conversas') setMobileView('list') }}
                    naoLidas={naoLidas} visitasAbertas={0} abas={['conversas', 'visitas', 'pipeline', 'arquitetura']}
                    rotuloConversas="As conversas do WhatsApp da Captação" rotuloPipeline="Pipeline">
        {/* 01/11 (Pedro): contador de visitas do Leads, meta de 1 por dia */}
        <ContadorDeVisitas linha="leads" />
      </AbasParceria>
      {/* quem só responde na captação vê o aviso sempre que abre esta tela (Pedro, 02/10) */}
      {aba === 'conversas' && soRespondeNaCaptacao(profileName || user?.name) && (
        <div role="alert" className="px-4 py-2.5 text-[13.5px] font-medium leading-snug"
             style={{ background: '#FEF3C7', color: '#78350F', borderBottom: '1px solid #F59E0B' }}>
          ⚠️ {AVISO_DA_CAPTACAO}
        </div>
      )}
      {/* 29/10 (Pedro: "não fazemos mais disparos pelo número de leads, pode retirar"): a faixa de disparos e as etapas da
          campanha saíram daqui; cada contato ganhou uma etiqueta com o nome da etapa dele */}
    </>
  ) : linha === 'oficial' ? (
    // o contador da Meta no mês (Pedro, 16/10: "quanto já disparamos ... e quanto estamos gastando") e a barrinha do
    // disparo pela API oficial (Pedro, 09/10): qual lista está saindo e quanto falta
    <>
      <AbasParceria aba={aba} aoMudar={(k) => { setAba(k); if (k === 'conversas') setMobileView('list') }}
                    naoLidas={naoLidas} visitasAbertas={0} abas={['conversas', 'visitas', 'pipeline']}
                    rotuloConversas="As conversas do número oficial (Meta)" rotuloPipeline="Pipeline" />
      {aba === 'conversas' && <BarraDoCustoOficial />}
      {aba === 'conversas' && <BarraDoDisparoOficial />}
    </>
  ) : null

  /* 29/10 (Pedro: "pôr cada pipeline do lado da agenda do número, só aparecendo o pipeline do número"): na Leads, o
     pipeline dos leads; na Parceria e na Oficial, o funil do CRM daquela linha, sem as abas dos outros números */
  /* 29/10, mais tarde (Pedro: "no Leads bugou, parece até que você refez o pipeline ao invés de pôr o pipeline de
     captação (antigo nome do número Leads), quero todos iguais aos que já tem no Parceria"): a Leads também abre o
     funil do CRM dela (WhatsApp Captação), não mais o PipelineDosLeads */
  const linhaDoFunil = ehParceria ? 'parceria' : linha === 'captacao' ? 'captacao' : 'oficial'
  /* 02/11 (Pedro: "o pipeline tá bugado para quem usa cor branca no CRM, texto que continua branco some no fundo branco"):
     .pipeline-no-chat troca as cores da paleta escura (ink, muted, line, panel) quando o tema é claro (globals.css) */
  const pipelineDoNumero = organizationId ? (
    <div className="pipeline-no-chat flex-1 min-w-0 min-h-0 flex flex-col">
      <PipelineBoard organizationId={organizationId} linha={linhaDoFunil} />
    </div>
  ) : null

  /* ── Celular: uma tela por vez; na Parceria as abas ficam em cima ── */
  if (isMobile) {
    const naConversa = mobileView === 'conversation' && aba === 'conversas'
    return (
      <div className="chat-theme h-full flex flex-col">
        {!naConversa && abas}
        {aba === 'visitas' ? (
          <div className="flex-1 min-h-0 flex"><VisitasAgendadas aoAbrirConversa={abrirConversaPorId} destaque={visitaDestaque} /></div>
        ) : aba === 'pipeline' ? (
          <div className="flex-1 min-h-0 flex">{pipelineDoNumero}</div>
        ) : aba === 'arquitetura' ? (
          <div className="flex-1 min-h-0 flex"><ArquiteturaDosAgentes /></div>
        ) : ehParceria && aba === 'fechamento' ? (
          <div className="flex-1 min-h-0 overflow-y-auto"><FechamentoChecklists /></div>
        ) : mobileView === 'list' ? (
          <div className="flex-1 min-h-0">{lista}</div>
        ) : (
          <div className="flex-1 min-h-0">{conversa(() => setMobileView('list'))}</div>
        )}
        {painelAberto && painel('gaveta')}
        {cadastro('gaveta')}
      </div>
    )
  }

  /* ── Computador: [abas da Parceria em cima] / lista | conversa | card do contato ── */
  return (
    <div className="chat-theme flex flex-col h-full min-h-0">
      {abas}
      <div className="flex flex-1 min-h-0">
        {aba === 'visitas' ? (
          <VisitasAgendadas aoAbrirConversa={abrirConversaPorId} destaque={visitaDestaque} />
        ) : aba === 'pipeline' ? (
          pipelineDoNumero
        ) : aba === 'arquitetura' ? (
          <ArquiteturaDosAgentes />
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
            {cadastro(telaLarga ? 'lateral' : 'gaveta')}
          </>
        )}
      </div>
    </div>
  )
}
