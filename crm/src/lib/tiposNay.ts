/**
 * Os tipos do que o CRM lê da Nay (ver nayLeitura.ts, que roda no servidor).
 * Separados aqui para a tela usar sem puxar o driver do banco junto.
 */
export interface MarcaDaNay {
  proprietario: boolean
  proprietarioNome: string | null
  imoveisDoDono: string[]
  corretor: boolean
  corretorNome: string | null
  creci: string | null
  visitaAberta: boolean
  visitaId: number | null
  visitaQuando: string | null
  visitaEstado: string | null
  visitaPapel: 'corretor' | 'proprietario' | null
  visitaCodigo: number | null
  telAtendendo: boolean
  telMotivo: string | null
  /** a etapa da Nay com a pessoa (nai_etapa_contato, migração 170) */
  etapa: string | null
  etapaDesde: string | null
  /** Tel, Rayssa (a voz do Tel): nem proprietário nem corretor (migração 173) */
  equipe: boolean
}

/** A chave geral da Nay (modo e pausa): vermelho para todos quando ela está parada. */
export interface EstadoDaNay {
  ligada: boolean
  motivo: string | null
}

/** As etapas da Nay, com as cores das tags "Nay: ..." do CRM (sincronizar_etapas_crm.py). */
export const ETAPA_DA_NAY: Record<string, { rotulo: string; cor: string; titulo: string }> = {
  identificacao: { rotulo: 'Identificação', cor: '#94a3b8', titulo: 'A Nay está identificando o que a pessoa procura' },
  recebeu_imovel: { rotulo: 'Recebeu imóvel', cor: '#0ea5e9', titulo: 'A pessoa já recebeu imóvel da Nay' },
  agendamento_visita: { rotulo: 'Agendamento', cor: '#f97316', titulo: 'A Nay está agendando uma visita' },
}

export interface VisitaDaNay {
  id: number
  codigo: number | null
  imovel: string | null
  estado: string
  aberta: boolean
  aguardando: string | null
  urgente: boolean
  acesso: string | null
  quando: string | null
  quandoSugerido: string | null
  criadoEm: string | null
  confirmadaCorretorEm: string | null
  aprovadaEm: string | null
  aprovadaPor: string | null
  propOkEm: string | null
  motoOkEm: string | null
  confirmadaEm: string | null
  posVisitaEm: string | null
  encerradaEm: string | null
  atualizadoEm: string | null
  resultado: string | null
  motivo: string | null
  corretorNome: string | null
  corretorChaves: string[]
  proprietarioNome: string | null
  visitanteNome: string | null
}

/** A visita como a tela recebe: sem as chaves de telefone, com a conversa do corretor. */
export type VisitaNaTela = Omit<VisitaDaNay, 'corretorChaves'> & {
  conversa: { leadId: string; titulo: string | null; avatar: string | null } | null
}

export interface EventoDaVisita {
  quando: string
  tipo: string
  detalhe: string | null
}

export interface ItemDoHistorico {
  quando: string
  tipo: 'pediu' | 'recebeu' | 'visita'
  codigo: number | null
  imovel: string | null
  detalhe: string | null
}

/** Os nomes das situações da visita, como a Rayssa lê. */
export const ESTADO_DA_VISITA: Record<string, { rotulo: string; tom: 'andamento' | 'ok' | 'atencao' | 'fim' | 'ruim' }> = {
  confirmando: { rotulo: 'Esperando o corretor confirmar', tom: 'andamento' },
  aguardando_rayssa: { rotulo: 'Esperando aprovação', tom: 'atencao' },
  aguardando_proprietario: { rotulo: 'Esperando o proprietário', tom: 'andamento' },
  negociando: { rotulo: 'Combinando outro horário', tom: 'atencao' },
  aguardando_acesso: { rotulo: 'Combinando o acesso', tom: 'andamento' },
  aguardando_motoboy: { rotulo: 'Esperando o André', tom: 'andamento' },
  confirmada: { rotulo: 'Confirmada', tom: 'ok' },
  com_tel: { rotulo: 'Com o Tel', tom: 'atencao' },
  realizada: { rotulo: 'Realizada', tom: 'fim' },
  encerrada: { rotulo: 'Encerrada', tom: 'fim' },
  cancelada: { rotulo: 'Cancelada', tom: 'ruim' },
  expirada: { rotulo: 'Expirou', tom: 'ruim' },
}

/** O que cada passo registrado pela Nay quer dizer (nai_visita_evento.tipo). */
export const EVENTO_DA_VISITA: Record<string, string> = {
  pedida: 'Visita pedida',
  corretor_confirmou: 'Corretor confirmou',
  aprovada: 'Aprovada',
  nao_aprovada: 'Não aprovada',
  telefone_do_proprietario: 'Telefone do proprietário informado',
  horario_trocado_antes_de_confirmar: 'Horário trocado antes de confirmar',
  horario_mudado_na_coleta: 'Horário mudado ao combinar',
  urgente_com_tel: 'Urgente: passou para o Tel',
  proprietario_sem_contato: 'Proprietário sem contato',
  proprietario_aceitou: 'Proprietário aceitou',
  proprietario_recusou: 'Proprietário recusou',
  proprietario_sugeriu: 'Proprietário sugeriu outro horário',
  proprietario_nao_quer: 'Proprietário não quer',
  proprietario_ok: 'Proprietário OK',
  motoboy_ok: 'André OK',
  motoboy_nao_pode: 'André não pode',
  confirmada: 'Visita confirmada',
  dados_completos: 'Dados do visitante completos',
  dados_ao_proprietario: 'Dados enviados ao proprietário',
  tel_confirmou_proprietario: 'Tel confirmou com o proprietário',
  tel_sugeriu_horario: 'Tel sugeriu horário',
  tel_remarcou: 'Tel remarcou',
  tel_2h: 'Aviso ao Tel (2h antes)',
  cancelada_pelo_tel: 'Cancelada pelo Tel',
  cancelada_pelo_corretor: 'Cancelada pelo corretor',
  cancelada: 'Cancelada',
  corretor_mudou_horario: 'Corretor mudou o horário',
  corretor_aceitou_horario_do_proprietario: 'Corretor aceitou o horário do proprietário',
  expirou_sem_confirmar: 'Expirou sem confirmar',
  aprovacao_sem_resposta: 'Aprovação sem resposta',
  expirada: 'Expirou',
  realizada: 'Realizada',
  horario_mudado_no_crm: 'Horário mudado no CRM',
  excluida_no_crm: 'Excluída no CRM',
  resultado: 'Resultado informado',
  mensagem_corretor: 'Mensagem ao corretor',
  mensagem_proprietario: 'Mensagem ao proprietário',
  mensagem_tel: 'Mensagem ao Tel',
  mensagem_motoboy: 'Mensagem ao André',
  mensagem_equipe: 'Mensagem à equipe',
}

/** O dono de uma conversa da captação, para a lista e o card (29/09, /api/captacao/donos). */
export interface DonoNaLista {
  nome: string | null; condominio: string | null; codigo: string | null; bairro: string | null
  tipo: string | null; captacaoId: number; imoveis: number
}
