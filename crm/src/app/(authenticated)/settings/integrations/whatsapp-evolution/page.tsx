'use client'

import Link from 'next/link'
import { ArrowLeft, ArrowsClockwise, Info, DeviceMobile, CheckCircle, Warning, CaretDown, CaretUp, UsersThree } from '@phosphor-icons/react'
import { useState, useEffect } from 'react'
import {
  getInstanceStatus,
  disconnectInstance,
  createInstance,
  connectInstance,
  setWebhook,
  deleteInstance,
} from '@/app/actions/evolution'
import { useAuth, usePipeline } from '@/hooks'

const INTEGRATION_NAME = 'WhatsApp Evolution'
const INTEGRATION_TYPE = 'whatsapp_evolution'

const FAQS = [
  {
    question: 'O celular precisa estar ligado?',
    answer: 'Sim, a conexão depende do estado do celular. Se ficar offline por muito tempo, a conexão será perdida.',
  },
  {
    question: 'Qual a diferença para o API Oficial?',
    answer: 'A Evolution API usa tecnologia Baileys (WhatsApp Web) — sem limite de templates, mas sem o SLA da Meta. Ideal para alto volume de atendimento humano.',
  },
  {
    question: 'Tem limite de mensagens?',
    answer: 'Não há limite técnico, mas siga as boas práticas do WhatsApp para evitar banimentos.',
  },
  {
    question: 'Como funciona o QR Code?',
    answer: 'Escaneie com o celular em WhatsApp > Aparelhos Conectados > Conectar um Aparelho.',
  },
]

function FAQItem({ question, answer }: { question: string; answer: string }) {
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
      <div className={`overflow-hidden transition-all duration-300 ${open ? 'max-h-40 opacity-100' : 'max-h-0 opacity-0'}`}>
        <div className="p-4 text-sm text-muted border-t border-line">{answer}</div>
      </div>
    </div>
  )
}

export default function WhatsAppEvolutionPage() {
  const { organizationId } = useAuth()
  const { pipelines } = usePipeline(organizationId || '')

  const [instanceName, setInstanceName] = useState<string | null>(null)
  const [defaultPipelineId, setDefaultPipelineId] = useState('')
  const [listenGroups, setListenGroups] = useState(false)
  const [connectionState, setConnectionState] = useState('loading')
  const [qrCodeBase64, setQrCodeBase64] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [isCreating, setIsCreating] = useState(false)

  // Derive instance name from org
  useEffect(() => {
    if (!organizationId) return
    const fetchOrg = async () => {
      const res = await fetch('/api/organizations')
      const { data } = res.ok ? await res.json() : { data: null }
      const orgName = data?.name ? data.name.replace(/[^a-zA-Z0-9]/g, '').toLowerCase() : 'atlas'
      const prefix = organizationId.replace(/-/g, '').substring(0, 6)
      setInstanceName(`${orgName}_evo_${prefix}`)
    }
    fetchOrg()
  }, [organizationId])

  // Load saved integration config
  const loadIntegration = async () => {
    if (!organizationId) return null
    const res = await fetch(`/api/integrations?name=${encodeURIComponent(INTEGRATION_NAME)}`)
    const { data } = res.ok ? await res.json() : { data: [] }
    return data?.[0] || null
  }

  const saveIntegration = async (cfg: Record<string, any>) => {
    if (!organizationId || !instanceName) return
    const existing = await loadIntegration()
    if (existing) {
      await fetch('/api/integrations', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: existing.id, config: { ...existing.config, ...cfg }, mergeConfig: true }),
      })
    } else {
      await fetch('/api/integrations', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: INTEGRATION_NAME,
          type: INTEGRATION_TYPE,
          status: 'active',
          config: { instanceName, ...cfg },
        }),
      })
    }
  }

  // Initialize: check existing integration + instance status
  const initialize = async (name: string) => {
    setConnectionState('loading')
    setError(null)

    const existing = await loadIntegration()
    if (existing?.config?.defaultPipelineId) setDefaultPipelineId(existing.config.defaultPipelineId)
    if (existing?.config?.listenGroups !== undefined) setListenGroups(existing.config.listenGroups)

    const savedInstanceName = existing?.config?.instanceName || name
    const res = await getInstanceStatus(savedInstanceName)
    if (res.success) {
      const state = normalizeState(res.state)
      setConnectionState(state)
    } else {
      setConnectionState('not_created')
    }
  }

  useEffect(() => {
    if (!instanceName) return
    initialize(instanceName)
  }, [instanceName])

  // Poll while waiting for QR scan
  useEffect(() => {
    if (!instanceName) return
    const polling = ['created', 'disconnected', 'connecting']
    if (!polling.includes(connectionState)) return

    const interval = setInterval(async () => {
      const res = await getInstanceStatus(instanceName)
      if (res.success) {
        const state = normalizeState(res.state)
        if ((state === 'connecting' || state === 'disconnected' || state === 'created') && !qrCodeBase64) {
          fetchQr()
        }
        setConnectionState(prev => prev !== state ? state : prev)
      }
    }, 3000)

    return () => clearInterval(interval)
  }, [instanceName, connectionState, qrCodeBase64])

  // Register webhook when connected
  useEffect(() => {
    if (connectionState !== 'connected' || !instanceName || !organizationId) return
    saveIntegration({ instanceName })
    const webhookUrl = `${window.location.origin}/api/webhooks/evolution?org_id=${organizationId}`
    setWebhook(instanceName, webhookUrl).catch(console.error)
  }, [connectionState, instanceName, organizationId])

  function normalizeState(state: string) {
    if (state === 'open') return 'connected'
    if (state === 'close' || state === 'closed') return 'disconnected'
    return state || 'not_created'
  }

  const fetchQr = async () => {
    if (!instanceName) return
    const res = await connectInstance(instanceName)
    if (res.success && res.base64Url) setQrCodeBase64(res.base64Url)
  }

  const handleCreate = async () => {
    if (!instanceName) return
    setIsCreating(true)
    setError(null)
    const res = await createInstance(instanceName)
    if (res.success) {
      await saveIntegration({ instanceName })
      setConnectionState('created')
    } else {
      setError(res.error || 'Erro ao criar instância')
      setConnectionState('error')
    }
    setIsCreating(false)
  }

  const handleDisconnect = async () => {
    if (!instanceName) return
    setConnectionState('loading')
    setQrCodeBase64(null)
    await disconnectInstance(instanceName)
    setConnectionState('disconnected')
  }

  const handleDelete = async () => {
    if (!instanceName) return
    setConnectionState('loading')
    setQrCodeBase64(null)
    const existing = await loadIntegration()
    if (existing) {
      await fetch('/api/integrations', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: existing.id, status: 'disabled', config: { instanceName: '', defaultPipelineId: '' } }),
      })
    }
    await deleteInstance(instanceName)
    setDefaultPipelineId('')
    setConnectionState('not_created')
  }

  const handlePipelineChange = async (e: React.ChangeEvent<HTMLSelectElement>) => {
    const id = e.target.value
    setDefaultPipelineId(id)
    await saveIntegration({ defaultPipelineId: id })
  }

  const handleToggleGroups = async () => {
    const val = !listenGroups
    setListenGroups(val)
    await saveIntegration({ listenGroups: val })
  }

  return (
    <div className="max-w-5xl pb-12">
      <div className="flex items-center gap-4 mb-8">
        <Link href="/settings/integrations" className="p-2 -ml-2 hover:bg-panel-2 rounded-full transition-colors text-muted">
          <ArrowLeft size={20} />
        </Link>
        <div>
          <h1 className="text-2xl font-bold text-ink">WhatsApp — Número 2 (Evolution API)</h1>
          <p className="text-muted text-sm mt-1">Conecte um segundo número via QR Code usando a Evolution API.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-5 gap-6 mb-8">
        {/* QR / Status panel */}
        <div className="bg-panel border rounded-xl p-4 sm:p-8 flex flex-col items-center justify-center lg:col-span-3 min-h-[400px]">
          {connectionState === 'loading' && (
            <div className="flex flex-col items-center">
              <div className="w-12 h-12 border-4 border-purple-200 border-t-purple-500 rounded-full animate-spin mb-4" />
              <p className="text-muted">Verificando conexão...</p>
            </div>
          )}

          {connectionState === 'error' && (
            <div className="flex flex-col items-center text-center">
              <div className="w-16 h-16 bg-red-50 text-red-500 rounded-full flex items-center justify-center mb-4">
                <Warning size={32} />
              </div>
              <h3 className="text-lg font-bold text-ink mb-2">Erro de Conexão</h3>
              <p className="text-muted text-sm mb-6 max-w-sm">{error}</p>
              <button onClick={() => instanceName && initialize(instanceName)} className="px-4 py-2 bg-purple-50 text-purple-600 rounded-lg font-medium hover:bg-purple-100">
                Tentar Novamente
              </button>
            </div>
          )}

          {connectionState === 'not_created' && (
            <div className="flex flex-col items-center text-center w-full max-w-sm">
              <div className="w-16 h-16 bg-purple-50 text-purple-500 rounded-full flex items-center justify-center mb-6">
                <DeviceMobile size={32} weight="fill" />
              </div>
              <h3 className="text-xl font-bold text-ink mb-2">Configurar Número 2</h3>
              <p className="text-muted mb-8 text-sm">
                Nenhuma instância configurada. Clique abaixo para criar e escaneie o QR Code com seu celular.
              </p>
              <button
                onClick={handleCreate}
                disabled={isCreating}
                className="w-full py-3 bg-purple-600 hover:bg-purple-700 disabled:bg-purple-300 text-white rounded-lg font-medium transition-colors"
              >
                {isCreating ? 'Criando instância...' : 'Criar Instância & Gerar QR Code'}
              </button>
            </div>
          )}

          {connectionState === 'connected' && (
            <div className="flex flex-col items-center text-center">
              <div className="w-20 h-20 bg-green-50 text-green-500 rounded-full flex items-center justify-center mb-4">
                <CheckCircle size={40} weight="fill" />
              </div>
              <h3 className="text-xl font-bold text-ink mb-2">Número 2 Conectado!</h3>
              <p className="text-muted text-sm mb-8 max-w-sm">
                O WhatsApp via Evolution API está operando. Não desligue o celular da internet.
              </p>
              <div className="flex gap-4">
                <button onClick={handleDisconnect} className="px-6 py-2.5 bg-yellow-50 text-yellow-700 hover:bg-yellow-100 rounded-lg font-medium">
                  Desconectar
                </button>
                <button onClick={handleDelete} className="px-6 py-2.5 bg-red-50 text-red-600 hover:bg-red-100 rounded-lg font-medium">
                  Excluir Instância
                </button>
              </div>

              <div className="mt-8 pt-8 border-t border-line w-full text-left">
                <h4 className="text-sm font-bold text-ink mb-2">Funil de Destino</h4>
                <p className="text-xs text-muted mb-4">Funil para onde novos leads deste número serão enviados.</p>
                <select
                  value={defaultPipelineId}
                  onChange={handlePipelineChange}
                  className="w-full bg-void border border-line text-ink text-sm rounded-lg focus:ring-purple-500 focus:border-purple-500 block p-2.5 outline-none"
                >
                  <option value="">Selecione um Funil</option>
                  {pipelines.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </div>

              <div className="mt-6 pt-6 border-t border-line w-full text-left">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-lg bg-purple-50 flex items-center justify-center">
                      <UsersThree size={18} className="text-purple-500" weight="fill" />
                    </div>
                    <div>
                      <h4 className="text-sm font-bold text-ink">Escutar Grupos</h4>
                      <p className="text-xs text-muted">Receber mensagens de grupos no chat.</p>
                    </div>
                  </div>
                  <button
                    onClick={handleToggleGroups}
                    className={`relative w-11 h-6 rounded-full transition-colors ${listenGroups ? 'bg-purple-500' : 'bg-panel-2'}`}
                  >
                    <span className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-panel shadow transition-transform ${listenGroups ? 'translate-x-5' : 'translate-x-0'}`} />
                  </button>
                </div>
              </div>
            </div>
          )}

          {(['created', 'disconnected', 'connecting'].includes(connectionState)) && (
            <>
              <div className="relative w-48 h-48 sm:w-64 sm:h-64 bg-void border-2 border-dashed border-line rounded-xl flex items-center justify-center mb-8 overflow-hidden">
                {qrCodeBase64 ? (
                  <img src={qrCodeBase64} alt="Evolution QR Code" className="w-full h-full object-cover" />
                ) : (
                  <div className="w-32 h-32 sm:w-48 sm:h-48 bg-panel-2 rounded-lg animate-pulse" />
                )}
                <div className="absolute top-0 bottom-0 left-1/2 w-[2px] bg-purple-400 opacity-50 -ml-[1px]" />
                <div className="absolute left-0 right-0 top-1/2 h-[2px] bg-purple-400 opacity-50 -mt-[1px]" />
              </div>
              <div className="flex items-center gap-2 px-4 py-2 bg-yellow-50 text-yellow-700 text-sm font-medium rounded-full mb-6">
                <div className="w-2 h-2 rounded-full bg-yellow-500 animate-pulse" />
                {qrCodeBase64 ? 'Aguardando leitura' : 'Gerando QR Code...'}
              </div>
              <button
                onClick={fetchQr}
                className="flex items-center gap-2 bg-purple-600 hover:bg-purple-700 text-white px-6 py-2.5 rounded-lg font-medium"
              >
                <ArrowsClockwise size={18} weight="bold" />
                Gerar Novo QR Code
              </button>
            </>
          )}
        </div>

        {/* Instructions */}
        <div className="bg-panel border rounded-xl p-4 sm:p-8 lg:col-span-2 shadow-sm">
          <div className="flex items-center gap-3 mb-6">
            <div className="w-8 h-8 rounded-full bg-purple-50 flex items-center justify-center text-purple-600">
              <Info size={18} weight="bold" />
            </div>
            <h3 className="font-semibold text-ink text-lg">Como conectar?</h3>
          </div>
          <div className="space-y-6">
            {[
              ['1', 'Abra o WhatsApp no celular', 'Certifique-se de ter conexão com a internet.'],
              ['2', 'Toque em Aparelhos Conectados', 'Vá em Configurações e selecione "Aparelhos Conectados".'],
              ['3', 'Aponte para o QR Code', 'Toque em "Conectar um Aparelho" e escaneie o código ao lado.'],
            ].map(([n, title, desc]) => (
              <div key={n} className="flex gap-4">
                <div className="flex-shrink-0 w-8 h-8 rounded-full bg-panel-2 flex items-center justify-center text-muted font-semibold text-sm">{n}</div>
                <div>
                  <p className="font-medium text-ink text-sm">{title}</p>
                  <p className="text-xs text-muted mt-1">{desc}</p>
                </div>
              </div>
            ))}
          </div>
          <div className="mt-8 bg-purple-50/50 rounded-lg p-4 flex gap-3 border border-purple-100">
            <Info size={18} className="text-purple-600 flex-shrink-0 mt-0.5" />
            <p className="text-xs leading-relaxed text-purple-800">
              <span className="font-semibold">Dica:</span> Desative a economia de bateria para o WhatsApp no smartphone para manter a conexão estável.
            </p>
          </div>
        </div>
      </div>

      <div className="bg-panel border rounded-xl p-4 sm:p-8">
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-purple-50 flex items-center justify-center text-purple-600">
            <Info size={16} weight="bold" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-ink">Perguntas Frequentes</h2>
            <p className="text-sm text-muted">Dúvidas sobre o Número 2 via Evolution API.</p>
          </div>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {FAQS.map((faq, i) => <FAQItem key={i} question={faq.question} answer={faq.answer} />)}
        </div>
      </div>
    </div>
  )
}
