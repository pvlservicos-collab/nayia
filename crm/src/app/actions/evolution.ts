'use server'

const EVOLUTION_SERVER = process.env.EVOLUTION_API_URL
const EVOLUTION_API_KEY = process.env.EVOLUTION_API_KEY

const apiFetch = async (endpoint: string, options: RequestInit = {}) => {
  if (!EVOLUTION_SERVER || !EVOLUTION_API_KEY) {
    throw new Error('Credenciais da Evolution API não configuradas.')
  }
  const res = await fetch(`${EVOLUTION_SERVER}${endpoint}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      'apikey': EVOLUTION_API_KEY,
      ...(options.headers as Record<string, string> || {}),
    },
  })
  const data = await res.json().catch(() => ({}))
  return { ok: res.ok, status: res.status, data }
}

export async function createInstance(instanceName: string) {
  try {
    const res = await apiFetch('/instance/create', {
      method: 'POST',
      body: JSON.stringify({
        instanceName,
        integration: 'WHATSAPP-BAILEYS',
        qrcode: true,
      }),
    })
    if (res.ok || res.status === 201) {
      return { success: true, data: res.data }
    }
    return { success: false, error: `Falha ao criar instância: ${JSON.stringify(res.data)}` }
  } catch (e: any) {
    return { success: false, error: e.message }
  }
}

export async function getInstanceStatus(instanceName: string) {
  try {
    const res = await apiFetch(`/instance/connectionState/${instanceName}`)
    if (res.ok) {
      const state = res.data?.instance?.state || res.data?.state || 'close'
      return { success: true, state }
    }
    return { success: true, state: 'not_created' }
  } catch (e: any) {
    return { success: false, error: e.message }
  }
}

export async function connectInstance(instanceName: string) {
  try {
    const res = await apiFetch(`/instance/connect/${instanceName}`)
    if (res.ok) {
      // Evolution v2 returns base64 QR as res.data.base64 or inside res.data.qrcode
      const base64 = res.data?.base64 || res.data?.qrcode?.base64
      if (base64) return { success: true, base64Url: `data:image/png;base64,${base64}` }
      // Some versions return a data URL directly
      if (res.data?.code?.startsWith('data:')) return { success: true, base64Url: res.data.code }
      return { success: false, error: 'QR Code não disponível — aguarde e tente novamente' }
    }
    return { success: false, error: `Falha ao obter QR: ${JSON.stringify(res.data)}` }
  } catch (e: any) {
    return { success: false, error: e.message }
  }
}

export async function disconnectInstance(instanceName: string) {
  try {
    const res = await apiFetch(`/instance/logout/${instanceName}`, { method: 'DELETE' })
    return { success: res.ok }
  } catch (e: any) {
    return { success: false, error: e.message }
  }
}

export async function deleteInstance(instanceName: string) {
  try {
    const res = await apiFetch(`/instance/delete/${instanceName}`, { method: 'DELETE' })
    return { success: res.ok, data: res.data }
  } catch (e: any) {
    return { success: false, error: e.message }
  }
}

export async function setWebhook(instanceName: string, webhookUrl: string) {
  try {
    const res = await apiFetch(`/webhook/set/${instanceName}`, {
      method: 'POST',
      body: JSON.stringify({
        webhook: {
          enabled: true,
          url: webhookUrl,
          webhookByEvents: false,
          webhookBase64: false,
          events: ['MESSAGES_UPSERT', 'CONNECTION_UPDATE'],
        },
      }),
    })
    if (res.ok) return { success: true }
    return { success: false, error: JSON.stringify(res.data) }
  } catch (e: any) {
    return { success: false, error: e.message }
  }
}
