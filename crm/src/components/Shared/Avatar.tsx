'use client'

import { useState } from 'react'
import { getInitials, stringToColor } from '@/lib/utils'

interface AvatarProps {
  name: string
  imageUrl?: string
  size?: 'sm' | 'md' | 'lg'
  className?: string
  badge?: React.ReactNode
}

const sizeClasses = {
  sm: 'w-8 h-8 text-xs',
  md: 'w-12 h-12 text-sm',
  lg: 'w-16 h-16 text-base',
}

export default function Avatar({ name, imageUrl, size = 'md', className = '', badge }: AvatarProps) {
  const [imageError, setImageError] = useState(false)
  const initials = getInitials(name)
  const backgroundColor = stringToColor(name)

  const showInitials = !imageUrl || imageError

  return (
    <div className={`relative inline-block ${className}`}>
      <div
        className={`${sizeClasses[size]} rounded-full flex items-center justify-center font-bold text-white flex-shrink-0`}
        style={{ backgroundColor: showInitials ? backgroundColor : 'transparent' }}
      >
        {showInitials ? (
          initials
        ) : (
          <img
            src={imageUrl}
            alt={name}
            className="w-full h-full rounded-full object-cover"
            onError={() => setImageError(true)}
          />
        )}
      </div>
      {badge}
    </div>
  )
}
