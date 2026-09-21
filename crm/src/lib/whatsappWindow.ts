// Janela de 24h da API oficial do WhatsApp: sem um template aprovado, só dá pra
// mandar mensagem livre até 24h depois da última mensagem do contato. Aproximação
// aqui: usa `last_activity_at` como referência (não distinguimos separadamente a
// última mensagem INBOUND de uma nossa) — suficiente pra o alerta visual.
export type WhatsAppWindowZone = 'normal' | 'warning' | 'critical' | 'closed'

export interface WhatsAppWindowState {
  zone: WhatsAppWindowZone
  remainingMs: number
  remainingLabel: string
  percentRemaining: number
}

const WINDOW_MS = 24 * 60 * 60 * 1000
const CRITICAL_THRESHOLD_MS = 60 * 60 * 1000
const WARNING_THRESHOLD_MS = 6 * 60 * 60 * 1000

function formatRemaining(ms: number): string {
  if (ms <= 0) return 'Janela encerrada'
  const totalMinutes = Math.floor(ms / 60000)
  const hours = Math.floor(totalMinutes / 60)
  const minutes = totalMinutes % 60
  if (hours > 0) return `${hours}h ${minutes}min restantes`
  return `${minutes}min restantes`
}

export function getWhatsAppWindowState(lastActivityAt?: string | null): WhatsAppWindowState | null {
  if (!lastActivityAt) return null
  const last = new Date(lastActivityAt).getTime()
  if (Number.isNaN(last)) return null

  const remainingMs = WINDOW_MS - (Date.now() - last)
  const percentRemaining = Math.max(0, Math.min(100, (remainingMs / WINDOW_MS) * 100))

  let zone: WhatsAppWindowZone = 'normal'
  if (remainingMs <= 0) zone = 'closed'
  else if (remainingMs <= CRITICAL_THRESHOLD_MS) zone = 'critical'
  else if (remainingMs <= WARNING_THRESHOLD_MS) zone = 'warning'

  return { zone, remainingMs, remainingLabel: formatRemaining(remainingMs), percentRemaining }
}

export const WHATSAPP_WINDOW_ZONE_COLOR: Record<WhatsAppWindowZone, string> = {
  normal: '#22c55e',
  warning: '#f97316',
  critical: '#ef4444',
  closed: '#6b7280',
}
