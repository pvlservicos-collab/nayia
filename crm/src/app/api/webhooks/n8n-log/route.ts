import { NextRequest } from 'next/server'
import { db } from '@/lib/db'
import { integrationMessageLogs } from '@/lib/schema'

const ORGANIZATION_ID = '91a7f4af-9e58-4e30-906b-b0ebc9386da4'

/**
 * POST /api/webhooks/n8n-log
 * Apenas registra a mensagem na aba Logs — não cria/atualiza conversas no CRM.
 *
 * Sem autenticação (uso interno). Tolerante a payloads desformatados:
 * - aceita JSON inválido/vazio (loga como erro, mas não derruba o fluxo do n8n)
 * - aceita array (usa o primeiro item)
 * - aceita tanto { phone, content, ... } quanto a resposta crua da API do
 *   WhatsApp (com "contacts"/"messages"), extraindo phone/content/whatsapp_message_id
 *   de vários formatos possíveis
 *
 * Para identificar de qual fluxo do n8n veio o log, adicione ?flow=NOME na URL
 * do webhook (ex: .../api/webhooks/n8n-log?flow=figurinha_aprovada). O valor
 * aparece na coluna "Origem" da aba de Logs como "n8n:NOME".
 */
export async function POST(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const flow = searchParams.get('flow')
  const raw = await req.text()

  let parsed: any = null
  let parseError: string | null = null
  try {
    parsed = raw ? JSON.parse(raw) : {}
  } catch (err: any) {
    parseError = `JSON inválido: ${err.message}`
  }

  // n8n às vezes envia um array de items
  const body = Array.isArray(parsed) ? (parsed[0] ?? {}) : (parsed ?? {})

  const phone =
    body.phone ??
    body.wa_id ??
    body.contacts?.[0]?.wa_id ??
    body.contacts?.[0]?.input ??
    body.messages?.[0]?.from ??
    null

  const content =
    body.content ??
    body.text ??
    body.message ??
    body.messages?.[0]?.text?.body ??
    body.messages?.[0]?.template?.name ??
    null

  const whatsappMessageId =
    body.whatsapp_message_id ??
    body.messages?.[0]?.id ??
    body.message_id ??
    null

  const messageStatus =
    body.message_status ??
    body.messages?.[0]?.message_status ??
    body.status ??
    null

  const direction = typeof body.direction === 'string' ? body.direction : 'outbound'
  const status = parseError ? 'error' : (body.status === 'error' ? 'error' : 'success')
  const error = parseError || body.error || null

  try {
    await db.insert(integrationMessageLogs).values({
      organizationId: ORGANIZATION_ID,
      source: flow ? `n8n:${flow}` : 'n8n',
      direction,
      phone: phone != null ? String(phone) : null,
      content: content != null ? String(content) : null,
      status,
      error,
      payload: {
        raw,
        parsed: parsed ?? null,
        whatsapp_message_id: whatsappMessageId,
        message_status: messageStatus,
      },
    })
  } catch (err: any) {
    console.error('[n8n-log] erro ao salvar log:', err)
  }

  // Sempre responde 200 para não quebrar o fluxo do n8n
  return Response.json({ status: 'ok' })
}
