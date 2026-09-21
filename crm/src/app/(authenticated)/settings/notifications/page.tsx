'use client'

import { useState, useCallback, useEffect } from 'react'
import {
    Bell,
    ChatCircleDots,
    Lightning,
    Trash,
    Copy,
    Check,
    Plus,
    EnvelopeSimple,
    Megaphone,
    Warning,
    Bug,
    ShieldCheck,
    Star,
    Heart,
    CurrencyDollar,
    CalendarBlank,
    Play,
    DeviceMobile,
    ShareFat,
} from '@phosphor-icons/react'
import { useNotification } from '@/contexts/NotificationContext'
import { useApiNotifications, ApiNotificationEvent } from '@/hooks/useApiNotifications'
import { usePushNotifications } from '@/hooks/usePushNotifications'

/* ─── Types ─── */

const AVAILABLE_ICONS: Record<string, React.ElementType> = {
    Lightning,
    Bell,
    ChatCircleDots,
    EnvelopeSimple,
    Megaphone,
    Warning,
    Bug,
    ShieldCheck,
    Star,
    Heart,
    CurrencyDollar,
    CalendarBlank,
}

interface SystemNotification {
    id: string
    label: string
    description: string
    enabled: boolean
}

const ALERT_COLORS = [
    { name: 'Vermelho', value: '#EF4444' },
    { name: 'Laranja', value: '#F97316' },
    { name: 'Azul', value: '#3B82F6' },
    { name: 'Verde', value: '#22C55E' },
    { name: 'Roxo', value: '#A855F7' },
]

function generateEventId(): string {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    let result = 'evt_'
    for (let i = 0; i < 10; i++) result += chars[Math.floor(Math.random() * chars.length)]
    return result
}

/* ─── Toggle Component ─── */

function Toggle({ enabled, onChange }: { enabled: boolean; onChange: (v: boolean) => void }) {
    return (
        <button
            type="button"
            onClick={() => onChange(!enabled)}
            className={`relative inline-flex h-6 w-11 shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none ${enabled ? 'bg-accent' : 'bg-panel-2'
                }`}
        >
            <span
                className={`pointer-events-none inline-block h-5 w-5 transform rounded-full bg-panel shadow-lg ring-0 transition duration-200 ease-in-out ${enabled ? 'translate-x-5' : 'translate-x-0'
                    }`}
            />
        </button>
    )
}

/* ─── Copy ID Component ─── */

function CopyableId({ value }: { value: string }) {
    const [copied, setCopied] = useState(false)

    const handleCopy = () => {
        navigator.clipboard.writeText(value)
        setCopied(true)
        setTimeout(() => setCopied(false), 2000)
    }

    return (
        <div className="flex items-center gap-2">
            <div className="flex-1 px-3 py-2 bg-void border border-line rounded-lg text-sm text-muted font-mono tracking-wide">
                {value}
            </div>
            <button
                onClick={handleCopy}
                className="p-2 text-muted hover:text-muted hover:bg-panel-2 rounded-lg transition-colors"
                title="Copiar ID"
            >
                {copied ? <Check size={16} weight="bold" className="text-green-500" /> : <Copy size={16} />}
            </button>
        </div>
    )
}

/* ─── API Notification Card ─── */

function ApiNotificationCard({
    notification,
    onToggle,
    onColorChange,
    onNameChange,
    onDescriptionChange,
    onIconChange,
    onDelete,
    onTest,
}: {
    notification: ApiNotificationEvent
    onToggle: () => void
    onColorChange: (color: string) => void
    onNameChange: (name: string) => void
    onDescriptionChange: (desc: string) => void
    onIconChange: (iconName: string) => void
    onDelete: () => void
    onTest: () => void
}) {
    const Icon = AVAILABLE_ICONS[notification.iconName] || Lightning

    return (
        <div className={`bg-panel border rounded-2xl shadow-sm transition-all ${notification.enabled ? 'border-line' : 'border-line opacity-75'}`}>
            <div className="px-5 py-4 flex items-center justify-between">
                <div className="flex items-center gap-3">
                    <div
                        className="w-9 h-9 rounded-xl flex items-center justify-center"
                        style={{ backgroundColor: notification.color + '18' }}
                    >
                        <Icon size={18} weight="duotone" style={{ color: notification.color }} />
                    </div>
                    <span className="text-sm font-semibold text-ink">{notification.label}</span>
                </div>
                <Toggle enabled={notification.enabled} onChange={onToggle} />
            </div>

            {notification.enabled && (
                <div className="px-5 pb-5 space-y-4 border-t border-line pt-4">
                    {/* Name Input */}
                    <div>
                        <label className="block text-[11px] font-bold text-muted uppercase tracking-wider mb-2">
                            Nome da Notificação
                        </label>
                        <input
                            type="text"
                            value={notification.label}
                            onChange={(e) => onNameChange(e.target.value)}
                            className="block w-full px-3 py-2 text-sm bg-panel border border-line rounded-lg focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-colors"
                        />
                    </div>

                    {/* Description Input */}
                    <div>
                        <label className="block text-[11px] font-bold text-muted uppercase tracking-wider mb-2">
                            Descrição (Opcional)
                        </label>
                        <input
                            type="text"
                            value={notification.description || ''}
                            onChange={(e) => onDescriptionChange(e.target.value)}
                            placeholder="Ex: Um novo negócio foi fechado na sua equipe"
                            className="block w-full px-3 py-2 text-sm bg-panel border border-line rounded-lg focus:outline-none focus:border-accent focus:ring-1 focus:ring-accent transition-colors"
                        />
                    </div>

                    {/* Icon picker */}
                    <div>
                        <label className="block text-[11px] font-bold text-muted uppercase tracking-wider mb-2.5">
                            Ícone
                        </label>
                        <div className="flex flex-wrap items-center gap-1.5">
                            {Object.entries(AVAILABLE_ICONS).map(([iconName, IconOption]) => (
                                <button
                                    key={iconName}
                                    onClick={() => onIconChange(iconName)}
                                    className={`w-9 h-9 rounded-xl flex items-center justify-center transition-all ${notification.iconName === iconName
                                        ? 'bg-panel-2 ring-2 ring-line'
                                        : 'hover:bg-void'
                                        }`}
                                    title="Selecionar ícone"
                                >
                                    <IconOption size={18} weight={notification.iconName === iconName ? "fill" : "duotone"} className={notification.iconName === iconName ? "text-ink" : "text-muted"} />
                                </button>
                            ))}
                        </div>
                    </div>

                    {/* Color picker */}
                    <div>
                        <label className="block text-[11px] font-bold text-muted uppercase tracking-wider mb-2.5">
                            Cor do alerta
                        </label>
                        <div className="flex items-center gap-2.5">
                            {ALERT_COLORS.map((c) => (
                                <button
                                    key={c.value}
                                    onClick={() => onColorChange(c.value)}
                                    className={`w-8 h-8 rounded-full transition-all ${notification.color === c.value
                                        ? 'ring-2 ring-offset-2 scale-110'
                                        : 'hover:scale-105'
                                        }`}
                                    style={{
                                        backgroundColor: c.value,
                                        ...(notification.color === c.value ? { ['--tw-ring-color' as string]: c.value } : {}),
                                    }}
                                    title={c.name}
                                />
                            ))}
                        </div>
                    </div>

                    {/* Event ID */}
                    <div>
                        <label className="block text-[11px] font-bold text-muted uppercase tracking-wider mb-2">
                            ID da notificação
                        </label>
                        <CopyableId value={notification.eventId} />
                    </div>

                    {/* Actions */}
                    <div className="flex justify-between items-center pt-2">
                        <button
                            onClick={onTest}
                            className="flex items-center gap-1.5 text-xs font-semibold text-accent-2 hover:text-accent-2 hover:bg-panel-2 px-3 py-1.5 rounded-lg transition-colors uppercase tracking-wide"
                        >
                            <Play size={14} weight="fill" />
                            Testar
                        </button>
                        <button
                            onClick={onDelete}
                            className="flex items-center gap-1.5 text-xs font-semibold text-muted hover:text-red-500 hover:bg-red-50 px-3 py-1.5 rounded-lg transition-colors uppercase tracking-wide"
                        >
                            <Trash size={14} />
                            Excluir
                        </button>
                    </div>
                </div>
            )}
        </div>
    )
}

/* ─── Push Notifications Card ─── */

function PushNotificationsCard() {
    const { status, subscribe, unsubscribe } = usePushNotifications()

    return (
        <div className="bg-panel border border-line rounded-2xl shadow-sm">
            <div className="px-5 py-4 flex items-center gap-2.5 border-b border-line">
                <DeviceMobile size={18} weight="duotone" className="text-muted" />
                <span className="text-xs font-bold text-muted uppercase tracking-wider">
                    Notificações no Celular
                </span>
            </div>
            <div className="px-5 py-4">
                {status === 'ios-not-installed' ? (
                    <div>
                        <p className="text-sm font-semibold text-ink">Instale o app pra receber notificações</p>
                        <p className="text-xs text-muted mt-1 flex items-center gap-1 flex-wrap">
                            No iPhone, o Safari só manda notificação push pra apps adicionados à tela de início. Toque em{' '}
                            <ShareFat size={14} weight="bold" className="text-accent-2" /> Compartilhar e depois em
                            &quot;Adicionar à Tela de Início&quot;, e volte aqui.
                        </p>
                    </div>
                ) : status === 'unsupported' ? (
                    <p className="text-sm text-muted">Seu navegador não é compatível com notificações push.</p>
                ) : status === 'denied' ? (
                    <p className="text-sm text-muted">
                        As notificações estão bloqueadas pro TitaCRM neste navegador. Ative de novo nas
                        configurações de site do seu navegador/celular pra poder ligar aqui.
                    </p>
                ) : (
                    <div className="flex items-center justify-between">
                        <div>
                            <p className="text-sm font-semibold text-ink">Ativar notificações</p>
                            <p className="text-xs text-muted mt-0.5">
                                Saiba na hora quando chegar uma mensagem nova, mesmo com o app fechado.
                            </p>
                        </div>
                        <Toggle
                            enabled={status === 'subscribed'}
                            onChange={(v) => (v ? subscribe() : unsubscribe())}
                        />
                    </div>
                )}
            </div>
        </div>
    )
}

/* ─── Page ─── */

export default function NotificationSettingsPage() {
    const { addNotification } = useNotification()
    const { events: apiNotifications, loading, saveEvents } = useApiNotifications()

    // Temporary list just for system notifications while they are not dynamic
    const [systemNotifications, setSystemNotifications] = useState<SystemNotification[]>([
        {
            id: 'new_leads',
            label: 'Novos leads atribuídos',
            description: 'Avisar sempre que um novo lead for designado a você.',
            enabled: true,
        },
        {
            id: 'pipeline_changes',
            label: 'Mudanças no pipeline',
            description: 'Alertas quando cards de negócios mudarem de etapa.',
            enabled: true,
        },
    ])

    const toggleSystem = useCallback((id: string) => {
        setSystemNotifications((prev) =>
            prev.map((n) => (n.id === id ? { ...n, enabled: !n.enabled } : n))
        )
    }, [])

    const toggleApi = useCallback((id: string) => {
        saveEvents(
            apiNotifications.map((n) => (n.id === id ? { ...n, enabled: !n.enabled } : n))
        )
    }, [apiNotifications, saveEvents])

    const changeApiColor = useCallback((id: string, color: string) => {
        saveEvents(
            apiNotifications.map((n) => (n.id === id ? { ...n, color } : n))
        )
    }, [apiNotifications, saveEvents])

    const changeApiName = useCallback((id: string, label: string) => {
        saveEvents(
            apiNotifications.map((n) => (n.id === id ? { ...n, label } : n))
        )
    }, [apiNotifications, saveEvents])

    const changeApiDescription = useCallback((id: string, description: string) => {
        saveEvents(
            apiNotifications.map((n) => (n.id === id ? { ...n, description } : n))
        )
    }, [apiNotifications, saveEvents])

    const changeApiIcon = useCallback((id: string, iconName: string) => {
        saveEvents(
            apiNotifications.map((n) => (n.id === id ? { ...n, iconName } : n))
        )
    }, [apiNotifications, saveEvents])

    const deleteApi = useCallback((id: string) => {
        saveEvents(apiNotifications.filter((n) => n.id !== id))
    }, [apiNotifications, saveEvents])

    const testApiNotification = useCallback((notification: ApiNotificationEvent) => {
        addNotification({
            type: 'info',
            title: notification.label,
            message: notification.description
                ? notification.description
                : `Este é um teste da notificação via evento ${notification.eventId}`,
            customColor: notification.color,
            customIcon: AVAILABLE_ICONS[notification.iconName] || Lightning,
            skipPersist: true,
            actionText: 'Ver chat',
            linkUrl: '/chat',
        })
    }, [addNotification])

    const createApiNotification = useCallback(() => {
        const newId = Date.now().toString()
        saveEvents([
            ...apiNotifications,
            {
                id: newId,
                eventId: generateEventId(),
                label: 'Nova Notificação',
                description: '',
                iconName: 'Lightning',
                enabled: true,
                color: '#3B82F6',
            },
        ])
    }, [apiNotifications, saveEvents])

    return (
        <div className="max-w-3xl mx-auto space-y-8">
            {/* Breadcrumb */}
            <div>
                <p className="text-[11px] font-bold text-muted uppercase tracking-wider mb-1">
                    Configurações &gt; Notificações
                </p>
                <h1 className="text-2xl font-bold text-ink">
                    Configurações de Notificações
                </h1>
                <p className="text-sm text-muted mt-1">
                    Gerencie como e quando você deseja receber alertas do CRM.
                </p>
            </div>

            {/* Push Notifications */}
            <PushNotificationsCard />

            {/* System Notifications */}
            <div className="bg-panel border border-line rounded-2xl shadow-sm">
                <div className="px-5 py-4 flex items-center gap-2.5 border-b border-line">
                    <ChatCircleDots size={18} weight="duotone" className="text-muted" />
                    <span className="text-xs font-bold text-muted uppercase tracking-wider">
                        Notificações do Sistema
                    </span>
                </div>
                <div className="divide-y divide-line">
                    {systemNotifications.map((item) => (
                        <div key={item.id} className="px-5 py-4 flex items-center justify-between">
                            <div>
                                <p className="text-sm font-semibold text-ink">{item.label}</p>
                                <p className="text-xs text-muted mt-0.5">{item.description}</p>
                            </div>
                            <Toggle enabled={item.enabled} onChange={() => toggleSystem(item.id)} />
                        </div>
                    ))}
                </div>
            </div>

            {/* API Notifications */}
            <div className="space-y-4">
                <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2.5">
                        <Lightning size={18} weight="duotone" className="text-muted" />
                        <span className="text-xs font-bold text-muted uppercase tracking-wider">
                            Notificações via API
                        </span>
                    </div>
                    <button
                        onClick={createApiNotification}
                        className="px-4 py-2 bg-accent hover:bg-accent-2 text-white text-sm font-semibold rounded-lg transition-colors shadow-sm flex items-center gap-2"
                    >
                        <Plus size={16} weight="bold" />
                        Criar nova notificação
                    </button>
                </div>
                <p className="text-sm text-muted -mt-2">
                    Configure eventos que serão disparados via API externa para notificar sua equipe.
                </p>

                <div className="space-y-3">
                    {apiNotifications.map((notification) => (
                        <ApiNotificationCard
                            key={notification.id}
                            notification={notification}
                            onToggle={() => toggleApi(notification.id)}
                            onColorChange={(color) => changeApiColor(notification.id, color)}
                            onNameChange={(name) => changeApiName(notification.id, name)}
                            onDescriptionChange={(desc) => changeApiDescription(notification.id, desc)}
                            onIconChange={(icon) => changeApiIcon(notification.id, icon)}
                            onDelete={() => deleteApi(notification.id)}
                            onTest={() => testApiNotification(notification)}
                        />
                    ))}

                    {apiNotifications.length === 0 && (
                        <div className="text-center py-12 bg-panel rounded-2xl border border-line shadow-sm">
                            <div className="w-12 h-12 bg-void rounded-full flex items-center justify-center mx-auto mb-3">
                                <Bell size={24} className="text-muted" />
                            </div>
                            <h3 className="text-sm font-medium text-ink mb-1">
                                Nenhuma notificação via API
                            </h3>
                            <p className="text-sm text-muted max-w-sm mx-auto">
                                Configure eventos que serão disparados via API externa para notificar sua equipe.
                            </p>
                        </div>
                    )}
                </div>
            </div>
        </div>
    )
}
