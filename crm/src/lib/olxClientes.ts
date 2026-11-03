/**
 * OS CLIENTES DA OLX NA ABA CAPTAÇÃO (Pedro, 16/10/2026: "vamos colocar novas etapas na aba captação baseada nas etapas
 * da nay que está atendendo: FILTRAR, FEITO BUSCA, IMÓVEIS ENVIADO, VISITA, PROPRIETÁRIOS, FECHAMENTO, FINALIZADOS").
 *
 * Quem põe a etapa é a Nay do WhatsApp dos clientes da OLX (nay-olx/olx/whatsapp.py, migração 385), pelo número de
 * captação (92 8595-6408): filtrar -> feito busca -> imóveis enviados -> visita. Proprietários, Fechamento e Finalizados
 * a equipe escolhe (menu do botão direito na conversa). O dado mora no banco da Nay (privado.olx_lead_whatsapp) e casa
 * com a conversa pelos 8 últimos dígitos do telefone.
 */
export const ETAPAS_OLX = [
  { chave: 'filtrar', rotulo: 'Filtrar', cor: '#2563eb', titulo: 'A Nay está perguntando o perfil: valor, bairros, quartos, crédito' },
  { chave: 'feito_busca', rotulo: 'Feito busca', cor: '#0891b2', titulo: 'A Nay buscou os imóveis (sem nada na faixa, a equipe foi avisada no grupo)' },
  { chave: 'imoveis_enviados', rotulo: 'Imóveis enviado', cor: '#16a34a', titulo: 'A Nay mandou os imóveis (card e fotos, um por vez)' },
  { chave: 'visita', rotulo: 'Visita', cor: '#be185d', titulo: 'Quer visitar: imóvel e horário anotados, a equipe combina com o proprietário e o corretor' },
  { chave: 'proprietarios', rotulo: 'Proprietários', cor: '#d97706', titulo: 'Combinando com o proprietário' },
  // 03/11, à tarde (Pedro): volta a ser Fechamento; Administração agora é o tipo de contato, só do Tel (organizacaoDoLead.ts)
  { chave: 'fechamento', rotulo: 'Fechamento', cor: '#7c3aed', titulo: 'Negócio em fechamento' },
  { chave: 'finalizado', rotulo: 'Finalizados', cor: '#6b7280', titulo: 'Atendimento encerrado' },
] as const

export type EtapaOlx = (typeof ETAPAS_OLX)[number]['chave']

export interface ClienteOlx {
  etapa: EtapaOlx | 'nova'
  nome: string | null
  codigo: number | null
  quer_visita: boolean
  /** alguém da equipe escreveu para a pessoa: a Nay saiu da conversa */
  humano: boolean
  /** 520: olx | organico | manual */
  origem?: string | null
  /** 520: o passo do atendimento da Nay, 0 a 5 (PASSOS_DA_NAY) */
  passo?: number
  /** 520: locacao | venda | null, o que a Nay entendeu do pedido */
  finalidade?: string | null
}

/** OS 5 PASSOS DO ATENDIMENTO DA NAY LEADS (Pedro, 29/10/2026: "uma barrinha sendo preenchida que mostra da etapa 1 a 5
 *  onde o lead tá, cada etapa ali em cima é uma etapa do atendimento da Nay, ela vai atender o lead e subir a barrinha
 *  dele, e depois se ele mudar de solicitação ela volta a barrinha dele sozinha"). O passo vem do banco da Nay
 *  (crm_olx_clientes_etapas, 520); a volta quando o pedido muda é do nay-olx (mudou_o_pedido). */
export const PASSOS_DA_NAY = [
  { n: 1, rotulo: 'Filtrar', titulo: 'A Nay está perguntando o perfil: valor, bairros, quartos, crédito' },
  { n: 2, rotulo: 'Busca feita', titulo: 'A Nay já tem o perfil e buscou os imóveis' },
  { n: 3, rotulo: 'Imóveis enviados', titulo: 'A Nay mandou os imóveis que servem' },
  { n: 4, rotulo: 'Visita pedida', titulo: 'O lead quer visitar: a Nay está combinando com o corretor e o proprietário' },
  { n: 5, rotulo: 'Visita confirmada', titulo: 'A visita está confirmada' },
] as const

/** O passo que conta para a aba: fechamento e finalizado enchem a barrinha, mas não são o passo 5 da Nay. */
export const passoDaAba = (c?: ClienteOlx | null): number =>
  c && c.etapa !== 'fechamento' && c.etapa !== 'finalizado' ? Number(c.passo || 0) : 0

export const ehEtapaOlx = (v: unknown): v is EtapaOlx => ETAPAS_OLX.some((e) => e.chave === v)
export const fim8 = (t?: string | null) => String(t || '').replace(/\D/g, '').slice(-8)
