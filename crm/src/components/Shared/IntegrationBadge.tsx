'use client'

import { memo } from 'react'
import { Phone, Robot, InstagramLogo } from '@phosphor-icons/react'
import { LeadWithOwner } from '@/lib/types'

interface IntegrationBadgeProps {
    lead: LeadWithOwner
    size?: 'sm' | 'md' | 'lg'
}

const sizeMap = {
    sm: {
        container: 'w-[18px] h-[18px] rounded-[6px]',
        icon: 12,
        offset: '-bottom-1 -right-1'
    },
    md: {
        container: 'w-5 h-5 rounded-[6px]',
        icon: 14,
        offset: '-bottom-1 -right-1'
    },
    lg: {
        container: 'w-6 h-6 rounded-[8px]',
        icon: 16,
        offset: '-bottom-1 -right-1'
    }
}

type BadgeOrigin = 'whatsapp_lite' | 'whatsapp_official' | 'whatsapp_evolution' | 'instagram' | 'api' | null

const IntegrationBadge = ({ lead, size = 'md' }: IntegrationBadgeProps) => {
    if (!lead) return null

    // Determine the origin of this lead based on integration_id
    let origin: BadgeOrigin = null

    if (lead.integration?.type) {
        // Lead has an explicit integration — use its type
        if (lead.integration.type === 'whatsapp_lite') {
            origin = 'whatsapp_lite'
        } else if (lead.integration.type === 'instagram_direct') {
            origin = 'instagram'
        } else if (lead.integration.type === 'whatsapp_evolution') {
            origin = 'whatsapp_evolution'
        } else if (lead.integration.type.includes('whatsapp')) {
            origin = 'whatsapp_official'
        } else {
            origin = 'api'
        }
    } else if (lead.integration_id) {
        // Has integration_id but integration data wasn't joined — fallback to WhatsApp Lite
        origin = 'whatsapp_lite'
    }
    // If no integration_id at all (null), the lead was created via API — no badge shown

    if (!origin) return null

    const sizeConfig = sizeMap[size]

    // Configuration per origin type
    const config = {
        whatsapp_lite: {
            bg: 'bg-blue-500',
            title: 'WhatsApp Lite',
            Icon: Phone,
        },
        whatsapp_official: {
            bg: 'bg-green-500',
            title: 'WhatsApp Oficial',
            Icon: Phone,
        },
        whatsapp_evolution: {
            bg: 'bg-violet-500',
            title: 'WhatsApp Nº 2 (Evolution)',
            Icon: Phone,
        },
        instagram: {
            bg: 'bg-fuchsia-500',
            title: 'Instagram Direct',
            Icon: InstagramLogo,
        },
        api: {
            bg: 'bg-violet-600',
            title: 'Agente IA (API)',
            Icon: Robot,
        },
    }

    const { bg, title, Icon } = config[origin]

    return (
        <div
            className={`absolute ${sizeConfig.offset} z-10 flex items-center justify-center border border-panel shadow-sm ${sizeConfig.container} ${bg}`}
            title={title}
        >
            <Icon size={sizeConfig.icon} weight="fill" className="text-white" />
        </div>
    )
}

export default memo(IntegrationBadge)
