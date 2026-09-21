'use client'

import { useEffect, useState } from 'react'
import { Copy, Check, Eye, EyeClosed, ArrowClockwise, CheckCircle, Info } from '@phosphor-icons/react'
import Modal from '@/components/Shared/Modal'
import LoadingSpinner from '@/components/Shared/LoadingSpinner'

interface Member {
  memberId: string
  userId: string
  fullName: string | null
  email: string
  roleName: string
  createdAt: string
}

interface OrgDetail {
  id: string
  name: string
  subscriptionStatus: string
  totalMessages: number
  members: Member[]
  whatsapp: {
    integrationId: string
    wabaId: string
    phoneNumberId: string
    graphApiVersion: string
    systemToken: string
  } | null
}

const STATUS_OPTIONS = [
  { value: 'active', label: 'Assinatura ativa' },
  { value: 'unpaid', label: 'Não pago' },
  { value: 'cancelled', label: 'Cancelado' },
]

function CopyableInput({ value, onChange, placeholder, masked, onToggleMask }: {
  value: string
  onChange: (v: string) => void
  placeholder?: string
  masked?: boolean
  onToggleMask?: () => void
}) {
  const [copied, setCopied] = useState(false)
  const handleCopy = () => {
    navigator.clipboard.writeText(value)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }
  return (
    <div className="flex items-center gap-2">
      <input
        type={masked === undefined ? 'text' : masked ? 'password' : 'text'}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="flex-1 min-w-0 bg-panel-2 border border-line rounded-lg px-3 py-2 text-sm text-ink font-mono placeholder:text-muted focus:outline-none focus:ring-2 focus:ring-accent focus:border-transparent"
      />
      {onToggleMask && (
        <button type="button" onClick={onToggleMask} className="p-2 text-muted hover:text-ink border border-line rounded-lg flex-shrink-0" tabIndex={-1}>
          {masked ? <Eye size={16} /> : <EyeClosed size={16} />}
        </button>
      )}
      <button type="button" onClick={handleCopy} disabled={!value} className="p-2 text-muted hover:text-ink border border-line rounded-lg flex-shrink-0 disabled:opacity-40" title="Copiar">
        {copied ? <Check size={16} className="text-emerald-400" /> : <Copy size={16} />}
      </button>
    </div>
  )
}

export default function OrgDetailModal({ organizationId, onClose, onUpdated }: {
  organizationId: string
  onClose: () => void
  onUpdated: () => void
}) {
  const [org, setOrg] = useState<OrgDetail | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  const [wabaId, setWabaId] = useState('')
  const [phoneNumberId, setPhoneNumberId] = useState('')
  const [graphApiVersion, setGraphApiVersion] = useState('v21.0')
  const [systemToken, setSystemToken] = useState('')
  const [showToken, setShowToken] = useState(false)
  const [subscriptionStatus, setSubscriptionStatus] = useState('active')

  const [saving, setSaving] = useState(false)
  const [saveError, setSaveError] = useState('')
  const [saveSuccess, setSaveSuccess] = useState(false)

  const [resettingId, setResettingId] = useState<string | null>(null)
  const [resetResult, setResetResult] = useState<{ userId: string; password: string } | null>(null)

  const [origin, setOrigin] = useState('')
  useEffect(() => { if (typeof window !== 'undefined') setOrigin(window.location.origin) }, [])

  const load = () => {
    setLoading(true)
    fetch(`/api/admin/organizations/${organizationId}`)
      .then(async (res) => {
        if (!res.ok) throw new Error((await res.json()).error || 'Erro ao carregar organização')
        return res.json()
      })
      .then((data: OrgDetail) => {
        setOrg(data)
        setSubscriptionStatus(data.subscriptionStatus)
        if (data.whatsapp) {
          setWabaId(data.whatsapp.wabaId)
          setPhoneNumberId(data.whatsapp.phoneNumberId)
          setGraphApiVersion(data.whatsapp.graphApiVersion)
        }
      })
      .catch((err) => setError(err.message))
      .finally(() => setLoading(false))
  }

  useEffect(load, [organizationId])

  const handleSave = async () => {
    setSaving(true)
    setSaveError('')
    setSaveSuccess(false)
    try {
      const body: Record<string, any> = {
        subscription_status: subscriptionStatus,
        waba_id: wabaId.trim(),
        phone_number_id: phoneNumberId.trim(),
        graph_api_version: graphApiVersion.trim() || 'v21.0',
      }
      if (systemToken) body.system_token = systemToken
      const res = await fetch(`/api/admin/organizations/${organizationId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      })
      const data = await res.json()
      if (!res.ok) throw new Error(data?.error || 'Erro ao salvar')
      setSaveSuccess(true)
      setSystemToken('')
      onUpdated()
    } catch (err: any) {
      setSaveError(err.message)
    } finally {
      setSaving(false)
    }
  }

  const handleResetPassword = async (userId: string) => {
    setResettingId(userId)
    setResetResult(null)
    try {
      const res = await fetch(`/api/admin/users/${userId}/reset-password`, { method: 'POST' })
      const data = await res.json()
      if (!res.ok) throw new Error(data?.error || 'Erro ao redefinir senha')
      setResetResult({ userId, password: data.newPassword })
    } catch (err: any) {
      setError(err.message)
    } finally {
      setResettingId(null)
    }
  }

  const webhookUrl = origin ? `${origin}/api/webhooks/facebook?org_id=${organizationId}` : ''

  return (
    <Modal isOpen onClose={onClose} title={org?.name || 'Organização'} maxWidthClassName="max-w-2xl">
      <div className="max-h-[75vh] overflow-y-auto px-6 py-5 space-y-6">
        {loading && <LoadingSpinner text="Carregando..." size="lg" />}
        {error && <p className="text-sm text-red-400">{error}</p>}

        {org && (
          <>
            <section>
              <h3 className="text-sm font-semibold text-ink mb-3">Membros ({org.members.length})</h3>
              <div className="space-y-2">
                {org.members.map((m) => (
                  <div key={m.memberId} className="flex items-center justify-between gap-3 bg-panel-2 border border-line rounded-lg px-3 py-2.5">
                    <div className="min-w-0">
                      <p className="text-sm font-medium text-ink truncate">{m.fullName || m.email}</p>
                      <p className="text-xs text-muted truncate">{m.email} · {m.roleName}</p>
                    </div>
                    <div className="flex-shrink-0 text-right">
                      {resetResult?.userId === m.userId ? (
                        <div className="flex items-center gap-2">
                          <code className="text-xs bg-void px-2 py-1 rounded text-emerald-400">{resetResult.password}</code>
                          <button
                            type="button"
                            onClick={() => navigator.clipboard.writeText(resetResult.password)}
                            className="p-1.5 text-muted hover:text-ink border border-line rounded-lg"
                            title="Copiar senha"
                          >
                            <Copy size={14} />
                          </button>
                        </div>
                      ) : (
                        <button
                          type="button"
                          onClick={() => handleResetPassword(m.userId)}
                          disabled={resettingId === m.userId}
                          className="flex items-center gap-1.5 text-xs font-medium text-muted hover:text-ink border border-line rounded-lg px-2.5 py-1.5 disabled:opacity-50"
                        >
                          <ArrowClockwise size={14} className={resettingId === m.userId ? 'animate-spin' : ''} />
                          Redefinir senha
                        </button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </section>

            <section>
              <h3 className="text-sm font-semibold text-ink mb-3">Status da assinatura</h3>
              <select
                value={subscriptionStatus}
                onChange={(e) => setSubscriptionStatus(e.target.value)}
                className="w-full bg-panel-2 border border-line rounded-lg px-3 py-2.5 text-sm text-ink focus:outline-none focus:ring-2 focus:ring-accent"
              >
                {STATUS_OPTIONS.map((opt) => (
                  <option key={opt.value} value={opt.value}>{opt.label}</option>
                ))}
              </select>
            </section>

            <section className="space-y-3">
              <h3 className="text-sm font-semibold text-ink">Variáveis do WhatsApp (API Oficial)</h3>
              <div>
                <label className="block text-xs font-medium text-muted mb-1.5">WABA ID</label>
                <CopyableInput value={wabaId} onChange={setWabaId} placeholder="Ex: 10928374650123" />
              </div>
              <div>
                <label className="block text-xs font-medium text-muted mb-1.5">Phone Number ID</label>
                <CopyableInput value={phoneNumberId} onChange={setPhoneNumberId} placeholder="Ex: 5523478901234567" />
              </div>
              <div>
                <label className="block text-xs font-medium text-muted mb-1.5">Graph API Version</label>
                <CopyableInput value={graphApiVersion} onChange={setGraphApiVersion} placeholder="v21.0" />
              </div>
              <div>
                <label className="block text-xs font-medium text-muted mb-1.5">System User Token</label>
                <CopyableInput
                  value={systemToken}
                  onChange={setSystemToken}
                  masked={showToken ? false : true}
                  onToggleMask={() => setShowToken((v) => !v)}
                  placeholder={org.whatsapp?.systemToken ? '•••••••••••••• (deixe em branco pra manter o atual)' : 'EAAW...'}
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-muted mb-1.5">URL de Webhook</label>
                <CopyableInput value={webhookUrl} onChange={() => {}} />
              </div>
            </section>

            {saveError && (
              <div className="bg-red-500/10 border border-red-500/30 text-red-400 text-sm rounded-lg p-3 flex items-start gap-2">
                <Info size={16} weight="fill" className="flex-shrink-0 mt-0.5" />
                <span>{saveError}</span>
              </div>
            )}
            {saveSuccess && (
              <div className="bg-emerald-500/10 border border-emerald-500/30 text-emerald-400 text-sm rounded-lg p-3 flex items-start gap-2">
                <CheckCircle size={16} weight="fill" className="flex-shrink-0 mt-0.5" />
                <span>Alterações salvas com sucesso.</span>
              </div>
            )}

            <div className="flex justify-end gap-3 pt-2">
              <button type="button" onClick={onClose} className="px-4 py-2.5 text-sm font-medium text-muted hover:text-ink">
                Fechar
              </button>
              <button
                type="button"
                onClick={handleSave}
                disabled={saving}
                className="px-5 py-2.5 bg-gradient-to-r from-[#4f8bff] to-[#2f6bf0] text-white text-sm font-semibold rounded-lg shadow-sm hover:shadow-glow disabled:opacity-50"
              >
                {saving ? 'Salvando...' : 'Salvar alterações'}
              </button>
            </div>
          </>
        )}
      </div>
    </Modal>
  )
}
