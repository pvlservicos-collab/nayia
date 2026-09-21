'use client'

import { Question } from '@phosphor-icons/react'

interface FieldTooltipProps {
    text: string
}

/** Ícone "?" que mostra uma caixinha de ajuda ao passar o mouse (hover, sem JS). */
export default function FieldTooltip({ text }: FieldTooltipProps) {
    return (
        <span className="relative inline-flex group">
            <Question size={14} weight="bold" className="text-muted hover:text-accent-2 cursor-help transition-colors" />
            <span className="pointer-events-none absolute z-30 hidden group-hover:block bottom-full right-0 mb-2 w-56 p-2.5 bg-panel-2 border border-line rounded-lg text-xs text-ink shadow-xl font-normal normal-case tracking-normal">
                {text}
            </span>
        </span>
    )
}
