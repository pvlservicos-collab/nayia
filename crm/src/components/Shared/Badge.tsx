type BadgeVariant = 'neutral' | 'success' | 'warning' | 'error' | 'info'

interface BadgeProps {
    variant?: BadgeVariant
    dot?: boolean
    children: React.ReactNode
    className?: string
}

const variantClasses: Record<BadgeVariant, string> = {
    neutral: 'border-line text-muted',
    success: 'border-emerald-500/30 text-emerald-400',
    warning: 'border-orange-500/30 text-orange-400',
    error: 'border-red-500/30 text-red-400',
    info: 'border-accent-line text-accent-2',
}

export default function Badge({ variant = 'neutral', dot, children, className = '' }: BadgeProps) {
    return (
        <span
            className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border bg-panel-2 text-[10px] font-bold uppercase tracking-wide ${variantClasses[variant]} ${className}`}
        >
            {dot && <span className="w-1.5 h-1.5 rounded-full bg-current" />}
            {children}
        </span>
    )
}
