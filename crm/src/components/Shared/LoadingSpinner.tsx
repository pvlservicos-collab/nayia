import { SpinnerGap } from '@phosphor-icons/react'

interface LoadingSpinnerProps {
    text?: string
    size?: 'sm' | 'md' | 'lg'
    className?: string
}

const sizeMap = {
    sm: { icon: 16, text: 'text-xs' },
    md: { icon: 20, text: 'text-sm' },
    lg: { icon: 28, text: 'text-sm' },
}

export default function LoadingSpinner({ text, size = 'md', className = '' }: LoadingSpinnerProps) {
    const s = sizeMap[size]

    return (
        <div className={`flex items-center justify-center gap-2 ${className}`}>
            <SpinnerGap
                size={s.icon}
                className="animate-spin text-accent"
                weight="bold"
            />
            {text && (
                <span className={`${s.text} text-muted font-medium`}>{text}</span>
            )}
        </div>
    )
}
