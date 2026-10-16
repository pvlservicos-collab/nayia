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
}

export const ehEtapaOlx = (v: unknown): v is EtapaOlx => ETAPAS_OLX.some((e) => e.chave === v)
export const fim8 = (t?: string | null) => String(t || '').replace(/\D/g, '').slice(-8)
