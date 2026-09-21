'use client'

import Link from 'next/link'
import { ArrowLeft, WebhooksLogo, Info, CheckCircle, Warning, PaperPlaneTilt, CaretDown, CaretUp } from '@phosphor-icons/react'
import { useState, useEffect } from 'react'
import { useAuth } from '@/hooks'

const INTEGRATION_NAME = 'Webhook de Saída'
const INTEGRATION_TYPE = 'outbound_webhook'

const EXAMPLE_TEXT = `{
  "isStatusReply": false,
  "chatLid": null,
  "connectedPhone": "554792683488",
  "waitingMessage": false,
  "isEdit": false,
  "isGroup": false,
  "isNewsletter": false,
  "instanceId": "3E284D0A569560EED6291664B40E8DC7",
  "messageId": "2AC0B78C0521E55874A1",
  "phone": "553498098061",
  "fromMe": false,
  "momment": 1760090229000,
  "status": "RECEIVED",
  "chatName": "Pugas",
  "senderPhoto": null,
  "senderName": "Pugas",
  "photo": null,
  "broadcast": false,
  "participantLid": null,
  "messageExpirationSeconds": 0,
  "forwarded": false,
  "type": "ReceivedCallback",
  "fromApi": false,
  "text": {
    "message": "Oi, quero fazer um pedido"
  }
}`

const EXAMPLE_AUDIO = `{
  ...campos comuns acima...,
  "audio": {
    "ptt": true,
    "seconds": 47,
    "audioUrl": "https://.../arquivo.ogg",
    "mimeType": "audio/ogg; codecs=opus",
    "viewOnce": false
  }
}`

function FAQItem({ question, children }: { question: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(false)
  return (
    <div className="border rounded-lg bg-panel overflow-hidden">
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between p-4 text-left font-medium text-ink hover:bg-void transition-colors"
      >
        {question}
        {open ? <CaretUp size={16} className="text-muted" /> : <CaretDown size={16} className="text-muted" />}
      </button>
      {open && <div className="p-4 text-sm text-muted border-t border-line">{children}</div>}
    </div>
  )
}

export default function OutboundWebhookPage() {
  const { organizationId } = useAuth()

  const [url, setUrl] = useState('')
  const [enabled, setEnabled] = useState(true)
  const [integrationId, setIntegrationId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [isSaving, setIsSaving] = useState(false)
  const [saveMessage, setSaveMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)
  const [isTesting, setIsTesting] = useState(false)
  const [testResult, setTestResult] = useState<{ ok: boolean; text: string } | null>(null)

  useEffect(() => {
    if (!organizationId) return
    const load = async () => {
      setLoading(true)
      const res = await fetch(`/api/integrations?name=${encodeURIComponent(INTEGRATION_NAME)}`)
      const { data } = res.ok ? await res.json() : { data: [] }
      const existing = data?.[0] || null
      if (existing) {
        setIntegrationId(existing.id)
        setUrl(existing.config?.url || '')
        setEnabled(existing.config?.enabled !== false)
      }
      setLoading(false)
    }
    load()
  }, [organizationId])

  const handleSave = async () => {
    if (!organizationId) return
    setIsSaving(true)
    setSaveMessage(null)
    try {
      const config = { url: url.trim(), enabled }
      if (integrationId) {
        const res = await fetch('/api/integrations', {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: integrationId, config }),
        })
        if (!res.ok) throw new Error()
      } else {
        const res = await fetch('/api/integrations', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name: INTEGRATION_NAME, type: INTEGRATION_TYPE, status: 'active', config }),
        })
        if (!res.ok) throw new Error()
        const { data } = await res.json()
        setIntegrationId(data.id)
      }
      setSaveMessage({ type: 'success', text: 'Configuração salva com sucesso.' })
    } catch {
      setSaveMessage({ type: 'error', text: 'Erro ao salvar a configuração.' })
    } finally {
      setIsSaving(false)
    }
  }

  const handleTest = async () => {
    if (!url.trim()) {
      setTestResult({ ok: false, text: 'Informe uma URL antes de testar.' })
      return
    }
    setIsTesting(true)
    setTestResult(null)
    try {
      const res = await fetch('/api/integrations/webhook/test', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url: url.trim() }),
      })
      const data = await res.json()
      if (data.ok) {
        setTestResult({ ok: true, text: `Webhook respondeu com sucesso (HTTP ${data.status}).` })
      } else {
        setTestResult({ ok: false, text: data.error || 'Não foi possível confirmar o recebimento pelo webhook.' })
      }
    } catch {
      setTestResult({ ok: false, text: 'Erro ao enviar o teste.' })
    } finally {
      setIsTesting(false)
    }
  }

  return (
    <div className="max-w-4xl pb-12">
      <div className="flex items-center gap-4 mb-8">
        <Link href="/settings/integrations" className="p-2 -ml-2 hover:bg-panel-2 rounded-full transition-colors text-muted">
          <ArrowLeft size={20} />
        </Link>
        <div>
          <h1 className="text-2xl font-bold text-ink">Webhook de Saída</h1>
          <p className="text-muted text-sm mt-1">Envie toda mensagem recebida ou enviada pelo WhatsApp para uma URL externa, no formato Z-API.</p>
        </div>
      </div>

      <div className="bg-panel border rounded-xl p-4 sm:p-8 mb-6 shadow-sm">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-emerald-50 flex items-center justify-center text-emerald-600">
            <WebhooksLogo size={20} weight="bold" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-ink">Configuração</h2>
            <p className="text-sm text-muted">A URL será chamada via POST a cada nova mensagem.</p>
          </div>
        </div>

        {loading ? (
          <div className="text-sm text-muted">Carregando...</div>
        ) : (
          <div className="space-y-5">
            <div>
              <label className="block text-sm font-medium text-muted mb-1.5">URL do Webhook</label>
              <input
                type="url"
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                placeholder="https://webhook.seudominio.com.br/webhook/whatsapp"
                className="w-full bg-void border border-line text-ink text-sm rounded-lg focus:ring-emerald-500 focus:border-emerald-500 block p-2.5 outline-none"
              />
            </div>

            <div className="flex items-center justify-between border-t border-line pt-5">
              <div>
                <h4 className="text-sm font-bold text-ink">Ativo</h4>
                <p className="text-xs text-muted">Desative para pausar o envio sem apagar a URL configurada.</p>
              </div>
              <button
                onClick={() => setEnabled(!enabled)}
                className={`relative w-11 h-6 rounded-full transition-colors ${enabled ? 'bg-emerald-500' : 'bg-panel-2'}`}
              >
                <span className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-panel shadow transition-transform ${enabled ? 'translate-x-5' : 'translate-x-0'}`} />
              </button>
            </div>

            <div className="flex items-center gap-3 pt-2">
              <button
                onClick={handleSave}
                disabled={isSaving}
                className="px-5 py-2.5 bg-emerald-600 hover:bg-emerald-700 disabled:bg-emerald-300 text-white rounded-lg font-medium text-sm transition-colors"
              >
                {isSaving ? 'Salvando...' : 'Salvar'}
              </button>
              <button
                onClick={handleTest}
                disabled={isTesting}
                className="flex items-center gap-2 px-5 py-2.5 bg-panel-2 hover:bg-panel-2 disabled:opacity-60 text-muted rounded-lg font-medium text-sm transition-colors"
              >
                <PaperPlaneTilt size={16} weight="bold" />
                {isTesting ? 'Enviando...' : 'Enviar teste'}
              </button>
            </div>

            {saveMessage && (
              <div className={`flex items-center gap-2 text-sm ${saveMessage.type === 'success' ? 'text-emerald-600' : 'text-red-600'}`}>
                {saveMessage.type === 'success' ? <CheckCircle size={16} weight="fill" /> : <Warning size={16} weight="fill" />}
                {saveMessage.text}
              </div>
            )}
            {testResult && (
              <div className={`flex items-center gap-2 text-sm ${testResult.ok ? 'text-emerald-600' : 'text-red-600'}`}>
                {testResult.ok ? <CheckCircle size={16} weight="fill" /> : <Warning size={16} weight="fill" />}
                {testResult.text}
              </div>
            )}
          </div>
        )}
      </div>

      <div className="bg-panel border rounded-xl p-4 sm:p-8 shadow-sm">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-emerald-50 flex items-center justify-center text-emerald-600">
            <Info size={18} weight="bold" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-ink">Como funciona</h2>
            <p className="text-sm text-muted">Formato do payload enviado ao seu webhook.</p>
          </div>
        </div>

        <div className="space-y-4">
          <FAQItem question="Quando o webhook é disparado?">
            A cada mensagem que passar pelo CRM via WhatsApp (Cloud API oficial ou Evolution API), tanto recebidas do
            cliente (<code className="bg-panel-2 px-1 rounded">fromMe: false</code>) quanto enviadas pelo número
            conectado (<code className="bg-panel-2 px-1 rounded">fromMe: true</code>). Use o campo{' '}
            <code className="bg-panel-2 px-1 rounded">fromMe</code> para filtrar no seu agente.
          </FAQItem>
          <FAQItem question="Qual o formato do corpo enviado?">
            O mesmo formato usado pela Z-API nos webhooks de mensagem recebida (ReceivedCallback), para que automações
            já prontas para Z-API funcionem sem adaptação. O conteúdo da mensagem muda de acordo com o tipo:{' '}
            <code className="bg-panel-2 px-1 rounded">text</code>, <code className="bg-panel-2 px-1 rounded">image</code>,{' '}
            <code className="bg-panel-2 px-1 rounded">video</code>, <code className="bg-panel-2 px-1 rounded">audio</code>{' '}
            ou <code className="bg-panel-2 px-1 rounded">document</code>.
            <pre className="mt-3 bg-void text-ink text-xs p-4 rounded-lg overflow-x-auto">{EXAMPLE_TEXT}</pre>
          </FAQItem>
          <FAQItem question="E mensagens de áudio?">
            O objeto muda para <code className="bg-panel-2 px-1 rounded">audio</code>, com a URL do arquivo e a
            duração em segundos:
            <pre className="mt-3 bg-void text-ink text-xs p-4 rounded-lg overflow-x-auto">{EXAMPLE_AUDIO}</pre>
          </FAQItem>
          <FAQItem question="O que acontece se o meu webhook estiver fora do ar?">
            A falha é registrada internamente e não afeta o funcionamento do CRM — a mensagem continua sendo salva
            normalmente no atendimento, apenas o envio para o webhook falha silenciosamente.
          </FAQItem>
        </div>
      </div>
    </div>
  )
}
