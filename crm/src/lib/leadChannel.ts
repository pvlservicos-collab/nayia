import type { LeadWithOwner } from '@/lib/types'

export type LeadChannel = 'whatsapp' | 'instagram' | 'other'

/**
 * Deriva o canal de uma conversa a partir do tipo da integração associada.
 * Sem integration.type (não veio via JOIN) mas com integration_id, assume
 * WhatsApp — mesmo fallback já usado em IntegrationBadge, já que hoje toda
 * integração sem tipo mapeado é WhatsApp Lite.
 */
export function getLeadChannel(lead: LeadWithOwner): LeadChannel {
  const type = lead.integration?.type
  if (!type) return lead.integration_id ? 'whatsapp' : 'other'
  if (type === 'instagram_direct') return 'instagram'
  if (type.includes('whatsapp')) return 'whatsapp'
  return 'other'
}
