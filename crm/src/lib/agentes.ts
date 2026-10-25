/**
 * OS AGENTES DA NAY LEADS (Pedro, 24/10/2026; nayia 489, nay-olx/olx/agentes.py): o registro (nome, cor, o que faz),
 * a linha do tempo de cada lead e o painel da aba Arquitetura. A fonte é o banco da Nay (privado.agente e
 * privado.agente_evento); agente novo = uma linha lá, e a legenda, o histórico e o fluxograma mostram sozinhos.
 */
export type ModoDosAgentes = 'nao' | 'sombra' | 'sim'

export interface Agente {
  chave: string
  nome: string
  cor: string
  descricao: string
  tipo: 'ia' | 'codigo' | 'gente'
  modelo: string | null
  ligado: boolean
}

export interface EventoDeAgente {
  em: string
  agente: string
  nome: string
  cor: string
  acao: string
  detalhe: string
  modo: 'real' | 'sombra'
}

export interface AgenteNoPainel extends Agente {
  ativacoes: number
  sombra: number
  conversas: number
  ms_medio: number | null
  custo_usd: number
  tokens: number
  erros: number
  ultima: string | null
}

export interface PainelDosAgentes {
  horas: number
  modo: ModoDosAgentes
  agentes: AgenteNoPainel[]
  caminhos: Record<string, number>
  veto: { passou: number; barrou: number }
  replay: { em: string; resumo: Record<string, any> } | null
}

export const ROTULO_DO_MODO: Record<ModoDosAgentes, string> = {
  nao: 'Desligado (como era)',
  sombra: 'Em sombra (decide e grava, não muda o envio)',
  sim: 'Ligado',
}

/** O que cada ação quer dizer, em português, para a dica da etiqueta. */
export const ROTULO_DA_ACAO: Record<string, string> = {
  rotear: 'escolheu o caminho',
  respondeu: 'respondeu ao cliente',
  calou: 'não respondeu (só cortesia)',
  enviou: 'mandou o imóvel',
  veto_passou: 'veto: o imóvel serve',
  veto_barrou: 'veto: o imóvel não serve',
  veto_erro: 'veto sem resposta',
  buscar: 'pediu a busca',
  card: 'mandou o card de novo',
  fotos: 'mandou as fotos',
  visita: 'pediu a confirmação da visita',
  confirmou_visita: 'o cliente confirmou a visita',
  perguntar: 'mandou a dúvida para a revisão',
  equipe: 'passou para a equipe',
  encerrar: 'encerrou a conversa',
  equipe_na_conversa: 'a equipe escreveu; a Nay espera',
  equipe_escreveu: 'a equipe escreveu por este número',
  equipe_no_crm: 'a equipe respondeu pelo CRM',
  busca_grupos: 'pediu nos grupos de corretores',
  busca_olx: 'perguntou aos anunciantes da OLX',
  busca_corretor: 'falou com um corretor parceiro',
  busca_base: 'olhou a nossa base',
  busca_oferta: 'ofereceu as opções',
  visita_pedida: 'visita pedida',
  visita_cliente_confirmou: 'o cliente confirmou a visita',
  visita_confirmada: 'visita confirmada',
  // 490: os passos do Fluxo (as portas e as ferramentas do código)
  chegou: 'chegou mensagem',
  abertura: 'lead novo: a abertura',
  falou: 'mandou os balões',
  chamou_de_novo: 'chamou o modelo de novo',
  buscou_na_base: 'buscou na base',
  nada_na_base: 'nada na base',
  equipe_assumiu: 'a equipe assumiu',
  equipe_ja_respondeu: 'a equipe já respondeu',
  limite_de_mensagens: 'limite de mensagens',
  so_agradeceu: 'só agradeceu',
  falhou: 'falhou',
}

/** 490: um passo do registro de fluxos (um evento de agente com o detalhe inteiro). */
export interface PassoDoTraco {
  id: number
  em: string
  agente: string
  nome: string
  cor: string
  acao: string
  resumo: string
  ms: number | null
  tokens: number
  custo_usd: number | null
  modelo: string | null
  modo: 'real' | 'sombra'
  erro: string | null
  detalhe: Record<string, unknown>
}

/** 490: um turno da Nay (a mensagem do cliente até a resposta), com os passos em ordem. */
export interface TurnoDoTraco {
  turno: string
  primeiro: number
  inicio: string
  fim: string
  duracao_ms: number
  lead: number | null
  chave8: string | null
  nome: string | null
  telefone: string | null
  origem: string | null
  etapa: string | null
  erros: number
  tokens: number
  custo_usd: number
  passos: PassoDoTraco[]
}

export function rotuloDaAcao(acao: string): string {
  if (ROTULO_DA_ACAO[acao]) return ROTULO_DA_ACAO[acao]
  if (acao.startsWith('duvida_')) return `dúvida na fila (${acao.slice(7)})`
  return acao.replace(/_/g, ' ')
}
