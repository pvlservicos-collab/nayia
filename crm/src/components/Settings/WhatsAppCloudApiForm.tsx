'use client'

import { Eye, EyeClosed, WhatsappLogo, CheckCircle, Info, Lightning, ShieldCheck, Copy, Check, CaretDown, CaretUp } from '@phosphor-icons/react'
import { useState, useEffect } from 'react'
import { useAuth } from '@/hooks'
import FieldTooltip from '@/components/Shared/FieldTooltip'

type ConnectionState = 'loading' | 'connected' | 'disconnected'

interface WhatsAppCloudApiFormProps {
    onConnected?: () => void
    compact?: boolean
}

function CopyField({ label, value, tooltip }: { label: string; value: string; tooltip: string }) {
    const [copied, setCopied] = useState(false)
    const handleCopy = () => {
        navigator.clipboard.writeText(value)
        setCopied(true)
        setTimeout(() => setCopied(false), 2000)
    }
    return (
        <div>
            <div className="flex items-center justify-between mb-2">
                <label className="block text-sm font-semibold text-ink">{label}</label>
                <FieldTooltip text={tooltip} />
            </div>
            <div className="flex items-center gap-2">
                <div className="flex-1 px-3 py-2.5 bg-void border border-line rounded-lg text-sm text-muted font-mono truncate">
                    {value}
                </div>
                <button
                    type="button"
                    onClick={handleCopy}
                    className="flex items-center gap-1.5 px-3 py-2.5 text-sm font-medium text-muted hover:text-ink hover:bg-panel-2 border border-line rounded-lg transition-colors flex-shrink-0"
                    title="Copiar"
                >
                    {copied ? <Check size={16} weight="bold" className="text-emerald-400" /> : <Copy size={16} />}
                    {copied ? 'Copiado' : 'Copie'}
                </button>
            </div>
        </div>
    )
}

const DATA_SOURCES = [
    { question: 'WABA ID', answer: 'Meta Business Suite → Configurações → Contas do WhatsApp → selecione sua conta → copie o "ID da conta".' },
    { question: 'Phone Number ID', answer: 'No App da Meta → WhatsApp → Configuração da API → aparece ao lado do seu número comercial.' },
    { question: 'System User Token', answer: 'Configurações do Negócio → Usuários → Usuários do sistema → Adicionar → gere um token com acesso ao WhatsApp, expiração "Nunca".' },
    { question: 'URL de Webhook', answer: 'Já gerada aqui embaixo — cole no seu App da Meta em Webhooks → Editar assinatura → Retorno de chamada.' },
    { question: 'Verify Token', answer: 'Já gerado aqui embaixo — cole no mesmo lugar, em "Verificar token".' },
]

export default function WhatsAppCloudApiForm({ onConnected, compact = false }: WhatsAppCloudApiFormProps) {
    const { organizationId } = useAuth()

    const [wabaId, setWabaId] = useState('')
    const [phoneNumberId, setPhoneNumberId] = useState('')
    const [systemToken, setSystemToken] = useState('')
    const [graphApiVersion, setGraphApiVersion] = useState('v21.0')

    const [showToken, setShowToken] = useState(false)
    const [connectionState, setConnectionState] = useState<ConnectionState>('loading')
    const [isSaving, setIsSaving] = useState(false)
    const [saveError, setSaveError] = useState<string | null>(null)
    const [saveSuccess, setSaveSuccess] = useState(false)
    const [showDataSources, setShowDataSources] = useState(false)
    const [origin, setOrigin] = useState('')
    const [verifyToken, setVerifyToken] = useState('')

    useEffect(() => {
        if (typeof window !== 'undefined') setOrigin(window.location.origin)
        fetch('/api/integrations/whatsapp-cloud/verify-token')
            .then((res) => res.json())
            .then((data) => setVerifyToken(data?.verify_token || ''))
            .catch(() => {})
    }, [])

    useEffect(() => {
        if (!organizationId) return
        let cancelled = false

        const load = async () => {
            setConnectionState('loading')
            try {
                const res = await fetch(`/api/integrations/whatsapp-cloud?organization_id=${organizationId}`)
                const data = await res.json()
                if (cancelled) return

                if (data && data.config) {
                    setWabaId(data.config.waba_id ?? '')
                    setPhoneNumberId(data.config.phone_number_id ?? '')
                    setGraphApiVersion(data.config.graph_api_version ?? 'v21.0')
                    setConnectionState(data.status === 'active' ? 'connected' : 'disconnected')
                } else {
                    setConnectionState('disconnected')
                }
            } catch (err) {
                console.error('Failed to load WhatsApp Cloud integration', err)
                if (!cancelled) setConnectionState('disconnected')
            }
        }

        load()
        return () => { cancelled = true }
    }, [organizationId])

    const handleSubmit = async (e: React.FormEvent) => {
        e.preventDefault()
        if (!organizationId) return

        setIsSaving(true)
        setSaveError(null)
        setSaveSuccess(false)

        try {
            const res = await fetch('/api/integrations/whatsapp-cloud', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    organization_id: organizationId,
                    waba_id: wabaId.trim(),
                    phone_number_id: phoneNumberId.trim(),
                    system_token: systemToken,
                    graph_api_version: graphApiVersion.trim() || 'v21.0',
                }),
            })

            const data = await res.json()
            if (!res.ok) {
                setSaveError(data?.error || 'Erro ao salvar integração')
            } else {
                setSaveSuccess(true)
                setConnectionState('connected')
                setSystemToken('') // limpa da memória depois de salvar
                onConnected?.()
            }
        } catch (err: any) {
            setSaveError(err?.message ?? 'Erro ao salvar integração')
        } finally {
            setIsSaving(false)
        }
    }

    const statusBadge = connectionState === 'connected' ? (
        <span className="flex items-center gap-1.5 text-emerald-400 bg-emerald-500/10 px-2.5 py-1 rounded-full">
            <div className="w-2 h-2 rounded-full bg-emerald-400"></div> Conectado
        </span>
    ) : connectionState === 'loading' ? (
        <span className="flex items-center gap-1.5 text-muted bg-panel-2 px-2.5 py-1 rounded-full">
            <div className="w-2 h-2 rounded-full bg-muted animate-pulse"></div> Verificando...
        </span>
    ) : (
        <span className="flex items-center gap-1.5 text-red-400 bg-red-500/10 px-2.5 py-1 rounded-full">
            <div className="w-2 h-2 rounded-full bg-red-400"></div> Não conectado
        </span>
    )

    const formDisabled = !organizationId || isSaving
    const webhookUrl = organizationId && origin ? `${origin}/api/webhooks/facebook?org_id=${organizationId}` : ''

    return (
        <div>
            <div className="flex items-center flex-wrap gap-3 justify-between mb-6">
                <div className="flex items-center gap-3">
                    <div className="w-10 h-10 rounded-full bg-emerald-500/10 flex items-center justify-center flex-shrink-0">
                        <WhatsappLogo size={22} weight="fill" className="text-emerald-400" />
                    </div>
                    <span className="font-bold text-ink">WhatsApp API Oficial</span>
                </div>
                {statusBadge}
            </div>

            <form onSubmit={handleSubmit} className="bg-panel border border-line rounded-xl p-6 sm:p-8">
                <div className="space-y-5">
                    <div>
                        <div className="flex items-center justify-between mb-2">
                            <label htmlFor="waba_id" className="block text-sm font-semibold text-ink">WABA ID</label>
                            <FieldTooltip text='Meta Business Suite → Configurações → Contas do WhatsApp → copie o "ID da conta".' />
                        </div>
                        <input
                            id="waba_id"
                            type="text"
                            value={wabaId}
                            onChange={(e) => setWabaId(e.target.value)}
                            placeholder="Ex: 10928374650123"
                            disabled={formDisabled}
                            className="w-full bg-panel-2 border border-line rounded-lg px-4 py-2.5 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent transition-all disabled:opacity-50"
                            required
                        />
                    </div>

                    <div>
                        <div className="flex items-center justify-between mb-2">
                            <label htmlFor="phone_number_id" className="block text-sm font-semibold text-ink">Phone Number ID</label>
                            <FieldTooltip text="No App da Meta → WhatsApp → Configuração da API, ao lado do seu número." />
                        </div>
                        <input
                            id="phone_number_id"
                            type="text"
                            value={phoneNumberId}
                            onChange={(e) => setPhoneNumberId(e.target.value)}
                            placeholder="Ex: 5523478901234567"
                            disabled={formDisabled}
                            className="w-full bg-panel-2 border border-line rounded-lg px-4 py-2.5 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent transition-all disabled:opacity-50"
                            required
                        />
                    </div>

                    <div>
                        <div className="flex items-center justify-between mb-2">
                            <label htmlFor="system_token" className="block text-sm font-semibold text-ink">System User Token</label>
                            <FieldTooltip text='Configurações do Negócio → Usuários do sistema → gere um token com acesso ao WhatsApp, expiração "Nunca".' />
                        </div>
                        <div className="relative">
                            <input
                                id="system_token"
                                type={showToken ? 'text' : 'password'}
                                value={systemToken}
                                onChange={(e) => setSystemToken(e.target.value)}
                                placeholder={connectionState === 'connected' ? '•••••••••••••• (deixe em branco pra manter o atual)' : 'EAAW...'}
                                disabled={formDisabled}
                                className="w-full bg-panel-2 border border-line rounded-lg px-4 py-2.5 text-sm text-ink placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent transition-all pr-10 disabled:opacity-50"
                                required={connectionState !== 'connected'}
                                autoComplete="new-password"
                            />
                            <button
                                type="button"
                                onClick={() => setShowToken(!showToken)}
                                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted hover:text-ink transition-colors"
                                tabIndex={-1}
                            >
                                {showToken ? <EyeClosed size={18} /> : <Eye size={18} />}
                            </button>
                        </div>
                        <p className="text-xs text-muted mt-1.5 flex items-center gap-1">
                            <ShieldCheck size={12} weight="fill" className="text-accent-2" />
                            Guardado no banco de dados da plataforma; nunca é reexibido pelo backend.
                        </p>
                    </div>

                    {webhookUrl && (
                        <CopyField
                            label="URL de Webhook"
                            value={webhookUrl}
                            tooltip="Cole no seu App da Meta, em Webhooks → Retorno de chamada."
                        />
                    )}

                    {verifyToken && (
                        <CopyField
                            label="Verify Token"
                            value={verifyToken}
                            tooltip="Cole no mesmo lugar, no campo 'Verificar token' da Meta."
                        />
                    )}
                </div>

                {saveError && (
                    <div className="mt-6 bg-red-500/10 border border-red-500/30 text-red-400 text-sm rounded-lg p-3 flex items-start gap-2">
                        <Info size={16} weight="fill" className="flex-shrink-0 mt-0.5" />
                        <span>{saveError}</span>
                    </div>
                )}

                {saveSuccess && (
                    <div className="mt-6 bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-sm rounded-lg p-3 flex items-start gap-2">
                        <CheckCircle size={16} weight="fill" className="flex-shrink-0 mt-0.5" />
                        <span>Integração salva com sucesso.</span>
                    </div>
                )}

                <div className="mt-8">
                    <button
                        type="submit"
                        disabled={formDisabled}
                        className="w-full flex items-center justify-center gap-2 bg-gradient-to-r from-[#4f8bff] to-[#2f6bf0] disabled:opacity-50 text-white font-bold text-lg py-3.5 rounded-lg shadow-sm transition-all hover:shadow-glow"
                    >
                        <Lightning size={18} weight="fill" />
                        {isSaving ? 'Salvando...' : connectionState === 'connected' ? 'Atualizar Credenciais' : 'Conectar'}
                    </button>
                </div>
            </form>

            {compact && (
                <div className="mt-4 border border-line rounded-xl overflow-hidden">
                    <button
                        type="button"
                        onClick={() => setShowDataSources((v) => !v)}
                        className="w-full flex items-center justify-between px-5 py-3.5 bg-panel-2 text-left"
                    >
                        <span className="text-sm font-semibold text-ink">Onde conseguir esses dados?</span>
                        {showDataSources ? <CaretUp size={16} className="text-muted" /> : <CaretDown size={16} className="text-muted" />}
                    </button>
                    {showDataSources && (
                        <div className="divide-y divide-line">
                            {DATA_SOURCES.map((item) => (
                                <div key={item.question} className="px-5 py-3.5 bg-panel">
                                    <p className="text-sm font-semibold text-ink mb-1">{item.question}</p>
                                    <p className="text-xs text-muted">{item.answer}</p>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            )}
        </div>
    )
}
