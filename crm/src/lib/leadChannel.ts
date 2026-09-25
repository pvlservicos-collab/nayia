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

/**
 * As DUAS LINHAS DE WHATSAPP da Imob Easy (Tel, 25/09/2026):
 *
 *   captacao  -- o numero novo, pela API Oficial da Meta (Cloud API).
 *                E dele que sai a campanha de proprietarios.
 *   parceria  -- o numero que ja esta no ar pela Z-API, onde a Nay atende
 *                corretor parceiro.
 *
 * Cada uma e uma aba propria no CRM. A conversa sabe de qual linha e pelo
 * TIPO da integracao -- e nao pelo numero -- porque o numero muda e o tipo
 * nao: trocar o chip da captacao nao pode misturar as duas telas.
 */
export type LinhaWhatsapp = 'captacao' | 'parceria'

export function getLinhaWhatsapp(lead: LeadWithOwner): LinhaWhatsapp | null {
  const type = lead.integration?.type
  if (type === 'whatsapp_cloud_official') return 'captacao'
  if (type === 'whatsapp_zapi') return 'parceria'
  // Sem tipo (nao veio pelo JOIN) mas com integracao: cai na parceria, que e
  // a linha que ja existia antes das duas abas. Assim nenhuma conversa
  // antiga some da tela enquanto a integracao nova nao esta configurada.
  if (!type && lead.integration_id) return 'parceria'
  return null
}
