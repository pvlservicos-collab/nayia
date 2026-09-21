'use client'

import { useState, useRef, useEffect } from 'react'
import { Bell, Circle, CheckCircle, BellSlash } from '@phosphor-icons/react'
import { useNotifications } from '@/hooks/useNotifications'
import { Notification } from '@/lib/types'
import { useRouter } from 'next/navigation'
import { comMarcaDeAbertura } from '@/lib/links'

function formatRelativeTime(dateString: string): string {
    const now = new Date()
    const date = new Date(dateString)
    const diffMs = now.getTime() - date.getTime()
    const diffSec = Math.floor(diffMs / 1000)
    const diffMin = Math.floor(diffSec / 60)
    const diffHour = Math.floor(diffMin / 60)
    const diffDay = Math.floor(diffHour / 24)

    if (diffSec < 60) return 'Agora mesmo'
    if (diffMin < 60) return `Há ${diffMin} min`
    if (diffHour < 24) return `Há ${diffHour} hora${diffHour > 1 ? 's' : ''}`
    if (diffDay < 7) return `Há ${diffDay} dia${diffDay > 1 ? 's' : ''}`

    return date.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
}

function NotificationItem({
    notification,
    onClickNotification,
}: {
    notification: Notification
    onClickNotification: (n: Notification) => void
}) {
    return (
        <button
            onClick={() => onClickNotification(notification)}
            className={`w-full text-left px-4 py-3 flex items-start gap-3 transition-colors hover:bg-white/[0.06] ${!notification.is_read ? 'bg-[#3b82f6]/[0.10]' : ''
                }`}
        >
            {/* Unread dot */}
            <div className="pt-1.5 shrink-0">
                {!notification.is_read ? (
                    <div className="w-2 h-2 rounded-full bg-[#3b82f6]" />
                ) : (
                    <div className="w-2 h-2" />
                )}
            </div>

            {/* Content */}
            <div className="flex-1 min-w-0">
                <p className="text-sm text-[#f4f4f5] leading-snug">
                    {notification.title && (
                        <span className="font-medium">{notification.title}</span>
                    )}
                    {notification.title && notification.content && ' '}
                    {notification.content && (
                        <span className="text-[#a1a1aa]">{notification.content}</span>
                    )}
                    {!notification.title && !notification.content && (
                        <span className="text-[#a1a1aa] italic">Nova notificação</span>
                    )}
                </p>
                <p className="text-xs text-[#71717a] mt-0.5">
                    {formatRelativeTime(notification.created_at)}
                </p>
            </div>
        </button>
    )
}

export default function NotificationDropdown() {
    const [open, setOpen] = useState(false)
    const dropdownRef = useRef<HTMLDivElement>(null)
    const botaoRef = useRef<HTMLButtonElement>(null)
    /*
     * A janela abria "absolute right-0" a partir do sino, com 360px fixos. No
     * celular o sino não fica colado na borda direita (o botão de tema e o
     * avatar vêm depois), então os 360px pra esquerda passavam da tela. Agora
     * ela é posicionada pela tela: alinhada ao sino quando cabe, empurrada pra
     * dentro quando não cabe, e nunca mais larga que a tela menos 16px.
     */
    const [posicao, setPosicao] = useState<{ top: number; right: number; width: number } | null>(null)

    useEffect(() => {
        if (!open) return
        const calcular = () => {
            const r = botaoRef.current?.getBoundingClientRect()
            if (!r) return
            const margem = 8
            // clientWidth e não innerWidth: a barra de cima (onde a janela mora) não
            // inclui a barra de rolagem da página.
            const larguraTela = document.documentElement.clientWidth
            const largura = Math.min(360, larguraTela - margem * 2)
            // Direita da janela alinhada à direita do sino; se isso jogar a
            // esquerda pra fora, puxa pra dentro.
            let right = Math.max(margem, larguraTela - r.right)
            if (larguraTela - right - largura < margem) right = larguraTela - largura - margem
            setPosicao({ top: r.bottom + 8, right, width: largura })
        }
        calcular()
        window.addEventListener('resize', calcular)
        return () => window.removeEventListener('resize', calcular)
    }, [open])
    const router = useRouter()
    const {
        notifications,
        loading,
        unreadCount,
        markAsRead,
        markAllAsRead,
    } = useNotifications()

    // Close on click outside
    useEffect(() => {
        const handleClickOutside = (event: MouseEvent) => {
            if (
                dropdownRef.current &&
                !dropdownRef.current.contains(event.target as Node)
            ) {
                setOpen(false)
            }
        }
        document.addEventListener('mousedown', handleClickOutside)
        return () => document.removeEventListener('mousedown', handleClickOutside)
    }, [])

    const handleClickNotification = (notification: Notification) => {
        if (!notification.is_read) {
            markAsRead(notification.id)
        }
        if (notification.link_url) {
            // Marca de abertura: clicar na mesma notificação duas vezes precisa
            // reabrir a conversa, e sem isso o endereço seria o mesmo de antes.
            router.push(comMarcaDeAbertura(notification.link_url))
            setOpen(false)
        }
    }

    const handleMarkAllAsRead = (e: React.MouseEvent) => {
        e.stopPropagation()
        markAllAsRead()
    }

    return (
        <div className="relative" ref={dropdownRef}>
            {/* Bell button */}
            <button
                ref={botaoRef}
                onClick={() => setOpen(!open)}
                className="relative p-2 text-gray-500 hover:text-gray-700 hover:bg-gray-100 rounded-lg transition-colors"
            >
                <Bell size={20} />
                {unreadCount > 0 && (
                    <span className="absolute -top-0.5 -right-0.5 flex items-center justify-center min-w-[18px] h-[18px] px-1 text-[10px] font-bold text-white bg-red-500 rounded-full leading-none">
                        {unreadCount > 9 ? '9+' : unreadCount}
                    </span>
                )}
            </button>

            {/* Dropdown */}
            {/* Fundo preto e cores fixas, iguais em tema claro e escuro: antes o
                fundo era branco e o texto seguia o tema — no escuro, texto claro
                em fundo claro, ilegível. */}
            {open && posicao && (
                <div
                    className="fixed bg-[#0a0a0a] border border-white/10 rounded-xl shadow-2xl shadow-black/60 z-50 animate-in fade-in slide-in-from-top-2 overflow-hidden"
                    style={{ top: posicao.top, right: posicao.right, width: posicao.width }}
                >
                    {/* Header */}
                    <div className="flex items-center justify-between px-4 py-3 border-b border-white/10">
                        <h3 className="text-sm font-semibold text-[#f4f4f5]">Notificações</h3>
                        {unreadCount > 0 && (
                            <button
                                onClick={handleMarkAllAsRead}
                                className="text-xs font-semibold text-[#60a5fa] hover:text-[#93c5fd] transition-colors uppercase tracking-wide"
                            >
                                Marcar lidas
                            </button>
                        )}
                    </div>

                    {/* Notification list */}
                    <div className="max-h-[min(340px,calc(100dvh-140px))] overflow-y-auto overscroll-contain">
                        {loading ? (
                            <div className="flex items-center justify-center py-8">
                                <div className="w-5 h-5 border-2 border-white/15 border-t-[#3b82f6] rounded-full animate-spin" />
                            </div>
                        ) : notifications.length === 0 ? (
                            <div className="flex flex-col items-center justify-center py-10 text-[#71717a] gap-2">
                                <BellSlash size={32} weight="light" />
                                <p className="text-sm">Nenhuma notificação</p>
                            </div>
                        ) : (
                            <div className="divide-y divide-white/[0.06]">
                                {notifications.map((notification) => (
                                    <NotificationItem
                                        key={notification.id}
                                        notification={notification}
                                        onClickNotification={handleClickNotification}
                                    />
                                ))}
                            </div>
                        )}
                    </div>

                    {/* Footer */}
                    {notifications.length > 0 && (
                        <div className="border-t border-white/10 px-4 py-2.5">
                            <button
                                onClick={() => {
                                    setOpen(false)
                                    router.push('/notifications')
                                }}
                                className="w-full text-center text-xs font-medium text-[#60a5fa] hover:text-[#93c5fd] transition-colors"
                            >
                                Ver todas as notificações
                            </button>
                        </div>
                    )}
                </div>
            )}
        </div>
    )
}
