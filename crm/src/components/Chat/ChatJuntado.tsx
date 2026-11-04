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
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { CircleNotch, MagnifyingGlass, Plus, X } from '@phosphor-icons/react'
import { useAuth, useIsMobile } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useTiposDeContato } from '@/hooks/useTiposDeContato'
import { usePuxador } from '@/hooks/usePuxador'
import type { LeadWithOwner } from '@/lib/types'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { acharTipo, tipoEscolhido } from '@/lib/organizacaoDoLead'
import { CORES_DE_ETIQUETA, criarEtiqueta, useEtiquetas } from '@/lib/etiquetas'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import LeadListItem, { ehEtapaComoTag } from './LeadListItem'
import ChatWindow from './ChatWindow'
import ChatFilterTabs, { type FiltroDaLista } from './ChatFilterTabs'
import { casaNaBusca } from './BuscaDaLista'
import PainelContatoParceria from './PainelContatoParceria'
import PainelContatoCaptacao from './PainelContatoCaptacao'
import CadastroImovelOlx from './CadastroImovelOlx'
import type { QuemAtende } from '@/lib/versaoDoCrm'

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
  /** v2, aba Visita: as conversas em cards, um por visita (o topo de cada card e quem entra nele) */
  grupos?: (visiveis: LeadWithOwner[]) => Array<{ chave: string; topo: ReactNode; leads: LeadWithOwner[] }>
}

export default function ChatJuntado({ titulo, subtitulo, pertence, soAdmin, chaveAbas, vazio, menu, carregando, topoDoCard, cadastrar, enfeite, meus, grupos }: Props) {
  const { organizationId, loading, isMaster, roleName, permissions } = useAuth()
  const ehAdmin = !!(isMaster || ['admin', 'administrador', 'owner'].includes(roleName?.toLowerCase() || '') || (permissions as any)?.['*'])
  const pode = soAdmin ? ehAdmin : ehAdmin || !!permissions?.settings?.view_chat
  const { leads, setLeads, loading: leadsLoading } = useLeadsContext()
  const { marcas } = useParceriaMarcas(true)
  const { tipos } = useTiposDeContato()
  const etiquetas = useEtiquetas()
  const isMobile = useIsMobile()
  const telaLarga = useTelaLarga()
  const lista_ = usePuxador('crm:largura-lista', { min: 260, max: 640, padrao: 380, lado: 'direita' })
  const router = useRouter()
  const searchParams = useSearchParams()

  const [aba, setAba] = useState<string>(meus ? 'meus' : 'all')
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
    const base = leads.filter((l) => !l.is_group && !l.is_archived && pertence(l))
    if (solto && pertence(solto) && !base.some((l) => l.id === solto.id)) base.push(solto)
    return base.sort((a, b) => new Date(b.last_activity_at || b.created_at).getTime() - new Date(a.last_activity_at || a.created_at).getTime())
  }, [leads, pertence, solto])

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
  const visiveis = todas.filter((l) => buscando ? casaNaBusca(busca, l)
    : aba === 'all' ? true : aba === 'meus' ? !!meus?.(l) || l.id === selecionada
    : aba === 'nao_lidas' ? !!l.is_unread || l.id === selecionada
    : (l.lead_tags || []).some((lt: any) => lt.tag_id === aba))
  const aberta = todas.find((l) => l.id === selecionada) || null

  const filtros: FiltroDaLista[] = [
    ...(meus ? [{ chave: 'meus' as any, rotulo: 'Meus', contagem: todas.filter((l) => meus(l)).length }] : []),
    { chave: 'all', rotulo: 'Todos', contagem: todas.length },
    { chave: 'nao_lidas' as any, rotulo: 'Não lidos', contagem: todas.filter((l) => l.is_unread).length },
    ...abas.flatMap((id) => {
      const t = etiquetas.find((x) => x.id === id)
      return t ? [{ chave: id as any, rotulo: t.name, contagem: contagem(id), cor: t.color }] : []
    }),
  ]

  const abrir = (l: LeadWithOwner) => {
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
    const item = (
      <LeadListItem lead={l} isSelected={l.id === selecionada} timeStr={hora(l.last_activity_at || l.created_at)}
                    onClick={abrir} query={busca}
                    onContextMenu={(e, lead) => { e.preventDefault(); if (menu) setMenuEm({ x: e.clientX, y: e.clientY, lead }) }}
                    faixaDaLinha={NUMERO_DA_CONVERSA[linhaDe(l)] || null}
                    tipoDoContato={acharTipo(tipos, tipoEscolhido(l))} cinzas />
    )
    const e = enfeite?.(l)
    if (!e || (!e.faixa && !e.borda)) return <div key={l.id}>{item}</div>
    return (
      <div key={l.id} className="flex items-stretch">
        {e.borda && (
          <div className="w-[20px] flex-shrink-0 flex items-center justify-center" style={{ background: e.borda.cor }} title={`Quem atende: ${e.borda.nome}`}>
            <span className="text-[10px] font-bold text-white whitespace-nowrap tracking-wide" style={{ writingMode: 'vertical-rl', transform: 'rotate(180deg)' }}>
              {e.borda.nome}
            </span>
          </div>
        )}
        <div className="flex-1 min-w-0">
          {e.faixa && (
            <div className="px-3 py-[3px] text-[11.5px] font-semibold truncate" style={{ background: 'var(--wa-text)', color: 'var(--wa-panel)' }} title={e.faixa}>
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
            <button type="button" onClick={() => setEscolhendo((v) => !v)} aria-expanded={escolhendo}
                    className={`wa-icone-btn ${escolhendo ? 'wa-icone-btn--on' : ''}`} title="Escolher as etiquetas que viram aba aqui">
              {escolhendo ? <X size={20} /> : <Plus size={20} />}
            </button>
          </div>
        </div>
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
        {!buscando && <ChatFilterTabs ativo={aba as any} aoMudar={(k) => setAba(String(k))} filtros={filtros} />}
      </div>
      <div className="flex-1 overflow-y-auto overflow-x-hidden wa-rolagem">
        {buscando && visiveis.length > 0 && (
          <div className="px-4 pt-1 pb-1.5 text-[12.5px]" style={{ color: 'var(--wa-text-2)' }}>
            {visiveis.length} {visiveis.length === 1 ? 'conversa' : 'conversas'} nesta tela
          </div>
        )}
        {visiveis.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-[70%] px-8 text-center text-[14px]" style={{ color: 'var(--wa-text-2)' }}>
            {carregando ? 'Carregando…' : buscando ? 'Ninguém com esse nome ou número nesta tela' : aba !== 'all' ? 'Nenhuma conversa neste filtro' : vazio}
          </div>
        ) : (
          grupos && !buscando ? (
            /* um card por visita, com espaço entre um e outro (Pedro: "para ficar bem fácil de ver") */
            <div className="flex flex-col gap-4 p-2 pb-4">
              {grupos(visiveis).map((g) => (
                <div key={g.chave} className="rounded-xl overflow-hidden" style={{ border: '2px solid #16a34a' }}>
                  <div className="px-3 py-2 text-[13px]" style={{ background: 'color-mix(in srgb, #16a34a 12%, transparent)', color: 'var(--wa-text)' }}>{g.topo}</div>
                  {g.leads.map(linhaDaLista)}
                </div>
              ))}
            </div>
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
                faixaDaLinha={NUMERO_DA_CONVERSA[linhaDe(aberta)] || null} onTagsChange={aoMudarEtiqueta}
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
      return <PainelContatoParceria key={aberta.id} lead={aberta} modo={modo} aoFechar={alternarPainel} topo={topoDoCard?.(aberta)}
                                    aoVerVisita={() => router.push('/chat/parceria')} onTagsChange={aoMudarEtiqueta} onUpdateLead={aoMudarLead} />
    }
    return <PainelContatoCaptacao key={aberta.id} lead={aberta} modo={modo} aoFechar={alternarPainel} topo={topoDoCard?.(aberta)}
                                  oficial={linhaDe(aberta) === 'oficial'} onTagsChange={aoMudarEtiqueta} />
  }
  const cadastro = (modo: 'lateral' | 'gaveta') => aberta && cadastrar && cadastroDe === aberta.id
    ? <CadastroImovelOlx key={aberta.id} lead={aberta} modo={modo} aoFechar={() => setCadastroDe(null)} linkInicial={cadastrar(aberta).linkInicial} />
    : null

  const menuAberto = menuEm && menu && (
    <div className="fixed z-50 rounded-xl py-1.5 min-w-[220px] shadow-xl"
         style={{ left: Math.min(menuEm.x, window.innerWidth - 240), top: Math.min(menuEm.y, window.innerHeight - 200),
                  background: 'var(--wa-menu)', border: '1px solid var(--wa-divider)', color: 'var(--wa-text)' }}
         onClick={(e) => e.stopPropagation()} onContextMenu={(e) => e.preventDefault()}>
      {menu(menuEm.lead, () => setMenuEm(null))}
    </div>
  )

  if (isMobile) {
    return (
      <div className="chat-theme h-full flex flex-col">
        <div className="flex-1 min-h-0">{verConversa && aberta ? conversa(() => setVerConversa(false)) : lista}</div>
        {painel('gaveta')}
        {cadastro('gaveta')}
        {menuAberto}
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
    </div>
  )
}
