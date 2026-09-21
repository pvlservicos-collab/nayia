/**
 * Configuração padrão do atendimento: as colunas do Kanban e os dois funis de
 * mensagem que rodam quando um lead entra por uma das fontes.
 *
 * Este arquivo é a ÚNICA descrição desse fluxo: POST /api/setup/atendimento
 * cria no banco exatamente o que está aqui.
 *
 * Ficar em um lugar só é o que evita o cenário chato: mudar a mensagem de
 * follow-up na tela e ela continuar velha no seed, ou vice-versa.
 *
 * A coluna "Fonte:" do Kanban NÃO está aqui de propósito — ela é fixa, desenhada
 * pelo board (src/components/Pipeline/SourceRail.tsx), não é uma etapa. As
 * quatro abaixo são etapas de verdade e podem ser editadas em
 * Configurações → Pipeline; a "Fonte:" não.
 */
import type { LeadSourceKey } from '@/lib/leadSources'

/** Identifica cada etapa no código sem depender do uuid que o banco vai gerar. */
export type StageKey = 'em_aguardo' | 'contactado_ia' | 'follow_up' | 'atendimento_humano' | 'comprou'

export interface DefaultStage {
  key: StageKey
  name: string
  color: string
  rank: number
}

export const DEFAULT_PIPELINE_NAME = 'Atendimento'

export const DEFAULT_STAGES: DefaultStage[] = [
  // "Em aguardo" é a primeira de propósito: a ingestão põe todo lead novo na
  // etapa de menor rank, então quem entra cai aqui e só sai quando a IA (ou
  // alguém) realmente falar com ele. Sem esta coluna, o lead nascia em
  // "Contactado por IA" sem ninguém ter contactado nada.
  { key: 'em_aguardo', name: 'Em aguardo', color: '#7b7b76', rank: 0 },
  { key: 'contactado_ia', name: 'Contactado por IA', color: '#8b5cf6', rank: 1 },
  { key: 'follow_up', name: 'Em follow up', color: '#f59e0b', rank: 2 },
  { key: 'atendimento_humano', name: 'Atendimento por humano', color: '#3987e5', rank: 3 },
  { key: 'comprou', name: 'Comprou produto', color: '#199e70', rank: 4 },
]

/** Minutos de espera pela resposta antes de cair no follow-up. */
export const FOLLOW_UP_MINUTES = 15

/* ── Blocos ───────────────────────────────────────────────────────────────── */

/** Um bloco do funil, ainda sem id do banco. `stage` vira `config.stageId`. */
export interface DefaultBlock {
  key: string
  type: 'trigger' | 'message' | 'wait' | 'condition' | 'move_stage' | 'end'
  x: number
  y: number
  config?: Record<string, unknown>
  /** Só para move_stage: qual etapa. Resolvido pra uuid na hora de gravar. */
  stage?: StageKey
}

export interface DefaultConnection {
  from: string
  to: string
  branch: 'default' | 'yes' | 'no'
}

export interface DefaultFunnel {
  source: LeadSourceKey
  name: string
  trigger: string
  blocks: DefaultBlock[]
  connections: DefaultConnection[]
}

/**
 * O fluxo pedido, igual para as duas fontes — só muda o texto das mensagens:
 *
 *   entrou em [Em aguardo] → [Contactado por IA] → mensagem de abertura
 *                                      ↓
 *                            respondeu em 15 min?
 *                       sim ↙                    ↘ não
 *          [Atendimento por humano]      [Em follow up] → mensagem de follow-up
 *
 * O move_stage logo depois do gatilho é o que tira o lead de "Em aguardo": ele
 * entra lá (etapa de menor rank) e só vira "Contactado por IA" quando o funil
 * de fato dispara. Sem esse bloco, todo lead novo já nasceria marcado como
 * contactado sem ninguém ter falado com ele.
 */
function buildFlow(opts: { abertura: string; followUp: string }): {
  blocks: DefaultBlock[]
  connections: DefaultConnection[]
} {
  const blocks: DefaultBlock[] = [
    { key: 'trigger', type: 'trigger', x: 0, y: 160 },
    { key: 'marca_ia', type: 'move_stage', x: 300, y: 160, stage: 'contactado_ia' },
    { key: 'abertura', type: 'message', x: 600, y: 160, config: { text: opts.abertura } },
    {
      key: 'respondeu',
      type: 'condition',
      x: 900,
      y: 160,
      config: { conditionType: 'respondeu', value: FOLLOW_UP_MINUTES, unit: 'minutes' },
    },
    { key: 'para_humano', type: 'move_stage', x: 1240, y: 40, stage: 'atendimento_humano' },
    { key: 'fim_humano', type: 'end', x: 1540, y: 40 },
    { key: 'para_followup', type: 'move_stage', x: 1240, y: 300, stage: 'follow_up' },
    { key: 'msg_followup', type: 'message', x: 1540, y: 300, config: { text: opts.followUp } },
    { key: 'fim_followup', type: 'end', x: 1840, y: 300 },
  ]

  const connections: DefaultConnection[] = [
    { from: 'trigger', to: 'marca_ia', branch: 'default' },
    { from: 'marca_ia', to: 'abertura', branch: 'default' },
    { from: 'abertura', to: 'respondeu', branch: 'default' },
    { from: 'respondeu', to: 'para_humano', branch: 'yes' },
    { from: 'para_humano', to: 'fim_humano', branch: 'default' },
    { from: 'respondeu', to: 'para_followup', branch: 'no' },
    { from: 'para_followup', to: 'msg_followup', branch: 'default' },
    { from: 'msg_followup', to: 'fim_followup', branch: 'default' },
  ]

  return { blocks, connections }
}

export const DEFAULT_FUNNELS: DefaultFunnel[] = [
  {
    source: 'site_evento',
    name: 'Atendimento Site Ascensão',
    trigger: 'lead_site_evento',
    ...buildFlow({
      abertura:
        'Oi {nome}! Aqui é da equipe do Evento Ascensão 👋\n\n' +
        'Recebi sua inscrição pelo site. Me conta rapidinho: o que te fez querer participar?',
      followUp:
        'Oi {nome}, passando aqui de novo 🙂\n\n' +
        'Vi que sua inscrição no Evento Ascensão ficou pendente. ' +
        'Quer que eu te mande os detalhes de data e horário?',
    }),
  },
  {
    source: 'agenda_ascensao',
    name: 'Atendimento Agenda Ascensão',
    trigger: 'lead_agenda_ascensao',
    ...buildFlow({
      abertura:
        'Oi {nome}! Aqui é da equipe da Minha Agenda em Ascensão 👋\n\n' +
        'Acabei de ver que você montou sua agenda. Posso te mandar a leitura dos seus 3 Faróis?',
      followUp:
        'Oi {nome}, tudo certo? 🙂\n\n' +
        'Sua agenda ficou pronta e ainda não conversamos sobre ela. ' +
        'Quer que eu te mostre onde estão os maiores vazamentos de tempo da sua semana?',
    }),
  },
]
