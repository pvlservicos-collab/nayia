import type { ComponentType } from 'react'
import { Phone, InstagramLogo, UsersThree } from '@phosphor-icons/react'
import type { LeadWithOwner } from '@/lib/types'

export interface LeadBadge {
  key: string
  label: string
  Icon: ComponentType<any>
  bg: string
  fg: string
  title?: string
}

/**
 * Selos de identificação rápida da conversa (grupo, canal) — pensados pra
 * ficar ao lado do nome na lista/painel, não misturados com tags de
 * pagamento/pedido que são informação secundária.
 */
export function getLeadBadges(lead: LeadWithOwner): LeadBadge[] {
  const badges: LeadBadge[] = []

  if (lead.is_group) {
    badges.push({
      key: 'group',
      label: 'Grupo',
      Icon: UsersThree,
      bg: 'rgba(251,146,60,0.18)',
      fg: '#fb923c',
      title: 'Grupo do WhatsApp — várias pessoas podem mandar mensagem nessa mesma conversa',
    })
  }

  const type = lead.integration?.type
  if (type === 'instagram_direct') {
    badges.push({ key: 'instagram', label: 'Instagram', Icon: InstagramLogo, bg: 'rgba(232,62,140,0.18)', fg: '#e83e8c' })
  } else if (type === 'whatsapp_evolution') {
    badges.push({ key: 'evolution', label: 'Nº 2', Icon: Phone, bg: 'rgba(167,139,250,0.2)', fg: '#a78bfa' })
  } else if (type === 'whatsapp_zapi') {
    badges.push({ key: 'zapi', label: 'Z-API', Icon: Phone, bg: 'rgba(45,212,191,0.18)', fg: '#2dd4bf' })
  }

  return badges
}
