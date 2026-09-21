import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { buildZApiStylePayload } from '@/lib/outbound-webhook'

export async function POST(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const body = await req.json()
    const url = (body?.url || '').trim()
    if (!url) return apiError(400, 'url é obrigatória.')

    const payload = buildZApiStylePayload({
      phone: '5511999999999',
      fromMe: false,
      isGroup: false,
      senderName: 'Contato de Teste',
      content: 'Esta é uma mensagem de teste do webhook de saída.',
      messageId: `test-${Date.now()}`,
      timestamp: Date.now(),
      instanceId: 'test',
      connectedPhone: null,
    })

    let status = 0
    let error: string | null = null
    try {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 8000)
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal,
      }).finally(() => clearTimeout(timeout))
      status = res.status
      if (!res.ok) error = `HTTP ${res.status}`
    } catch (err: any) {
      error = err?.message || 'Falha ao conectar no webhook'
    }

    return Response.json({ ok: !error, status, error, payload })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
