'use client'

import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { LeadWithOwner, SearchHit } from '@/lib/types'
import { MagnifyingGlass, PushPin, Archive, ArrowCounterClockwise, ArrowLeft, Check, X, ChatCircleText, ChatCircleDots } from '@phosphor-icons/react'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'
import { useLeadSearch } from '@/hooks/useLeadSearch'
import { DIAS_CONVERSA_IMPORTADA } from '@/lib/conversas'
import { useAuth, useTags, useOrganizationMembers } from '@/hooks'
import { soRespondeNaCaptacao } from '@/lib/captacaoSoResponde'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useCaptacaoDonos } from '@/hooks/useCaptacaoDonos'
import { useOlxClientes, mudarEtapaOlx } from '@/hooks/useOlxClientes'
import { useDonosDoCadastro } from '@/hooks/useDonosDoCadastro'
import { ETAPAS_OLX, fim8, type EtapaOlx } from '@/lib/olxClientes'
/* 18/10 (Pedro): as etapas em que a Nay ainda está atendendo não são abas; quem está nelas fica em Todos */
const ETAPAS_OLX_FORA_DA_FILEIRA = new Set<string>(['filtrar', 'feito_busca', 'imoveis_enviados'])
import { montarAtendentes, atendenteDaConversa, type Atendente } from '@/lib/atendentes'
import LeadListItem from './LeadListItem'
import ChatFilterTabs, { type ChatTab, type FiltroDaLista } from './ChatFilterTabs'
import BuscaDaLista, { casaNaBusca } from './BuscaDaLista'
import { conversaEstaNaLinha, type LinhaWhatsapp } from '@/lib/leadChannel'
import { comAlguemPelaNay, etapaDaParceria, escolhaAMao } from '@/lib/etapaDaParceria'
import PranchetaDeEtiquetas from './PranchetaDeEtiquetas'
import { EditarAbas, abasQueValem, etiquetasDasEtapasDoLeads, useAbasDaLinha } from './AbasDeEtiquetas'
import { useEtiquetas } from '@/lib/etiquetas'

/*
 * HOJE / ESSA SEMANA NA PARCERIA (Pedro, 19/10/2026): "tirar Sem resposta: Últimas 6h / 24h / Essa semana. Colocar no
 * lugar uma aba Hoje (bastante destaque, até borda colorida): quando a Rayssa clicar ali ela vai ver somente as
 * conversas que mandaram mensagem no dia de hoje; é tipo um toggle. E do lado uma aba Essa semana que mostra as
 * OUTRAS conversas da semana. Se ela não marcar nenhuma, fica mostrando todas as conversas normal. Vale a todos."
 *
 * É um filtro à parte das etapas (Todos, Visitas, Tel...): soma com a aba que estiver aberta. O dia é o de Manaus
 * (a última movimentação da conversa, `last_activity_at`). Substituiu o follow-up de 29/09 (últimas 6h/24h/semana
 * sem resposta nossa), que ninguém usava.
 */
type Periodo = '' | 'hoje' | 'semana'
const DIA = 86_400_000
function diaEmManaus(iso?: string | null): string | null {
  const t = Date.parse(iso || '')
  if (!Number.isFinite(t)) return null
  return new Date(t).toLocaleDateString('en-CA', { timeZone: 'America/Manaus' })   // AAAA-MM-DD
}
function periodoDaConversa(l: { last_activity_at?: string | null }, hoje: string | null, agora: number): Periodo {
  const dia = diaEmManaus(l.last_activity_at)
  if (!dia) return ''
  if (dia === hoje) return 'hoje'
  return agora - Date.parse(l.last_activity_at || '') <= 7 * DIA ? 'semana' : ''
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
/* AS ABAS DA CAPTAÇÃO (Pedro, 30/09/2026): "as mesmas abas do parceria mas com uma
   aparência levemente diferente ... a IA vai colocando as pessoas no automático".
   Quem decide a aba é a campanha (crm_captacao_donos, migração 236); aqui é só o
   desenho: cada aba com a sua cor (o pontinho), para não confundir com a Parceria. */
/* DUAS LINHAS (Pedro, 30/09: "ficou muito longa a rolagem lateral ... divide em 2 linhas,
   colocando categorias que fazem sentido estarem próximas"):
     linha 1 = COMO ESTÁ A CONVERSA   Todos · Em andamento · Sem resposta · Com o Tel
     linha 2 = O QUE O DONO DISSE     Disponíveis · Alugados · Quer vender · Já vendeu · Tem outro imóvel */
const ABAS_DA_CAPTACAO: Array<{ chave: string; rotulo: string; cor: string; titulo: string; pessoa?: boolean; linha: 1 | 2 }> = [
  { chave: 'em_andamento', rotulo: 'Em andamento', cor: '#2563eb', titulo: 'Respondeu e a conversa ainda não fechou', linha: 1 },
  { chave: 'sem_resposta', rotulo: 'Sem resposta', cor: '#dc2626', titulo: 'Recebeu a mensagem da campanha e ainda não respondeu', linha: 1 },
  { chave: 'com_o_tel', rotulo: 'Com o Tel', cor: '#be185d', titulo: 'A Nay parou: o Tel está com a conversa', pessoa: true, linha: 1 },
  { chave: 'disponiveis', rotulo: 'Disponíveis', cor: '#16a34a', titulo: 'O dono disse que o imóvel está disponível', linha: 2 },
  { chave: 'alugados', rotulo: 'Alugados', cor: '#d97706', titulo: 'O dono disse que o imóvel está alugado', linha: 2 },
  { chave: 'quer_vender', rotulo: 'Quer vender', cor: '#7c3aed', titulo: 'O dono quer vender', linha: 2 },
  { chave: 'ja_vendeu', rotulo: 'Já vendeu', cor: '#6b7280', titulo: 'O dono disse que já vendeu', linha: 2 },
  { chave: 'tem_outro_imovel', rotulo: 'Tem outro imóvel', cor: '#0891b2', titulo: 'O dono falou de outro imóvel', linha: 2 },
]
const NA_LINHA_2_DA_CAPTACAO = new Set(ABAS_DA_CAPTACAO.filter((a) => a.linha === 2).map((a) => `cap:${a.chave}`))

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
  /** abrir conversa pelo id: a busca da etapa Proprietários precisa (30/09) */
  aoAbrirPorId?: (leadId: string) => void
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
  aoAbrirPorId,
  onUpdateLead,
  loading,
  organizationId,
}: LeadListProps) {
  const ehParceria = linha === 'parceria'
  const { profileName, user } = useAuth()
  const semLupa = soRespondeNaCaptacao(profileName || user?.name)
  const [search, setSearch] = useState('')
  const [buscaAberta, setBuscaAberta] = useState(false)
  const [activeTab, setActiveTab] = useState<ChatTab>('all')
  // 19/10: Hoje / Essa semana na Parceria -- um toggle à parte da aba
  const [periodo, setPeriodo] = useState<Periodo>('')
  // 20/10 (Tel): as abas do WhatsApp Leads são etiquetas, editáveis (AbasDeEtiquetas.tsx); só no Leads
  const abasDaLinha = useAbasDaLinha(linha === 'captacao' ? linha : null)
  const etiquetasDaEquipe = useEtiquetas()
  // a busca por nome/número, só na etapa Proprietários (30/09)
  const [buscaDono, setBuscaDono] = useState('')
  const [verArquivadas, setVerArquivadas] = useState(false)
  const [contextMenu, setContextMenu] = useState<ContextMenuState>({ visible: false, x: 0, y: 0, lead: null })

  const { marcas, nay } = useParceriaMarcas(ehParceria)
  // o dono e o imóvel de cada conversa da captação (29/09)
  // 09/10: na Oficial também, porque a captação passou a falar por lá (Pedro: "quero que apareça o imóvel do cara")
  const donos = useCaptacaoDonos(linha === 'captacao' || linha === 'oficial')
  /* OS FILTROS DA CAPTAÇÃO NA OFICIAL TAMBÉM (Pedro, 09/10: "quero lá em cima das conversas da API oficial filtros
     igual os que tem na de captação"). A aba de cada conversa vem do dono (crm_captacao_donos), e o dono é o mesmo
     pelos dois números: na Oficial aparecem Todos, Em andamento, Sem resposta, Com o Tel, Disponíveis... */
  const comAbasDaCaptacao = linha === 'captacao' || linha === 'oficial'
  /* OS CLIENTES DA OLX (Pedro, 16/10/2026: "novas etapas na aba captação baseada nas etapas da nay que está atendendo").
     A etapa vem da Nay do WhatsApp dos clientes da OLX (src/lib/olxClientes.ts); só na aba Captação, que é o número dela. */
  const olxClientes = useOlxClientes(linha === 'captacao')
  /* 16/10 (Pedro: "no CRM número captação pôr a aba proprietário também"): Proprietários da Captação vale como o da
     Parceria -- quem é dono de imóvel no cadastro entra, além do dono da campanha (migração 397) */
  const donosDoCadastro = useDonosDoCadastro(linha === 'captacao')
  const ehDono = (l: { id: string; phone?: string | null }) => !!donos[l.id] || donosDoCadastro.has(fim8(l.phone))
  const etapaOlxDe = (l: LeadWithOwner): EtapaOlx | null => {
    const c = olxClientes[fim8(l.phone)]
    return c && c.etapa !== 'nova' ? c.etapa : null
  }
  /* 18/10 (Pedro: "precisa pôr a aba Tel lá" na Captação): a conversa está com o Tel quando a etapa manual é
     Com o Tel (242, dono da campanha), quando alguém da equipe escreveu e a Nay do WhatsApp saiu (`humano`, 385),
     ou quando o card foi posto em Tel à mão. */
  const comOTelNaCaptacao = (l: LeadWithOwner): boolean =>
    (donos[l.id]?.abas || []).includes('com_o_tel') || !!olxClientes[fim8(l.phone)]?.humano || escolhaAMao(l as any) === 'tel'

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
  /* A RAYSSA (Tel, 30/09): "vamos pôr a Nay para responder a maioria das
     pessoas e escalar para a Rayssa após uma visita confirmada". Ela é uma
     atendente do CRM como as outras -- o que muda é ter lugar fixo no menu,
     ao lado do Tel. Se ninguém com esse nome estiver na organização, a aba
     simplesmente não aparece, em vez de aparecer vazia. */
  const rayssa = useMemo(
    () => atendentes.find((a) => a.nome.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().startsWith('rayssa')),
    [atendentes])

  /* TEL x RAYSSA (Pedro, 30/09): "todo mundo da aba Tel e que tenha a tag Tel
     joga para a Rayssa, ela tava respondendo pelo login dele".
     A Nay marca "o Tel está com a conversa" nos dois casos -- o que separa é o
     motivo ('Rayssa: …', migração 201) e quem mandou a última mensagem manual.
     Quem atendeu pelo login manda: se a última foi dela, é dela, mesmo quando
     a Nay diz "o Tel escreveu pelo celular" (esse aviso é o eco de QUALQUER
     mensagem manual pela linha, não sabe de quem foi). */
  const daRayssa = (l: LeadWithOwner, m: any, atendente?: { nome: string } | null) => {
    /* SÓ A ETAPA DECIDE (Pedro, 30/09/2026: "contatos que já estão marcados como todos
       estão aparecendo lá na aba Rayssa ... essas tags de atendimento que usávamos antes
       pode remover, hoje fazemos tudo por etapas"). Saiu o "quem mandou a última
       mensagem pelo login dela": valia para sempre e vencia a etapa escolhida. Agora é
       dela quem foi MANDADO para ela (no card, ou a marca 'Rayssa:' da Nay) -- e
       qualquer etapa escolhida à mão (Todos, Visitas...) tira daqui. */
    const aMao = escolhaAMao(l as any)
    if (aMao === 'rayssa') return true
    if (aMao) return false                // Todos, Visitas, Proprietários, Fechamento ou Tel: não é dela
    return !!(m?.telMotivo || '').startsWith('Rayssa:')
  }
  const doTel = (l: LeadWithOwner, m: any, atendente?: { nome: string } | null) => {
    const aMao = escolhaAMao(l as any)
    if (aMao === 'tel') return true
    if (aMao) return false                // etapa escolhida à mão (inclusive Todos) tira do Tel
    // 03/10: a pausa de 30 min de quem escreveu à mão NÃO é "com o Tel" (a conversa fica na aba dela)
    return comAlguemPelaNay(m) && !daRayssa(l, m, atendente)
  }
  /* QUEM ESTÁ COM UMA PESSOA SAI DAS ETAPAS: a conversa não está mais no fluxo
     da Nay, então não faz sentido contá-la em Todos nem em Visitas. */
  const comAlguem = (l: LeadWithOwner, m: any, atendente?: { nome: string } | null) =>
    doTel(l, m, atendente) || daRayssa(l, m, atendente)

  const [selectedTagIds, setSelectedTagIds] = useState<string[]>([])

  // quantas conversas desta linha têm cada etiqueta (o número ao lado de cada uma na prancheta)
  const contagemPorEtiqueta = useMemo(() => {
    const c: Record<string, number> = {}
    for (const l of leads) for (const lt of ((l as any).lead_tags || []) as any[]) c[lt.tag_id] = (c[lt.tag_id] || 0) + 1
    return c
  }, [leads])

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
  /* PÁGINAS NA ABA TODOS DA CAPTAÇÃO (Pedro, 19/10/2026: "mude a visualização da aba Todos em páginas, põe em ordem
     de mais recente primeiro, os grupos [as fileiras de abas] continuam lá em cima"). 50 por página, a mais recente
     primeiro (última atividade); as fixadas continuam no topo da primeira. As outras abas seguem rolando. */
  const POR_PAGINA = 50
  const [pagina, setPagina] = useState(1)

  const { results: searchResults, loading: searching } = useLeadSearch(search, linha)

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

  useEffect(() => { setPagina(1) }, [activeTab, search, verArquivadas, selectedTagIds.length, linha])

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

  /* NA OFICIAL, QUEM ESCREVEU FICA EM CIMA (Pedro, 09/10/2026: "quando o [contato] manda msg nem sobe a mensagem dele
     para cima, precisa corrigir isso agora"). A conversa subia, sim -- e era enterrada logo depois: cada modelo que
     o disparo manda conta como "última atividade", e com um modelo saindo por minuto quem só RECEBEU ia para o
     topo. Medido em 09/10: 167 conversas, 124 só de disparo; das 13 esperando resposta, a melhor estava na 22ª
     posição. Aqui a ordem era a de quem ESCREVEU por último; quem nunca escreveu vinha depois.
     12/10 (Pedro): "preciso que as conversas da aba api oficial fiquem sempre as mais recentes em cima igual as
     outras, tá toda bugada". Voltou para a ordem das outras abas (última atividade, de quem quer que seja); quem
     espera resposta se acha pelo chip "Não lido".
     13/10 (Pedro): "sempre que um proprietário mandar msg a conversa dele suba para o topo da lista, hoje só as
     minhas mensagens fazem isso". Com o disparo de volta, o mesmo enterro: quem escreveu às 10:17 estava na 108ª
     posição às 12:40. Agora vale a última mensagem de GENTE -- a do proprietário ou a que alguém do time escreveu
     à mão; o modelo do disparo e a resposta da Nay não mexem na ordem. Quem só recebeu disparo vem depois.
     21/10 (Pedro, com o disparo do outro_imovel_04 rodando e "nada no CRM"): "quem dispara volta para o topo e quem
     responde volta também, pelo evento mais recente". De novo a última atividade, como nas outras abas; a ordem de
     quem escreveu fica desligada (ultima_de_gente continua vindo da rota, para religar é só voltar esta linha). */
  const ordemDeQuemEscreveu = false
  const escreveuEm = (l: LeadWithOwner) => { const t = Date.parse(l.ultima_de_gente || ''); return Number.isFinite(t) ? t : 0 }

  const ordenados: SearchHit[] = [...daLinha].sort((a, b) => {
    const ap = !!a.lead.is_pinned
    const bp = !!b.lead.is_pinned
    if (ap !== bp) return ap ? -1 : 1
    const rank = (h: SearchHit) => (h.matchType === 'message' ? 1 : 0)
    if (rank(a) !== rank(b)) return rank(a) - rank(b)
    if (ordemDeQuemEscreveu) {
      const ea = escreveuEm(a.lead)
      const eb = escreveuEm(b.lead)
      if (ea !== eb) return eb - ea
    }
    const ta = new Date(a.lead.last_activity_at || a.lead.created_at).getTime()
    const tb = new Date(b.lead.last_activity_at || b.lead.created_at).getTime()
    return tb - ta
  })

  const arquivadas = ordenados.filter((hit) => hit.lead.is_archived)
  const semArquivados = ordenados.filter((hit) => !hit.lead.is_archived)

  // Lista de CONVERSAS, não de leads cadastrados (ver ehConversaVisivel). Na
  // busca a regra é suspensa: aí a pessoa procura alguém para começar a falar.
  // BUSCA EM TODO O NÚMERO (Pedro, 30/09): buscando, entra tudo -- arquivadas também
  const buscando = search.trim().length > 0
  const visiveis = verArquivadas
    ? arquivadas
    : buscando ? ordenados : semArquivados.filter((hit) => ehConversaVisivel(hit.lead))

  /* ── Os filtros de cima ── */
  const atendenteDoLead: Record<string, Atendente | undefined> = {}
  const contagem: Record<string, number> = { all: visiveis.length }
  const soma = (k: string) => { contagem[k] = (contagem[k] ?? 0) + 1 }
  const agora = Date.now()
  const hoje = diaEmManaus(new Date(agora).toISOString())
  for (const hit of visiveis) {
    const l = hit.lead
    if (l.is_unread) soma('nao_lidas')
    // quem da equipe mandou a última mensagem pelo CRM (29/09: Tel e Rayssa,
    // pelo login de cada um) -- vale também na Parceria agora
    const atendente = atendenteDaConversa(l.autores_manuais, atendentePorId)
    atendenteDoLead[l.id] = atendente
    if (ehParceria) {
      const m = marcas[l.id]
      // uma conversa, UMA etapa (ver src/lib/etapaDaParceria.ts)
      /* A BOLINHA DA ETAPA É O NÚMERO DE PESSOAS, não de mensagens (Pedro, 02/10:
         "quero que as notificações na bolinha lá na aba parceria não seja o número
         de mensagens mas sim o número de pessoas a responder"). Em 01/10 ela somava
         as mensagens sem ler: uma pessoa que mandou 12 mensagens virava 12. Agora
         cada conversa com mensagem sem ler conta 1, em todas as etapas, inclusive
         Todos. O balãozinho de cada conversa continua mostrando quantas mensagens. */
      const semLer = Number(l.nao_lidas || 0) > 0 || !!l.is_unread ? 1 : 0
      const comPessoa = comAlguem(l, m, atendente)
      if (!comPessoa) {
        const etapa = etapaDaParceria(l, m)
        soma(etapa)
        if (semLer) contagem[`semler:${etapa}`] = (contagem[`semler:${etapa}`] ?? 0) + semLer
      }
      if (daRayssa(l, m, atendente)) { soma('rayssa'); if (semLer) contagem['semler:rayssa'] = (contagem['semler:rayssa'] ?? 0) + semLer }
      // "Tel": a Nay diz que ele está com a conversa OU ele mandou pelo login dele
      if (doTel(l, m, atendente)) { soma('tel'); if (semLer) contagem['semler:tel'] = (contagem['semler:tel'] ?? 0) + semLer }
      // 19/10: quantas conversas se mexeram hoje e quantas nos outros dias da semana
      const p = periodoDaConversa(l, hoje, agora)
      if (p) soma(`periodo:${p}`)
    } else {
      for (const lt of (l.lead_tags || []) as any[]) {
        soma(`tag:${lt.tag_id}`)
        if (Number(l.nao_lidas || 0) > 0 || l.is_unread) contagem[`semler:tag:${lt.tag_id}`] = (contagem[`semler:tag:${lt.tag_id}`] ?? 0) + 1
      }
      if (atendente) soma(`atendente:${atendente.id}`)
      // 20/10: Hoje / Essa semana também no WhatsApp Leads
      if (linha === 'captacao') {
        const p = periodoDaConversa(l, hoje, agora)
        if (p) soma(`periodo:${p}`)
      }
      // as abas da captação (migração 236)
      if (comAbasDaCaptacao) for (const a of donos[l.id]?.abas || []) {
        soma(`cap:${a}`)
        const semLer = Number(l.nao_lidas || 0)
        if (semLer) contagem[`semler:cap:${a}`] = (contagem[`semler:cap:${a}`] ?? 0) + semLer
      }
      // as etapas da aba Captação (16/10): a do cliente da OLX; o dono da campanha conta em Proprietários
      const etapaOlx = linha === 'captacao' ? (etapaOlxDe(l) || (ehDono(l) ? 'proprietarios' : null)) : null
      if (etapaOlx) {
        soma(`olx:${etapaOlx}`)
        const semLer = Number(l.nao_lidas || 0)
        if (semLer) contagem[`semler:olx:${etapaOlx}`] = (contagem[`semler:olx:${etapaOlx}`] ?? 0) + semLer
      }
      // 18/10: a aba Tel da Captação
      if (linha === 'captacao' && comOTelNaCaptacao(l)) {
        soma('tel')
        const semLer = Number(l.nao_lidas || 0)
        if (semLer) contagem['semler:tel'] = (contagem['semler:tel'] ?? 0) + semLer
      }
    }
  }

  const filtros: FiltroDaLista[] = ehParceria
    ? [
        /* AS ETAPAS DA PARCERIA (Tel, 30/09/2026). Saiu "Não lidas"; entrou um
           menu só, com as três etapas destacadas de quem atende.

           A Nay atende em TODOS. Quando ela escala uma visita, a conversa passa
           para Visitas e quem atende é a Rayssa -- e isso é TEMPORÁRIO: "a
           pessoa fica por tempo temporário em visita enquanto a visita está
           aberta mesmo; quando finaliza ou passa o tempo ela volta para todos e
           a Nay volta a atender". Por isso a marca é `visitaAberta`, que a Nay
           já apaga sozinha ao fechar a visita -- não tem nada para arquivar
           aqui, a conversa volta de graça.

           30/09 -> 01/10, Pedro: "retira esse número que conta quantas pessoas
           tem, deixa só o número de pessoas para responder em cada etapa". Cada
           etapa mostra UM número: quem falou por último e está esperando. O
           Todos continua sem número -- é a etapa da Nay, ela responde. */
        { chave: 'all', rotulo: 'Todos', grupo: 'etapa', pessoas: contagem['semler:todos'],
          titulo: 'A Nay atende aqui. Quem está em outra etapa não aparece.' },
        { chave: 'visitas', rosa: true, rotulo: 'Visitas', grupo: 'etapa', pessoas: contagem['semler:visitas'],
          titulo: 'Com visita aberta — quem atende é a Rayssa. Fechou a visita, volta para Todos e a Nay volta a atender.' },
        { chave: 'proprietarios', rosa: true, rotulo: 'Proprietários', grupo: 'etapa', pessoas: contagem['semler:proprietarios'],
          titulo: 'Quem a Nay sabe que é dono de imóvel. Só aparece aqui.' },
        { chave: 'fechamento', rosa: true, rotulo: 'Fechamento', grupo: 'etapa', pessoas: contagem['semler:fechamento'],
          titulo: 'Já pediu o checklist — está juntando a documentação. Entra aqui sozinho quando a Nay manda o checklist.' },
        { chave: 'tel', rotulo: 'Tel', grupo: 'pessoa', pessoas: contagem['semler:tel'], titulo: 'O Tel está atendendo (a Nay parou por ele, ou ele mandou pelo login dele)' },
        ...(rayssa
          ? [{ chave: 'rayssa', rotulo: rayssa.nome, grupo: 'pessoa' as const, cor: rayssa.cor, pessoas: contagem['semler:rayssa'],
               titulo: `${rayssa.nome} está atendendo (mandou a última mensagem da equipe, pelo login dela)` }]
          : []),
      ]
    : comAbasDaCaptacao
    ? [
        { chave: 'all', rotulo: 'Todos', grupo: 'etapa' as const },
        ...ABAS_DA_CAPTACAO.map((a) => ({ chave: `cap:${a.chave}`, rotulo: a.rotulo, cor: a.cor, titulo: a.titulo,
                                          grupo: (a.pessoa ? 'pessoa' : 'etapa') as 'pessoa' | 'etapa', contagem: contagem[`cap:${a.chave}`],
                                          naoLidas: contagem[`semler:cap:${a.chave}`] })),
      ]
    : [
        { chave: 'all', rotulo: 'Todas' },
        { chave: 'nao_lidas', rotulo: 'Não lidas', contagem: contagem.nao_lidas },
        ...(ETIQUETAS_DA_LINHA[linha ?? ''] ?? [])
          .map((nome) => allTags.find((t: any) => t.name === nome))
          .filter(Boolean)
          .map((t: any) => ({ chave: `tag:${t.id}`, rotulo: t.name, cor: t.color || '#8b5cf6', contagem: contagem[`tag:${t.id}`] })),
      ]

  /* 19/10: na Parceria o follow-up de 29/09 (últimas 6h/24h/semana sem resposta) saiu; no lugar, o toggle
     Hoje / Essa semana (abaixo, `periodo`), que soma com a aba. */
  const filtrosDeFollowup: FiltroDaLista[] = linha === 'oficial' ? [
    /* NA OFICIAL, SÓ "NÃO LIDO" (Pedro, 09/10/2026: "coloca aquilo de filtrar por não lido que nem tem nas outras
       conversas ... coloca só Não lido nele"). */
    { chave: 'nao_lidas', rotulo: 'Não lido', contagem: contagem.nao_lidas, titulo: 'Só as conversas com mensagem que ninguém abriu ainda' },
  ] : []

  /* AS ETAPAS DA ABA CAPTAÇÃO (Pedro, 16/10/2026: "novas etapas na aba captação ... serão essas etapas: FILTRAR, FEITO
     BUSCA, IMÓVEIS ENVIADO, VISITA, PROPRIETÁRIOS, FECHAMENTO, FINALIZADOS"). São A fileira principal da aba (antes eram
     uma terceira fileira pequena, embaixo das abas da campanha, e ele não as achou). Proprietários junta os donos da
     campanha (as abas antigas viram o subfiltro dela) e o cliente da OLX que a equipe pôs ali. Só na Captação: a
     Oficial continua com as abas da campanha. */
  /* 18/10 (Pedro: "retira essas 3: Filtrar, Feito busca, Imóveis enviado; deixa todos os que estavam nesse estado
     dentro de Todos ... precisa pôr a aba Tel lá, mesmo que tenha 2 linhas de etapas"): as três etapas em que a Nay
     ainda está atendendo saem da fileira (quem está nelas aparece em Todos, que mostra tudo); entra Tel, de quem está
     com a conversa (a etapa manual Com o Tel, ou alguém da equipe escreveu e a Nay saiu). */
  const filtrosCaptacao: FiltroDaLista[] = linha === 'captacao'
    ? [
        { chave: 'all', rotulo: 'Todos', grupo: 'etapa' as const },
        ...ETAPAS_OLX.filter((e) => !ETAPAS_OLX_FORA_DA_FILEIRA.has(e.chave))
          .map((e) => ({ chave: `olx:${e.chave}`, rotulo: e.rotulo, cor: e.cor, grupo: 'etapa' as const,
                         titulo: e.chave === 'proprietarios'
                           ? 'Os donos de imóvel: do cadastro, da campanha e o cliente da OLX que a equipe pôs aqui'
                           : e.titulo,
                         contagem: contagem[`olx:${e.chave}`], naoLidas: contagem[`semler:olx:${e.chave}`] })),
        { chave: 'tel', rotulo: 'Tel', grupo: 'pessoa' as const, contagem: contagem['tel'], naoLidas: contagem['semler:tel'],
          titulo: 'O Tel está com a conversa: etapa Com o Tel, ou alguém da equipe escreveu e a Nay saiu' },
      ]
    : []
  /* AS ABAS SÃO ETIQUETAS (Tel, por Pedro, 20/10/2026: "troque as etapas que têm Todos, Visitas, pelas tags que têm
     pessoas ... editável"). Fica Todos + as etiquetas escolhidas (lápis no fim da fileira); o Tel continua na fileira
     de cima. SÓ NO WHATSAPP LEADS (Pedro, 20/10, mais tarde: "bugou os filtros das etapas do whatsapp parceria, eu não
     pedi para mexer lá e sim no whatsapp leads captação"): a Parceria voltou a Todos / Visitas / Proprietários /
     Fechamento pelo fato (etapaDaParceria.ts) com Tel e Rayssa, e a Oficial às abas da campanha. No Leads, sem
     edição, as abas são as etiquetas das etapas (Visita, Proprietários, Fechamento, Finalizados; 426), e não as do
     disparo. */
  const usarAbasDeEtiquetas = linha === 'captacao'
  const etapasDoLeads = usarAbasDeEtiquetas ? etiquetasDasEtapasDoLeads(etiquetasDaEquipe) : []
  const abasDeEtiqueta = usarAbasDeEtiquetas ? abasQueValem(abasDaLinha.ids, etiquetasDaEquipe, contagem, etapasDoLeads) : []
  // na linha da conversa, a etiqueta da aba (a etapa) aparece antes das outras
  const etiquetasEmDestaque = abasDeEtiqueta.map((t) => t.id)
  const filtrosDeEtiquetas: FiltroDaLista[] = [
    { chave: 'all', rotulo: 'Todos', grupo: 'etapa' as const, contagem: contagem.all },
    ...abasDeEtiqueta.map((t) => ({ chave: `tag:${t.id}`, rotulo: t.name, cor: t.color, grupo: 'etapa' as const,
                                    contagem: contagem[`tag:${t.id}`], pessoas: contagem[`semler:tag:${t.id}`] })),
  ]
  const filtrosDeQuemAtende: FiltroDaLista[] = filtrosCaptacao.filter((f) => f.grupo === 'pessoa')

  const passaNoFiltro = (hit: SearchHit): boolean => {
    const l = hit.lead
    // 20/10: no Leads, Todos é a linha inteira (como já era)
    if (usarAbasDeEtiquetas && activeTab === 'all') return true
    /* O PROPRIETÁRIO SÓ APARECE NA ETAPA DELE (Tel, 30/09): "os proprietários
       não vão aparecer em outras etapas, só ali, para ficar mais organizado".
       Vale para as ETAPAS (Todos, Visitas). Tel e Rayssa são quem atende, não
       etapa: se o Tel está com um proprietário, ele aparece na aba do Tel. */
    if (ehParceria && (activeTab === 'all' || activeTab === 'visitas'
        || activeTab === 'proprietarios' || activeTab === 'fechamento')) {
      if (comAlguem(l, marcas[l.id], atendenteDoLead[l.id])) return false
      return etapaDaParceria(l, marcas[l.id]) === (activeTab === 'all' ? 'todos' : activeTab)
    }
    if (activeTab === 'all') return true
    if (activeTab.startsWith('cap:')) return (donos[l.id]?.abas || []).includes(activeTab.slice(4))
    if (activeTab === 'olx:proprietarios') return etapaOlxDe(l) === 'proprietarios' || (!etapaOlxDe(l) && ehDono(l))
    if (activeTab.startsWith('olx:')) return etapaOlxDe(l) === activeTab.slice(4)
    if (activeTab === 'nao_lidas') return !!l.is_unread || l.id === selectedLeadId
    if (activeTab === 'rayssa') return daRayssa(l, marcas[l.id], atendenteDoLead[l.id])
    if (activeTab === 'tel' && linha === 'captacao') return comOTelNaCaptacao(l)
    if (activeTab === 'tel') return doTel(l, marcas[l.id], atendenteDoLead[l.id])
    if (activeTab.startsWith('tag:')) return (l.lead_tags || []).some((lt: any) => `tag:${lt.tag_id}` === activeTab)
    if (activeTab.startsWith('atendente:')) return `atendente:${atendenteDoLead[l.id]?.id}` === activeTab
    return true
  }

  const buscandoDono = ehParceria && activeTab === 'proprietarios' && buscaDono.trim().length > 0
  /* BUSCA DE VERDADE EM TODO O NÚMERO (Pedro, 30/09/2026: "a lupa de buscar
     contato nas conversas quero que funcione como uma busca real de leads em todo
     o número; hoje se eu tô no Tel só acho quem é do Tel"). Com a lupa, a aba
     (etapa, Tel/Rayssa, não lidas, etiqueta) não filtra: acha no número inteiro. */
  const filtradas = visiveis
    .filter((hit) => buscando || passaNoFiltro(hit))
    // 19/10: Hoje / Essa semana (Parceria) soma com a aba; com a lupa, não filtra
    .filter((hit) => buscando || !periodo || periodoDaConversa(hit.lead, hoje, agora) === periodo)
    .filter((hit) => buscando || !buscandoDono || casaNaBusca(buscaDono, hit.lead))
    .filter((hit) => buscando || selectedTagIds.length === 0 || hit.lead.lead_tags?.some((lt: any) => selectedTagIds.includes(lt.tag_id)))

  /* O ANDRÉ EM CIMA, EM VISITAS (Tel, 30/09): "o André vai ficar fixado em cima
     das conversas porque ele é da equipe e faz parte disso". Quem é da equipe
     vem da Nay: `acompanhante` é exatamente ele (migração 197), e não o
     `equipe`, que pega Tel e Rayssa junto. Só reordena, não filtra: ninguém
     some por causa disso. */
  if (ehParceria && activeTab === 'visitas') {
    filtradas.sort((a, b) => Number(!!marcas[b.lead.id]?.acompanhante) - Number(!!marcas[a.lead.id]?.acompanhante))
  }

  const emPaginas = linha === 'captacao' && activeTab === 'all' && !buscando && !verArquivadas && selectedTagIds.length === 0
  const totalDePaginas = Math.max(1, Math.ceil(filtradas.length / POR_PAGINA))
  const paginaAtual = Math.min(pagina, totalDePaginas)
  const visibleHits = emPaginas
    ? filtradas.slice((paginaAtual - 1) * POR_PAGINA, paginaAtual * POR_PAGINA)
    : filtradas.slice(0, displayLimit)
  const irParaPagina = (n: number) => {
    setPagina(Math.min(Math.max(1, n), totalDePaginas))
    if (scrollContainerRef.current) scrollContainerRef.current.scrollTop = 0
  }
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
            {/* A lupa de cima não aparece para quem só responde na captação (Pedro, 02/10/2026: "retira a
                lupa lá de cima para a Rayssa"): era por ela que a conversa nova era aberta. */}
            {!verArquivadas && !semLupa && (
              <button type="button" onClick={() => setBuscaAberta((v) => !v)} aria-expanded={buscaAberta}
                      className={`wa-icone-btn ${buscaAberta || search ? 'wa-icone-btn--on' : ''}`} title="Pesquisar conversa (nome ou número)">
                <MagnifyingGlass size={20} />
              </button>
            )}
            {/* a prancheta das etiquetas (Pedro, 17/10): filtrar e criar, nos números da Parceria e da Captação */}
            {!verArquivadas && (
              <PranchetaDeEtiquetas escolhidas={selectedTagIds} aoAlternar={toggleTagFilter} aoLimpar={() => setSelectedTagIds([])}
                                    contagem={contagemPorEtiqueta} />
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

        {/* número que não temos: a lupa inicia a conversa nesta linha (Pedro, 30/09) */}
        {buscaAberta && !verArquivadas && !searching && (
          <BuscaDaLista soBotao linha={linha} texto={search} aoMudar={setSearch} achados={filtradas.length}
                        aoAbrir={(id) => { setBuscaAberta(false); aoAbrirPorId?.(id) }} />
        )}

        {!verArquivadas && (
          <>
            {/* HOJE / ESSA SEMANA (Pedro, 19/10): toggle à parte da aba; nenhum marcado = todas as conversas.
                20/10: também no WhatsApp Leads (captação) */}
            {(ehParceria || linha === 'captacao') && (
              <div className="flex items-center gap-2 px-4 pb-2 pt-0.5 -mb-1" role="group" aria-label="Período das conversas">
                <button type="button" aria-pressed={periodo === 'hoje'}
                        className={`wa-periodo wa-periodo--hoje ${periodo === 'hoje' ? 'wa-periodo--on' : ''}`}
                        title="Só as conversas que se mexeram hoje (hora de Manaus). Clique de novo para ver todas."
                        onClick={() => setPeriodo(periodo === 'hoje' ? '' : 'hoje')}>
                  Hoje{!!contagem['periodo:hoje'] && <span className="wa-periodo__n">{contagem['periodo:hoje']}</span>}
                </button>
                <button type="button" aria-pressed={periodo === 'semana'}
                        className={`wa-periodo ${periodo === 'semana' ? 'wa-periodo--on' : ''}`}
                        title="As outras conversas da semana (dos últimos 7 dias, fora as de hoje). Clique de novo para ver todas."
                        onClick={() => setPeriodo(periodo === 'semana' ? '' : 'semana')}>
                  Essa semana{!!contagem['periodo:semana'] && <span className="wa-periodo__n">{contagem['periodo:semana']}</span>}
                </button>
              </div>
            )}
            {filtrosDeFollowup.length > 0 && (
              <div className="flex items-center gap-1 -mb-1">
                <div className="flex-1 min-w-0">
                  <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtrosDeFollowup} />
                </div>
              </div>
            )}
            {usarAbasDeEtiquetas ? (
              <>
                {filtrosDeQuemAtende.length > 0 && (
                  <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtrosDeQuemAtende} />
                )}
                <div className="flex items-center gap-1 pr-2">
                  <div className="flex-1 min-w-0">
                    <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtrosDeEtiquetas} />
                  </div>
                  <EditarAbas linha={linha as string} atuais={abasDeEtiqueta} contagem={contagem} />
                </div>
              </>
            ) : comAbasDaCaptacao ? (
              <>
                <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtros.filter((f) => !NA_LINHA_2_DA_CAPTACAO.has(f.chave))} />
                <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtros.filter((f) => NA_LINHA_2_DA_CAPTACAO.has(f.chave))} />
              </>
            ) : (
              <ChatFilterTabs ativo={activeTab} aoMudar={setActiveTab} filtros={filtros} />
            )}
            {ehParceria && activeTab === 'proprietarios' && (
              <BuscaDaLista
                texto={buscaDono}
                aoMudar={setBuscaDono}
                achados={filtradas.length}
                aoAbrir={(id) => aoAbrirPorId?.(id)}
                placeholder="Procurar proprietário por nome ou número"
              />
            )}
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

        {buscando && filtradas.length > 0 && (
          <div className="px-4 pt-1 pb-1.5 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
            {filtradas.length} {filtradas.length === 1 ? 'conversa' : 'conversas'} em todo o número (todas as abas)
          </div>
        )}
        {filtradas.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-[70%] px-8 text-center text-[14px]" style={{ color: 'var(--wa-text-2)' }}>
            {searching ? 'Buscando…'
              : search.trim() ? 'Ninguém com esse nome ou número neste WhatsApp'
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
                  etiquetasEmDestaque={usarAbasDeEtiquetas ? etiquetasEmDestaque : undefined}
                />
              )
            })}
            {emPaginas && totalDePaginas > 1 && (
              <PaginasDaLista atual={paginaAtual} total={totalDePaginas} conversas={filtradas.length} aoIr={irParaPagina} />
            )}
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
          {/* 16/10: a etapa do cliente da OLX (Proprietários, Fechamento e Finalizados são da equipe) */}
          {linha === 'captacao' && contextMenu.lead && olxClientes[fim8(contextMenu.lead.phone)] && (
            <div className="mt-1 pt-1" style={{ borderTop: '1px solid var(--wa-divider)' }}>
              <p className="px-4 py-1 text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Etapa do cliente da OLX</p>
              {ETAPAS_OLX.map((e) => {
                const atual = olxClientes[fim8(contextMenu.lead!.phone)]?.etapa === e.chave
                return (
                  <button key={e.chave} type="button"
                          onClick={async () => {
                            const tel = contextMenu.lead!.phone || ''
                            setContextMenu((prev) => ({ ...prev, visible: false }))
                            const erro = await mudarEtapaOlx(tel, e.chave)
                            if (erro) window.alert(erro)
                          }}
                          className="w-full text-left px-4 py-2 text-[14px] hover:bg-[var(--wa-row-hover)] flex items-center gap-3" style={{ color: 'var(--wa-text)' }}>
                    <span className="w-2.5 h-2.5 rounded-full flex-shrink-0" style={{ background: e.cor }} />
                    <span className="flex-1">{e.rotulo}</span>
                    {atual && <Check size={15} style={{ color: 'var(--wa-green)' }} />}
                  </button>
                )
              })}
            </div>
          )}
        </div>
      )}
    </div>
  )
}

/* O rodapé das páginas (aba Todos da Captação): anterior / números / próxima, e quantas conversas há. */
function PaginasDaLista({ atual, total, conversas, aoIr }: { atual: number; total: number; conversas: number; aoIr: (n: number) => void }) {
  const numeros: Array<number | '…'> = []
  for (let n = 1; n <= total; n++) {
    if (n === 1 || n === total || Math.abs(n - atual) <= 1) numeros.push(n)
    else if (numeros[numeros.length - 1] !== '…') numeros.push('…')
  }
  const botao = 'min-w-[32px] h-8 px-2 rounded-full text-[13px] font-semibold disabled:opacity-40'
  return (
    <div className="flex flex-col items-center gap-1.5 px-3 pt-3 pb-2" onClick={(e) => e.stopPropagation()} onPointerDown={(e) => e.stopPropagation()}>
      <div className="flex items-center gap-1 flex-wrap justify-center">
        <button type="button" className={botao} style={{ color: 'var(--wa-text)' }} disabled={atual <= 1} onClick={() => aoIr(atual - 1)}
                aria-label="Página anterior">‹</button>
        {numeros.map((n, i) => n === '…'
          ? <span key={`r${i}`} className="px-1 text-[13px]" style={{ color: 'var(--wa-text-2)' }}>…</span>
          : (
            <button key={n} type="button" className={botao} onClick={() => aoIr(n)} aria-current={n === atual ? 'page' : undefined}
                    style={n === atual ? { background: 'var(--wa-green)', color: '#fff' } : { color: 'var(--wa-text)' }}>{n}</button>
          ))}
        <button type="button" className={botao} style={{ color: 'var(--wa-text)' }} disabled={atual >= total} onClick={() => aoIr(atual + 1)}
                aria-label="Próxima página">›</button>
      </div>
      <span className="text-[12px]" style={{ color: 'var(--wa-text-2)' }}>Página {atual} de {total} · {conversas} conversas, as mais recentes primeiro</span>
    </div>
  )
}
