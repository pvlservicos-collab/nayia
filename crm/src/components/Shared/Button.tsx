'use client'

/**
 * Botão do app. Fachada fina em cima do <Button> do design system
 * (src/components/UI) — mantém a API antiga (`variant`, `href`, `showArrow`)
 * que já está espalhada pelas telas.
 *
 * O primário era `bg-gradient-to-r from-[#4f8bff] to-[#2f6bf0]` — um azul que
 * não existe mais na marca, e num degradê que a gente decidiu não usar em
 * botão. Agora todas as variantes têm preenchimento sólido e o acabamento
 * vai na borda (ver a seção BOTÕES em globals.css).
 */

import Link from 'next/link'
import { ArrowRight } from '@phosphor-icons/react'
import { buttonClass, type ButtonVariant, type ButtonSize } from '@/components/UI'

interface ButtonProps {
    variant?: ButtonVariant
    size?: ButtonSize
    href?: string
    onClick?: () => void
    type?: 'button' | 'submit'
    disabled?: boolean
    className?: string
    showArrow?: boolean
    children: React.ReactNode
}

export default function Button({
    variant = 'primary',
    size = 'md',
    href,
    onClick,
    type = 'button',
    disabled,
    className = '',
    showArrow,
    children,
}: ButtonProps) {
    const classes = buttonClass(variant, size, `group ${className}`)
    const content = (
        <>
            {children}
            {showArrow && (
                <ArrowRight size={16} weight="bold" className="transition-transform group-hover:translate-x-1" />
            )}
        </>
    )

    if (href) {
        return (
            <Link href={href} className={classes}>
                {content}
            </Link>
        )
    }

    return (
        <button type={type} onClick={onClick} disabled={disabled} className={classes}>
            {content}
        </button>
    )
}
