/**
 * Formatos e cores da tela Início.
 *
 * Este arquivo já foi um pacote de dados de demonstração. Os números agora vêm
 * de GET /api/metrics/dashboard, contados no banco — o que sobrou aqui é só o
 * que a API não tem por que devolver: os tipos e a cor de cada fonte na tela.
 *
 * Os canais também mudaram: eram quatro inventados (form / site / instagram /
 * indicações) e passaram a ser as fontes de lead que existem de verdade,
 * declaradas em src/lib/leadSources.ts. Assim acrescentar uma fonte nova
 * aparece no dashboard sozinho.
 */
import { LEAD_SOURCES, LEAD_SOURCE_ORDER, ACQUISITION_SOURCE_ORDER, type LeadSourceKey } from '@/lib/leadSources'

export type AcquisitionChannel = LeadSourceKey

/** Cor de cada fonte nos cards e no gráfico. */
const CHANNEL_COLORS: Record<LeadSourceKey, string> = {
  agenda_ascensao: '#f2c744',
  site_evento: '#5fd39b',
  indicacao: '#7aa2f7',
  agenda_antigos: '#7b7b76',
}

export const CHANNEL_META: Record<AcquisitionChannel, { label: string; color: string }> =
  Object.fromEntries(
    LEAD_SOURCE_ORDER.map((key) => [key, { label: LEAD_SOURCES[key].label, color: CHANNEL_COLORS[key] }])
  ) as Record<AcquisitionChannel, { label: string; color: string }>

/**
 * O dashboard mostra só as fontes que são aquisição de verdade — lista
 * importada de planilha fica de fora (ver countsInMetrics em leadSources).
 */
export const CHANNEL_ORDER: AcquisitionChannel[] = ACQUISITION_SOURCE_ORDER

export interface ChannelTotals {
  channel: AcquisitionChannel
  newCustomers: number
}

/** Um ponto por dia; uma chave por fonte, mais a data. */
export type DailyLeadPoint = { date: string } & Partial<Record<AcquisitionChannel, number>>

export interface PurchaseMetrics {
  salesCount: number
  productsSold: number
  totalValue: number
}

export interface FollowUpMetrics {
  initialRepliesCount: number
  followUpsSentCount: number
  followUpRepliesCount: number
}

export interface TopFollowUpMessage {
  id: string
  preview: string
  responseRate: number
  sentCount: number
}

/** Resposta de GET /api/metrics/dashboard. */
export interface DashboardMetrics {
  periodo_dias: number
  fontes: ChannelTotals[]
  serie_diaria: DailyLeadPoint[]
  leads: { total: number; no_periodo: number }
  compras: PurchaseMetrics
  mensagens: { recebidas: number; enviadas: number; automaticas: number }
  follow_up: FollowUpMetrics & { semResposta: number; execucoes: number }
  top_funis: { name: string; sentCount: number }[]
}

/** Estado inicial: tudo zero até a API responder. Nunca número inventado. */
export const EMPTY_METRICS: DashboardMetrics = {
  periodo_dias: 30,
  fontes: CHANNEL_ORDER.map((channel) => ({ channel, newCustomers: 0 })),
  serie_diaria: [],
  leads: { total: 0, no_periodo: 0 },
  compras: { salesCount: 0, productsSold: 0, totalValue: 0 },
  mensagens: { recebidas: 0, enviadas: 0, automaticas: 0 },
  follow_up: {
    initialRepliesCount: 0,
    followUpsSentCount: 0,
    followUpRepliesCount: 0,
    semResposta: 0,
    execucoes: 0,
  },
  top_funis: [],
}
