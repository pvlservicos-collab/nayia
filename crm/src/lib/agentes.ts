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
}

export function rotuloDaAcao(acao: string): string {
  if (ROTULO_DA_ACAO[acao]) return ROTULO_DA_ACAO[acao]
  if (acao.startsWith('duvida_')) return `dúvida na fila (${acao.slice(7)})`
  return acao.replace(/_/g, ' ')
}
