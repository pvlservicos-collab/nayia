import { NextRequest } from 'next/server'
import { db } from '@/lib/db'
import { integrationMessageLogs } from '@/lib/schema'
import { extractPhone, sendAutomatedMessage, ORGANIZATION_ID } from '@/lib/automated-message'

/**
 * POST /api/webhooks/recuperacao
 * Webhook para disparo automático de mensagem de recuperação de PIX não pago.
 *
 * Sem autenticação (uso interno). Tolerante a payloads desformatados:
 * - aceita JSON inválido/vazio
 * - aceita array (usa o primeiro item)
 * - aceita vários formatos de telefone (phone, telefone, wa_id, etc.)
 */
export async function POST(req: NextRequest) {
  const raw = await req.text()

  let parsed: any = null
  let parseError: string | null = null
  try {
    parsed = raw ? JSON.parse(raw) : {}
  } catch (err: any) {
    parseError = `JSON inválido: ${err.message}`
  }

  const body = Array.isArray(parsed) ? (parsed[0] ?? {}) : (parsed ?? {})
  const phone = extractPhone(body)

  if (parseError || !phone) {
    await db.insert(integrationMessageLogs).values({
      organizationId: ORGANIZATION_ID,
      source: 'recuperacao',
      direction: 'outbound',
      phone: phone || null,
      content: null,
      status: 'error',
      error: parseError || 'Não foi possível identificar o telefone (phone) na mensagem.',
      payload: { raw, parsed },
    }).catch(() => {})
    return Response.json({ status: 'ok', sent: false })
  }

  const content = `👀 Oi! Vi aqui que o pagamento do PIX ainda não foi confirmado.

Sua figurinha ainda está salva por alguns minutinhos... ⏳

Pra te dar um incentivo, liberamos um desconto especial: de R$ 12,90 por apenas R$ 7,90!

Aproveita agora antes que ela seja removida! 👇
https://gerarfigurinhas.vercel.app/preview-desconto/${phone}?utm_source=rec`

  const result = await sendAutomatedMessage({ phone, content, source: 'recuperacao', raw, parsed })

  return Response.json({ status: 'ok', lead_id: result.leadId, activity_id: result.activityId })
}
