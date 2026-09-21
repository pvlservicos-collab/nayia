'use client'

import { useEffect, useState } from 'react'
import { createPortal } from 'react-dom'
import { X } from '@phosphor-icons/react'

interface ModalProps {
    isOpen: boolean
    onClose: () => void
    title?: string
    children: React.ReactNode
    maxWidthClassName?: string
}

export default function Modal({ isOpen, onClose, title, children, maxWidthClassName = 'max-w-md' }: ModalProps) {
    const [mounted, setMounted] = useState(false)
    useEffect(() => { setMounted(true) }, [])

    useEffect(() => {
        if (!isOpen) return
        const handleEsc = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
        document.addEventListener('keydown', handleEsc)
        return () => document.removeEventListener('keydown', handleEsc)
    }, [isOpen, onClose])

    if (!mounted || !isOpen) return null

    return createPortal(
        <div className="fixed inset-0 z-[100]">
            {/* Backdrop desfocado — o que está atrás continua legível, só fora de
                foco; é o que amarra o modal de vidro com o resto da tela. */}
            <div
                className="absolute inset-0 bg-black/55 backdrop-blur-sm modal-overlay-enter"
                onClick={onClose}
            />
            <div className="flex items-center justify-center min-h-screen p-4 pointer-events-none">
                <div
                    className={`glass-raised rounded-2xl w-full ${maxWidthClassName} overflow-hidden modal-content-enter pointer-events-auto relative z-10`}
                >
                    {title && (
                        <div className="flex items-center justify-between px-6 py-4 relative">
                            <h2 className="text-lg font-bold text-ink">{title}</h2>
                            <button
                                onClick={onClose}
                                className="btn-icon w-9 h-9"
                                aria-label="Fechar"
                            >
                                <X className="w-5 h-5" />
                            </button>
                            <div className="absolute bottom-0 left-0 right-0 h-px hairline-x" />
                        </div>
                    )}
                    {children}
                </div>
            </div>
        </div>,
        document.body
    )
}
