'use client'

import { memo } from 'react'
import { LeadWithOwner } from '@/lib/types'
import { getLeadBadges } from '@/lib/channelBadge'

interface LeadBadgesProps {
  lead: LeadWithOwner
  size?: 'sm' | 'md'
}

function LeadBadges({ lead, size = 'sm' }: LeadBadgesProps) {
  const badges = getLeadBadges(lead)
  if (badges.length === 0) return null

  const textSize = size === 'sm' ? 'text-[10px]' : 'text-[11px]'
  const iconSize = size === 'sm' ? 10 : 12
  const padding = size === 'sm' ? 'px-1.5 py-[3px]' : 'px-2.5 py-1'

  return (
    <>
      {badges.map((b) => (
        <span
          key={b.key}
          title={b.title || b.label}
          className={`inline-flex items-center gap-1 ${textSize} font-bold uppercase tracking-wide ${padding} rounded-full flex-shrink-0`}
          style={{ backgroundColor: b.bg, color: b.fg }}
        >
          <b.Icon size={iconSize} weight="bold" />
          {b.label}
        </span>
      ))}
    </>
  )
}

export default memo(LeadBadges)
