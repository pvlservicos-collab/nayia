'use client'

import { RocketLaunch, type Icon } from '@phosphor-icons/react'
import Button from './Button'

interface EmptyStateProps {
    icon?: Icon
    title: string
    description?: string
    actionLabel?: string
    onAction?: () => void
    actionHref?: string
    className?: string
}

export default function EmptyState({
    icon: Icon = RocketLaunch,
    title,
    description,
    actionLabel,
    onAction,
    actionHref,
    className = '',
}: EmptyStateProps) {
    return (
        <div className={`flex flex-col items-center justify-center text-center py-16 px-6 ${className}`}>
            <div className="w-14 h-14 rounded-2xl bg-panel-2 border border-accent-line flex items-center justify-center mb-5 shadow-glow">
                <Icon size={28} weight="fill" className="text-accent-2" />
            </div>
            <h3 className="text-lg font-semibold text-ink mb-1.5">{title}</h3>
            {description && <p className="text-sm text-muted max-w-sm mb-6">{description}</p>}
            {actionLabel && (onAction || actionHref) && (
                <Button variant="primary" href={actionHref} onClick={onAction} showArrow>
                    {actionLabel}
                </Button>
            )}
        </div>
    )
}
