'use client'

import { useState, useMemo } from 'react'
import { useRouter } from 'next/navigation'
import {
    ArrowLeft,
    MagnifyingGlass,
    ChatCircleDots,
    UserPlus,
    CalendarBlank,
    ChartBar,
    Notebook,
    CheckCircle,
    BellSlash,
    Bell,
    Circle,
    Warning,
    Info,
    Headset,
} from '@phosphor-icons/react'
import { useNotifications } from '@/hooks/useNotifications'
import { Notification } from '@/lib/types'

/* ─── Helpers ─── */

function formatRelativeTime(dateString: string): string {
    const now = new Date()
    const date = new Date(dateString)
    const diffMs = now.getTime() - date.getTime()
    const diffSec = Math.floor(diffMs / 1000)
    const diffMin = Math.floor(diffSec / 60)
    const diffHour = Math.floor(diffMin / 60)
    const diffDay = Math.floor(diffHour / 24)

    if (diffSec < 60) return 'AGORA'
    if (diffMin < 60) return `${diffMin} MIN`
    if (diffHour < 24) return `${diffHour}H`
    if (diffDay === 1) return 'ONTEM'
    if (diffDay < 7) {
        const dayNames = ['DOMINGO', 'SEGUNDA', 'TERÇA', 'QUARTA', 'QUINTA', 'SEXTA', 'SÁBADO']
        return dayNames[date.getDay()]
    }
    return date.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' })
}

type TimeGroup = 'Hoje' | 'Ontem' | 'Esta semana' | 'Mais antigas'

function getTimeGroup(dateString: string): TimeGroup {
    const now = new Date()
    const date = new Date(dateString)
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const yesterdayStart = new Date(todayStart.getTime() - 86400000)
    const weekStart = new Date(todayStart.getTime() - todayStart.getDay() * 86400000)

    if (date >= todayStart) return 'Hoje'
    if (date >= yesterdayStart) return 'Ontem'
    if (date >= weekStart) return 'Esta semana'
    return 'Mais antigas'
}

function groupNotifications(notifications: Notification[]): Record<TimeGroup, Notification[]> {
    const groups: Record<TimeGroup, Notification[]> = {
        'Hoje': [],
        'Ontem': [],
        'Esta semana': [],
        'Mais antigas': [],
    }
    for (const n of notifications) {
        groups[getTimeGroup(n.created_at)].push(n)
    }
    return groups
}

/* ─── Icon by type ─── */

const typeConfig: Record<string, { icon: React.ElementType; color: string; bg: string; actionColor: string }> = {
    message: { icon: ChatCircleDots, color: 'text-accent-2', bg: 'bg-panel-2', actionColor: 'bg-accent hover:bg-accent-2 text-white' },
    success: { icon: CheckCircle, color: 'text-emerald-600', bg: 'bg-emerald-50', actionColor: 'bg-emerald-600 hover:bg-emerald-700 text-white' },
    warning: { icon: Warning, color: 'text-amber-600', bg: 'bg-amber-50', actionColor: 'bg-amber-600 hover:bg-amber-700 text-white' },
    error: { icon: Warning, color: 'text-red-600', bg: 'bg-red-50', actionColor: 'bg-red-600 hover:bg-red-700 text-white' },
    info: { icon: Info, color: 'text-indigo-600', bg: 'bg-indigo-50', actionColor: 'bg-indigo-600 hover:bg-indigo-700 text-white' },
    lead: { icon: UserPlus, color: 'text-cyan-600', bg: 'bg-cyan-50', actionColor: 'bg-cyan-700 hover:bg-cyan-800 text-white' },
    meeting: { icon: CalendarBlank, color: 'text-violet-600', bg: 'bg-violet-50', actionColor: 'text-violet-700 border border-violet-200 hover:bg-violet-50' },
    report: { icon: ChartBar, color: 'text-teal-600', bg: 'bg-teal-50', actionColor: 'bg-teal-600 hover:bg-teal-700 text-white' },
    note: { icon: Notebook, color: 'text-muted', bg: 'bg-panel-2', actionColor: 'text-muted border border-line hover:bg-void' },
    support: { icon: Headset, color: 'text-purple-600', bg: 'bg-purple-50', actionColor: 'bg-purple-600 hover:bg-purple-700 text-white' },
}

const defaultConfig = { icon: Bell, color: 'text-muted', bg: 'bg-panel-2', actionColor: 'text-muted border border-line hover:bg-void' }

function getConfig(type?: string) {
    return typeConfig[type || ''] || defaultConfig
}

/* ─── Notification Item ─── */

function NotificationPageItem({
    notification,
    onMark,
}: {
    notification: Notification
    onMark: (id: string) => void
}) {
    const config = getConfig(notification.type || undefined)
    const Icon = config.icon
    const router = useRouter()

    const handleAction = () => {
        if (!notification.is_read) onMark(notification.id)
        if (notification.link_url) router.push(notification.link_url)
    }

    // Derive action text from notification type
    const actionText = notification.link_url
        ? getActionLabel(notification.type)
        : null

    return (
        <div
            className={`flex items-start gap-4 px-6 py-4 transition-colors cursor-pointer hover:bg-void ${!notification.is_read ? 'bg-panel-2' : ''}`}
            onClick={() => { if (!notification.is_read) onMark(notification.id) }}
        >
            {/* Icon */}
            <div className={`shrink-0 w-10 h-10 rounded-xl flex items-center justify-center ${config.bg}`}>
                <Icon size={20} weight="duotone" className={config.color} />
            </div>

            {/* Content */}
            <div className="flex-1 min-w-0">
                <p className="text-sm leading-snug">
                    <span className="font-semibold text-ink">{notification.title || 'Notificação'}</span>
                </p>
                {notification.content && (
                    <p className="text-sm text-muted mt-0.5 line-clamp-2">{notification.content}</p>
                )}
                {actionText && (
                    <button
                        onClick={(e) => { e.stopPropagation(); handleAction() }}
                        className={`mt-2 inline-flex items-center px-3 py-1 rounded-md text-xs font-semibold transition-colors ${config.actionColor}`}
                    >
                        {actionText}
                    </button>
                )}
            </div>

            {/* Time + unread dot */}
            <div className="shrink-0 flex flex-col items-end gap-1.5 pt-0.5">
                <span className="text-[11px] font-medium text-muted tracking-wide uppercase">
                    {formatRelativeTime(notification.created_at)}
                </span>
                {!notification.is_read && (
                    <div className="w-2 h-2 rounded-full bg-accent" />
                )}
            </div>
        </div>
    )
}

function getActionLabel(type?: string): string {
    switch (type) {
        case 'message': return 'Visualizar Chat'
        case 'support': return 'Assumir Chat'
        case 'lead': return 'Ligar Agora'
        case 'meeting': return 'Ver Agenda'
        case 'report': return 'Ver Relatório'
        case 'note': return 'Registrar'
        case 'success': return 'Comemorar'
        default: return 'Ver chat'
    }
}

/* ─── Page ─── */

export default function NotificationsPage() {
    const router = useRouter()
    const { notifications, loading, unreadCount, markAsRead, markAllAsRead } = useNotifications(50)
    const [search, setSearch] = useState('')
    const [tab, setTab] = useState<'all' | 'unread'>('all')

    // Filter + search
    const filtered = useMemo(() => {
        let list = notifications
        if (tab === 'unread') list = list.filter((n) => !n.is_read)
        if (search.trim()) {
            const q = search.toLowerCase()
            list = list.filter(
                (n) =>
                    (n.title || '').toLowerCase().includes(q) ||
                    (n.content || '').toLowerCase().includes(q)
            )
        }
        return list
    }, [notifications, tab, search])

    const groups = useMemo(() => groupNotifications(filtered), [filtered])
    const groupOrder: TimeGroup[] = ['Hoje', 'Ontem', 'Esta semana', 'Mais antigas']

    return (
        <div className="h-full bg-panel">
            {/* Sticky Header */}
            <div className="sticky top-0 z-10 bg-panel border-b border-line">
                {/* Top bar */}
                <div className="flex items-center justify-between px-6 py-4">
                    <div className="flex items-center gap-3">
                        <button
                            onClick={() => router.back()}
                            className="p-1.5 rounded-lg text-muted hover:text-ink hover:bg-panel-2 transition-colors"
                        >
                            <ArrowLeft size={20} weight="bold" />
                        </button>
                        <h1 className="text-lg font-bold text-ink">Notificações</h1>
                        {unreadCount > 0 && (
                            <span className="inline-flex items-center justify-center min-w-[22px] h-[22px] px-1.5 text-[11px] font-bold text-white bg-red-500 rounded-full">
                                {unreadCount > 99 ? '99+' : unreadCount}
                            </span>
                        )}
                    </div>
                    {unreadCount > 0 && (
                        <button
                            onClick={() => markAllAsRead()}
                            className="text-xs font-semibold text-accent-2 hover:text-accent-2 transition-colors uppercase tracking-wide flex items-center gap-1.5"
                        >
                            <CheckCircle size={14} weight="bold" />
                            Marcar todas como lidas
                        </button>
                    )}
                </div>

                {/* Search */}
                <div className="px-6 pb-3">
                    <div className="relative">
                        <MagnifyingGlass
                            size={16}
                            className="absolute left-3 top-1/2 -translate-y-1/2 text-muted"
                        />
                        <input
                            type="text"
                            placeholder="Buscar nas notificações..."
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                            className="w-full pl-9 pr-4 py-2.5 text-sm bg-void border border-line rounded-xl focus:outline-none focus:ring-2 focus:ring-accent focus:border-accent transition-all placeholder:text-muted"
                        />
                    </div>
                </div>

                {/* Tabs */}
                <div className="px-6 pb-0">
                    <div className="flex border-b border-line">
                        <button
                            onClick={() => setTab('all')}
                            className={`flex-1 text-center py-2.5 text-sm font-semibold transition-colors border-b-2 ${tab === 'all'
                                ? 'text-ink border-line'
                                : 'text-muted border-transparent hover:text-muted'
                                }`}
                        >
                            Todas
                        </button>
                        <button
                            onClick={() => setTab('unread')}
                            className={`flex-1 text-center py-2.5 text-sm font-semibold transition-colors border-b-2 ${tab === 'unread'
                                ? 'text-accent-2 border-accent'
                                : 'text-muted border-transparent hover:text-muted'
                                }`}
                        >
                            Não lidas
                            {unreadCount > 0 && (
                                <span className="ml-1.5 inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 text-[10px] font-bold text-accent-2 bg-panel-2 rounded-full">
                                    {unreadCount}
                                </span>
                            )}
                        </button>
                    </div>
                </div>
            </div>

            {/* Notification List */}
            <div className="overflow-y-auto pb-16" style={{ maxHeight: 'calc(100vh - 220px)' }}>
                {loading ? (
                    <div className="flex items-center justify-center py-20">
                        <div className="w-6 h-6 border-2 border-line border-t-blue-500 rounded-full animate-spin" />
                    </div>
                ) : filtered.length === 0 ? (
                    <div className="flex flex-col items-center justify-center py-20 text-muted gap-3">
                        <BellSlash size={48} weight="light" />
                        <p className="text-sm font-medium">
                            {tab === 'unread' ? 'Nenhuma notificação não lida' : 'Nenhuma notificação'}
                        </p>
                        {search && (
                            <p className="text-xs text-muted">
                                Nenhum resultado para &quot;{search}&quot;
                            </p>
                        )}
                    </div>
                ) : (
                    groupOrder.map((group) => {
                        const items = groups[group]
                        if (items.length === 0) return null
                        return (
                            <div key={group}>
                                <div className="sticky top-0 z-[5] bg-void backdrop-blur-sm px-6 py-2 border-b border-line">
                                    <span className="text-xs font-bold text-muted uppercase tracking-wider">
                                        {group}
                                    </span>
                                </div>
                                <div className="divide-y divide-line">
                                    {items.map((notification) => (
                                        <NotificationPageItem
                                            key={notification.id}
                                            notification={notification}
                                            onMark={markAsRead}
                                        />
                                    ))}
                                </div>
                            </div>
                        )
                    })
                )}
            </div>
        </div>
    )
}
