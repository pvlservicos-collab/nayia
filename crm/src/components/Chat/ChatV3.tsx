'use client'

/**
 * O ATENDIMENTO DA V3 (Pedro, 04/11/2026): "um número de WhatsApp só juntando Leads e Parceria ... o lead é atendido, depois
 * que confirma que quer uma visita vai para Visitas ... nesse número vamos falar com corretores e leads; a Nay que atende
 * depende da origem". E o desenho que ele mandou ("coloca esse layout no atendimento da v3, com as funções que já estão
 * funcionando nos outros"):
 *
 *   à esquerda   Todas (a contagem) · Locação (Diego) · Venda (Rayssa) · Corretores (Nay), em coluna, com a bolinha da cor;
 *                embaixo, as conversas, cada uma com a barrinha das etapas e "etapa · quem atende" (IA quando é a Nay)
 *   no alto      o nome e "Locação · Diego"; Cadastrar imóvel, Tipo, Enviar para…, Adicionar pessoa e Dentro de
 *                (os mesmos do WhatsApp Leads: OrganizarConversa; na Parceria, o Enviar para… dela)
 *   embaixo dele a barra das 5 etapas: Começar · Filtrado · Em atend. · Opção · Visitas, a de agora em negrito
 *   em cima da caixa de mensagem: "Sai pelo WhatsApp Leads · 8595" (ou Parceria · 9445)
 *
 * É só a TELA: cada conversa continua sendo da linha dela (crm/CLAUDE.md) e a resposta sai pelo número dela; a Nay que
 * atende segue a origem (Leads: Nay Leads; Parceria: Nay Parceria). O mesmo telefone nos dois números aparece uma vez, pela
 * Parceria. Fechamento só o Tel e quem ele incluiu (a regra da v2).
 *
 * AS ETAPAS saem do que a Nay já sabe (o passo dela, 520; crm_olx_clientes_etapas), com esta leitura (as regras ficam em
 * `etapaDe`; Pedro: "testa aí, mas eu vou mudar"):
 *   Começar         a Nay ainda está perguntando o perfil (passo 1) ou nem começou
 *   Filtrado        perfil completo, busca feita (passo 2)
 *   Em atendimento  imóveis enviados, conversando sobre eles (passo 3); na Parceria, todo corretor fora de visita
 *   Opção           escolheu um e pediu visita (passo 4)
 *   Visitas         visita confirmada (passo 5) ou na etapa Visita (Leads: a etiqueta; Parceria: a etapa Visitas)
 */
import { useCallback, useMemo } from 'react'
import { useAuth, useOrganizationMembers } from '@/hooks'
import { useLeadsContext } from '@/contexts/LeadsContext'
import { usePapelDoContato } from '@/hooks/usePapelDoContato'
import { useFechamentoV2 } from '@/hooks/useFechamentoV2'
import { useCorretoresDaCaptacao } from '@/hooks/useCorretoresDaCaptacao'
import { useOlxClientes } from '@/hooks/useOlxClientes'
import { useParceriaMarcas } from '@/hooks/useParceriaMarcas'
import { useEquipeV2 } from '@/hooks/useEquipeV2'
import { getLinhaWhatsapp } from '@/lib/leadChannel'
import { fim8 } from '@/lib/olxClientes'
import { etapaDaParceria } from '@/lib/etapaDaParceria'
import { tipoEscolhido } from '@/lib/organizacaoDoLead'
import { montarAtendentes } from '@/lib/atendentes'
import { primeiroNome, responsavelV2, usePapelV2 } from '@/lib/versaoDoCrm'
import type { LeadWithOwner } from '@/lib/types'
import NotAuthorized from '@/components/Shared/NotAuthorized'
import ChatJuntado from './ChatJuntado'
import OrganizarConversa, { EnviarParaDaParceria, type Organizado } from './OrganizarConversa'

type Grupo = 'locacao' | 'venda' | 'corretores'
const GRUPOS: Array<{ chave: Grupo; rotulo: string; quem: string; cor: string }> = [
  { chave: 'locacao', rotulo: 'Locação', quem: 'Diego', cor: '#22c55e' },
  { chave: 'venda', rotulo: 'Venda', quem: 'Rayssa', cor: '#f97316' },
  { chave: 'corretores', rotulo: 'Corretores', quem: 'Nay', cor: '#ec4899' },
]
const ETAPAS = [
  { curto: 'Começar', rotulo: 'Começar', cor: '#9ca3af' },
  { curto: 'Filtrado', rotulo: 'Filtrado', cor: '#3b82f6' },
  { curto: 'Em atend.', rotulo: 'Em atendimento', cor: '#8b5cf6' },
  { curto: 'Opção', rotulo: 'Opção', cor: '#65a30d' },
  { curto: 'Visitas', rotulo: 'Visitas', cor: '#f59e0b' },
]
const SAIDA: Record<string, string> = { captacao: 'Sai pelo WhatsApp Leads · 8595', parceria: 'Sai pelo WhatsApp Parceria · 9445' }

/** o login Tel (administrador de verdade): a v3 é só dele, por enquanto */
export function useEhTel(): boolean {
  const { profileName, user } = useAuth()
  const papel = usePapelV2()
  return papel.adminDeVerdade && primeiroNome(profileName || user?.name) === 'tel'
}

/** a barra das 5 etapas embaixo do cabeçalho da conversa (a de agora em negrito; as de depois apagadas) */
function BarraDasEtapas({ atual }: { atual: number }) {
  return (
    <div className="flex-shrink-0 grid grid-cols-5 gap-1.5 px-3 pt-2 pb-1.5" style={{ borderBottom: '1px solid var(--wa-divider)' }}>
      {ETAPAS.map((e, i) => (
        <div key={e.curto} className="flex flex-col items-center gap-1 min-w-0">
          <span className="h-[5px] w-full rounded-full" style={{ background: e.cor, opacity: i <= atual ? 1 : 0.3 }} />
          <span className="text-[12px] truncate" style={{ color: i === atual ? 'var(--wa-text)' : 'var(--wa-text-2)', fontWeight: i === atual ? 700 : 400 }}>{e.curto}</span>
        </div>
      ))}
    </div>
  )
}

/** embaixo de cada conversa da lista: a barrinha (até a etapa de agora) e "etapa · quem atende" */
function RodapeDaConversa({ atual, quem }: { atual: number; quem: string }) {
  return (
    <div className="flex flex-col gap-1">
      <div className="flex items-center gap-[3px]">
        {ETAPAS.map((e, i) => (
          <span key={e.curto} className="h-[3px] flex-1 rounded-full max-w-[34px]" style={{ background: i <= atual ? e.cor : 'var(--wa-row-selected)' }} />
        ))}
      </div>
      <span className="text-[12px] truncate" style={{ color: 'var(--wa-text-2)' }}>{ETAPAS[atual].rotulo} · {quem}</span>
    </div>
  )
}

export default function ChatV3() {
  const { loading, organizationId } = useAuth()
  const ehTel = useEhTel()
  const { leads, setLeads } = useLeadsContext()
  const { ehProprietario, ehVisita, ehLocacao } = usePapelDoContato(true, true)
  const { emFechamento, podeVer } = useFechamentoV2()
  const corretoresDoLeads = useCorretoresDaCaptacao(true)
  const olx = useOlxClientes(true)
  const { marcas } = useParceriaMarcas(true)
  const equipeV2 = useEquipeV2(true)
  const { members } = useOrganizationMembers(organizationId || '')
  const equipe = useMemo(() => montarAtendentes(members || []), [members])

  // o telefone que já tem conversa na Parceria: o do Leads some (vale a Parceria)
  const pelaParceria = useMemo(() => new Set(leads.filter((l) => !l.is_group && getLinhaWhatsapp(l) === 'parceria').map((l) => fim8(l.phone)).filter(Boolean)), [leads])

  /** a conversa é desta tela? (os dois números, sem grupo, sem o repetido do Leads, e o fechamento só de quem pode) */
  const daTela = useCallback((l: LeadWithOwner): boolean => {
    const linha = getLinhaWhatsapp(l)
    if (l.is_group || (linha !== 'captacao' && linha !== 'parceria')) return false
    if (linha === 'captacao' && pelaParceria.has(fim8(l.phone))) return false
    return podeVer(l)
  }, [pelaParceria, podeVer])

  /** Locação, Venda ou Corretores (o proprietário fica só em Todas) */
  const grupoDe = useCallback((l: LeadWithOwner): Grupo | null => {
    if (!daTela(l)) return null
    const tipo = tipoEscolhido(l)
    if (getLinhaWhatsapp(l) === 'parceria' || tipo === 'corretor' || corretoresDoLeads.has(fim8(l.phone))) return 'corretores'
    if (ehProprietario(l) || emFechamento(l)) return null
    return ehLocacao(l) ? 'locacao' : 'venda'
  }, [daTela, corretoresDoLeads, ehProprietario, emFechamento, ehLocacao])

  /** a etapa de agora, 0 a 4 (ETAPAS) */
  const etapaDe = useCallback((l: LeadWithOwner): number => {
    if (getLinhaWhatsapp(l) === 'parceria') return etapaDaParceria(l as any, marcas[l.id]) === 'visitas' ? 4 : 2
    const passo = Number(olx[fim8(l.phone)]?.passo || 0)
    if (ehVisita(l) || passo >= 5) return 4
    return passo === 4 ? 3 : passo === 3 ? 2 : passo === 2 ? 1 : 0
  }, [marcas, olx, ehVisita])

  /** quem atende: a pessoa da equipe que assumiu; senão a Nay (IA) */
  const quemDe = useCallback((l: LeadWithOwner): string => {
    const r = responsavelV2(l as any, equipeV2)
    return r && !r.nay ? r.nome : 'IA'
  }, [equipeV2])

  const aplicar = useCallback((leadId: string, o: Organizado) => {
    setLeads((p) => p.map((x) => (x.id === leadId ? {
      ...x, custom_attributes: o.custom_attributes,
      ...(o.last_activity_at ? { last_activity_at: new Date(o.last_activity_at).toISOString() } : {}),
      ...(typeof o.is_unread === 'boolean' ? { is_unread: o.is_unread } : {}),
    } : x)))
  }, [setLeads])

  const etapas = useMemo(() => [
    { chave: 'todas', rotulo: 'Todas', cor: '#9ca3af', casa: daTela },
    ...GRUPOS.map((g) => ({ chave: g.chave, rotulo: g.rotulo, quem: g.quem, cor: g.cor, casa: (l: LeadWithOwner) => grupoDe(l) === g.chave })),
  ], [daTela, grupoDe])

  if (loading) return null
  if (!ehTel) return <NotAuthorized />

  return (
    <div className="chat-theme h-full min-h-0">
      <ChatJuntado titulo="Atendimento" subtitulo="Leads e Parceria num lugar só · a resposta sai pelo número de cada conversa"
                   pertence={daTela} etapas={etapas} etapasEmLista semFaixaDaLinha chaveAbas="crm:abas-v3"
                   vazio="Nenhuma conversa aqui."
                   cadastrar={() => ({})}
                   rodapeDoItem={(l) => <RodapeDaConversa atual={etapaDe(l)} quem={quemDe(l)} />}
                   naConversa={{
                     subtitulo: (l) => {
                       const g = GRUPOS.find((x) => x.chave === grupoDe(l))
                       return `${g ? g.rotulo : ehProprietario(l) ? 'Proprietário' : 'Fechamento'} · ${quemDe(l)}`
                     },
                     abaixoDoTopo: (l) => <BarraDasEtapas atual={etapaDe(l)} />,
                     saida: (l) => SAIDA[getLinhaWhatsapp(l) || ''],
                     organizar: (l) => getLinhaWhatsapp(l) === 'parceria'
                       ? <EnviarParaDaParceria lead={l} aoMudar={(o) => aplicar(l.id, o)} />
                       : <OrganizarConversa lead={l} tipoDeduzido={null} equipe={equipe} naLocacao={ehLocacao(l)}
                                            aoMudar={(o) => aplicar(l.id, o)} />,
                   }} />
    </div>
  )
}
