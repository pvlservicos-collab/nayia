export type StatusTone = 'success' | 'warning' | 'danger' | 'info'

/** Cores inline (tema escuro — Chat) por tom, reaproveitadas por qualquer pílula de status. */
export const TONE_STYLES: Record<StatusTone, { backgroundColor: string; color: string }> = {
  warning: { backgroundColor: 'rgba(234,179,8,0.15)', color: '#facc15' },
  success: { backgroundColor: 'rgba(34,197,94,0.15)', color: '#4ade80' },
  danger: { backgroundColor: 'rgba(239,68,68,0.15)', color: '#f87171' },
  info: { backgroundColor: 'rgba(59,130,246,0.15)', color: '#60a5fa' },
}

export const PAYMENT_STATUS_META: Record<string, { label: string; tone: StatusTone }> = {
  pending: { label: 'Pendente', tone: 'warning' },
  paid: { label: 'Pago', tone: 'success' },
  refunded: { label: 'Reembolsado', tone: 'danger' },
}

export const DELIVERY_STATUS_META: Record<string, { label: string; tone: StatusTone }> = {
  pending: { label: 'Pendente', tone: 'warning' },
  picking: { label: 'Em separação', tone: 'warning' },
  picked: { label: 'Separado', tone: 'info' },
  shipped: { label: 'Enviado', tone: 'info' },
  delivered: { label: 'Entregue', tone: 'success' },
  cancelled: { label: 'Cancelado', tone: 'danger' },
}

export const PAYMENT_METHOD_META: Record<string, { label: string }> = {
  pix: { label: 'PIX' },
  credit_card: { label: 'Cartão de Crédito' },
  boleto: { label: 'Boleto' },
  dinheiro: { label: 'Dinheiro' },
}
