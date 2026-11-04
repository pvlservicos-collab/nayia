'use client'

import React, { createContext, useContext, useState, useEffect, useCallback, useRef, useMemo, ReactNode } from 'react'
import { LeadWithOwner } from '@/lib/types'
import { useAuth } from '@/hooks'
import { acessoV2, usePapelV2 } from '@/lib/versaoDoCrm'
import { usePusherChannel, usePusherConectado } from '@/hooks/usePusher'
import { useAtualizacaoPeriodica } from '@/hooks/useAtualizacaoPeriodica'

interface StageStats {
  count: number
  totalValue: number
}

interface LeadsContextType {
  leads: LeadWithOwner[]
  setLeads: React.Dispatch<React.SetStateAction<LeadWithOwner[]>>
  loading: boolean
  error: string | null
  stageStats: Record<string, StageStats>
  moveLeadToStage: (leadId: string, newStageId: string, oldStageId?: string, memberId?: string) => Promise<void>
  /**
   * Recarrega a lista sem piscar a tela.
   *
   * Quem cadastra um lead à mão (a fonte "Indicação", no Pipeline) precisa ver
   * o card aparecer na hora. A entrada por ingestão não passa pelo realtime que
   * atualiza esta lista sozinha, então quem grava avisa daqui.
   */
  refetch: () => Promise<void>
  /** 04/11: a tela do Leads aberta pede a lista inteira (quem só usa a Parceria) e devolve ao sair */
  abrirLeads?: () => void
  fecharLeads?: () => void
}

const LeadsContext = createContext<LeadsContextType | undefined>(undefined)

/**
 * Que fatia da base esta tela precisa.
 *
 * `conversas` pro Chat, `funil` pro Pipeline, `tudo` pra quem precisar mesmo de
 * tudo. Antes toda tela baixava tudo: 2.366 leads pra desenhar 82 conversas.
 */
export type EscopoLeads = 'conversas' | 'funil' | 'tudo'

export function LeadsProvider({ children, escopo = 'tudo' }: { children: ReactNode; escopo?: EscopoLeads }) {
  const { currentOrganization, permissions } = useAuth()
  /* 04/11 (Pedro: "o de Leads não quero que carregue para ela, só se ela clicar, e quando ela sair, sai, para não pesar"):
     quem só usa a Parceria (a Rayssa) baixa só as conversas da Parceria e as ENVIADAS para ela (Enviar para Rayssa);
     a tela do Leads aberta (ChatWhatsApp linha captacao) pede a lista inteira e, ao sair, devolve */
  const papel = usePapelV2()
  const soOsNumerosDela = !!acessoV2(papel.admin, papel.nome, papel.abas).soOsNumerosDela
  const [leadsAbertos, setLeadsAbertos] = useState(0)
  const soParceria = soOsNumerosDela && leadsAbertos === 0
  const abrirLeads = useCallback(() => setLeadsAbertos((n) => n + 1), [])
  const fecharLeads = useCallback(() => setLeadsAbertos((n) => Math.max(0, n - 1)), [])
  const [leads, setLeads] = useState<LeadWithOwner[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const organizationId = currentOrganization?.organization_id
  // Última lista recebida, pra não redesenhar a tela quando nada mudou — a
  // lista é buscada a cada poucos segundos e quase sempre vem igual.
  const ultimaAssinatura = useRef('')
  /*
   * UMA BUSCA DE CADA VEZ (Pedro, 29/09/2026: "quando aparece mensagem nova nem
   * sempre ela fica no topo da lista"). Cada aviso 'lead.updated' buscava a
   * lista inteira, e numa rajada (a Nay manda texto + card + fotos) várias
   * buscas corriam juntas: a resposta mais VELHA podia chegar por último e
   * desfazer a nova -- a conversa voltava para baixo até o aviso seguinte ou a
   * rede de segurança de 60 s. Agora quem chega com uma busca no ar só marca
   * "de novo", e a busca seguinte sai quando a atual termina: a última
   * aplicada é sempre a mais nova.
   */
  const buscando = useRef(false)
  const deNovo = useRef(false)

  /*
   * SÓ A CONVERSA QUE MUDOU (Pedro, 29/09/2026: "preciso do máximo de
   * velocidade nas mensagens no CRM... cliques rápidos sem bugar"). O aviso diz
   * QUAL conversa mudou ({ id } ou { ids }); a tela busca só ela (1 KB, ~100 ms)
   * em vez da lista inteira (352 conversas, 400 KB) -- que numa rajada de
   * mensagens era baixada, comparada e redesenhada várias vezes seguidas. Os
   * pedidos que chegam juntos viram uma busca só; uma de cada vez, pela mesma
   * razão da busca completa. A lista inteira fica para a abertura, o "não sei
   * qual mudou" e a rede de segurança de 60 s.
   */
  const idsPendentes = useRef<Set<string>>(new Set())
  const buscandoIds = useRef(false)
  const relogioIds = useRef<ReturnType<typeof setTimeout> | null>(null)
  // mudaram enquanto a lista inteira estava no ar: pedidos de novo depois dela
  const mexidosDuranteCompleta = useRef<Set<string>>(new Set())

  function parametrosBase() {
    const viewOwnOnly = permissions?.leads?.view_own_only
    const memberId = currentOrganization?.id
    // Grupos entram na lista (o Chat precisa deles); quem não quer ver grupo
    // (Pipeline) já filtra por conta própria em PipelineBoard.tsx.
    const params = new URLSearchParams({ returnAll: 'true' })
    if (escopo !== 'tudo') params.set('scope', escopo)
    if (viewOwnOnly && memberId) params.set('owner', memberId)
    if (soParceria) params.set('linha', 'parceria')
    return params
  }

  async function fetchLeads(showLoading = true) {
    if (!organizationId) { setLoading(false); return }
    if (buscando.current) { deNovo.current = true; return }
    buscando.current = true
    mexidosDuranteCompleta.current = new Set()
    try {
      if (showLoading) setLoading(true)
      setError(null)
      const res = await fetch(`/api/leads?${parametrosBase()}`)
      if (!res.ok) throw new Error('Failed to fetch leads')
      const { data } = await res.json()
      const assinatura = JSON.stringify(data || [])
      if (assinatura === ultimaAssinatura.current) return
      ultimaAssinatura.current = assinatura
      setLeads(data || [])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to fetch leads')
    } finally {
      if (showLoading) setLoading(false)
      buscando.current = false
      // o que mudou enquanto ela estava no ar pode ter vindo velho nela
      if (mexidosDuranteCompleta.current.size) {
        pedirConversas(Array.from(mexidosDuranteCompleta.current))
        mexidosDuranteCompleta.current = new Set()
      }
      if (deNovo.current) {
        deNovo.current = false
        void fetchLeads(false)
      }
    }
  }

  function pedirConversas(ids: string[]) {
    for (const id of ids) if (id) idsPendentes.current.add(id)
    if (!idsPendentes.current.size || relogioIds.current || buscandoIds.current) return
    // os avisos de uma rajada chegam juntos: espera um instante e busca todos
    relogioIds.current = setTimeout(() => { relogioIds.current = null; void buscarConversas() }, 80)
  }

  async function buscarConversas() {
    if (buscandoIds.current || !organizationId) return
    const ids = Array.from(idsPendentes.current).slice(0, 100)
    if (!ids.length) return
    ids.forEach((id) => idsPendentes.current.delete(id))
    buscandoIds.current = true
    let falhou = false
    try {
      const params = parametrosBase()
      params.set('ids', ids.join(','))
      const res = await fetch(`/api/leads?${params}`)
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      const { data } = await res.json()
      const novos: LeadWithOwner[] = data || []
      if (buscando.current) ids.forEach((id) => mexidosDuranteCompleta.current.add(id))
      // a tela já não é a última lista completa: a próxima completa aplica
      ultimaAssinatura.current = ''
      setLeads((prev) => {
        const porId = new Map(novos.map((l) => [l.id, l]))
        const pedidos = new Set(ids)
        const proxima: LeadWithOwner[] = []
        for (const l of prev) {
          const nova = porId.get(l.id)
          if (nova) { proxima.push(nova); porId.delete(l.id) }
          else if (!pedidos.has(l.id)) proxima.push(l)   // pedida e não voltou: saiu do recorte
        }
        for (const n of porId.values()) proxima.push(n)  // entrou no recorte agora
        return proxima
      })
    } catch {
      falhou = true
      ids.forEach((id) => idsPendentes.current.add(id))
    } finally {
      buscandoIds.current = false
      if (idsPendentes.current.size) {
        if (falhou) {
          // sem rede ou servidor reiniciando: tenta daqui a pouco, sem girar em falso
          if (!relogioIds.current) relogioIds.current = setTimeout(() => { relogioIds.current = null; void buscarConversas() }, 3000)
        } else {
          pedirConversas([])
        }
      }
    }
  }

  // o Pusher guarda as funções da hora da inscrição: estas são sempre as de agora
  const acoes = useRef({ fetchLeads, pedirConversas })
  acoes.current = { fetchLeads, pedirConversas }

  useEffect(() => {
    fetchLeads()
  }, [organizationId, currentOrganization?.id])

  useEffect(() => () => { if (relogioIds.current) clearTimeout(relogioIds.current) }, [])

  // 04/11: abriu ou fechou o Leads (a Rayssa): a lista muda de tamanho
  const primeiraVez = useRef(true)
  useEffect(() => {
    if (primeiraVez.current) { primeiraVez.current = false; return }
    void fetchLeads(false)
  }, [soParceria])  // eslint-disable-line react-hooks/exhaustive-deps

  // Grupo não conta pra estatística do Pipeline
  const stageStats = useMemo(() => {
    const stats: Record<string, StageStats> = {}
    for (const lead of leads) {
      if (!lead.stage_id || lead.is_group) continue
      if (!stats[lead.stage_id]) stats[lead.stage_id] = { count: 0, totalValue: 0 }
      stats[lead.stage_id].count++
      stats[lead.stage_id].totalValue += lead.value || 0
    }
    return stats
  }, [leads])

  // Real-time via Pusher
  /*
   * Atualização automática: é o que faz a conversa que acabou de receber
   * mensagem subir pro topo sozinha (a lista é ordenada pela última atividade)
   * e conversa nova aparecer sem recarregar.
   *
   * ERA DE 6 EM 6 SEGUNDOS porque o app do Pusher não existia mais e a busca
   * periódica era a única coisa que atualizava. O Tel criou o app em
   * 25/09/2026, então o tempo real voltou a funcionar e a busca vira o que ela
   * deveria ser: uma REDE DE SEGURANÇA, não o mecanismo.
   *
   * Sem Pusher configurado, continua nos 6 segundos de antes — nada regride.
   *
   * 04/10 (a Rayssa: "não estava chegando mensagem"): a rede de 60 s só vale
   * com a ligação DE PÉ. Enquanto ela está caída ou reconectando (rede ruim,
   * celular voltando do descanso) nenhum evento chega, e a lista busca sozinha
   * a cada 8 s até a ligação voltar.
   */
  const temPusher = !!process.env.NEXT_PUBLIC_PUSHER_KEY
  const pusherConectado = usePusherConectado()
  useAtualizacaoPeriodica(() => acoes.current.fetchLeads(false), !temPusher ? 6000 : pusherConectado ? 60000 : 8000,
                          { ativo: !!organizationId })

  const quaisMudaram = (data: any): string[] | null => {
    if (Array.isArray(data?.ids) && data.ids.length) return data.ids.map(String)
    if (data?.id) return [String(data.id)]
    return null
  }

  usePusherChannel(
    organizationId ? `org-${organizationId}` : '',
    {
      'lead.created': (data: any) => {
        const ids = quaisMudaram(data)
        if (ids) acoes.current.pedirConversas(ids)
        else acoes.current.fetchLeads(false)
      },
      'lead.updated': (data: any) => {
        const ids = quaisMudaram(data)
        if (ids) acoes.current.pedirConversas(ids)
        else acoes.current.fetchLeads(false)
      },
      'lead.deleted': (data: any) => {
        if (data?.id) setLeads(prev => prev.filter(l => l.id !== data.id))
      },
      '__reconnected': () => acoes.current.fetchLeads(false),
    }
  )

  const moveLeadToStage = useCallback(
    async (leadId: string, newStageId: string, oldStageId?: string) => {
      setLeads(prev => prev.map(l => l.id === leadId ? { ...l, stage_id: newStageId } : l))
      try {
        const res = await fetch(`/api/leads/${leadId}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ stage_id: newStageId }),
        })
        if (!res.ok) throw new Error('Failed to update lead stage')
      } catch (err) {
        console.error('Failed to update lead stage:', err)
        if (oldStageId) {
          setLeads(prev => prev.map(l => l.id === leadId ? { ...l, stage_id: oldStageId } : l))
        }
        throw err
      }
    },
    [organizationId]
  )

  return (
    <LeadsContext.Provider value={{ leads, setLeads, loading, error, stageStats, moveLeadToStage, refetch: () => fetchLeads(false), abrirLeads, fecharLeads }}>
      {children}
    </LeadsContext.Provider>
  )
}

export function useLeadsContext() {
  const context = useContext(LeadsContext)
  if (context === undefined) throw new Error('useLeadsContext must be used within a LeadsProvider')
  return context
}
