/**
 * Webhook de saída: replica, no formato de webhook da Z-API, toda mensagem que
 * passa pelos webhooks de entrada (Evolution API, WhatsApp Cloud API), para que
 * automações externas (ex: agente de IA no n8n) já preparadas para o padrão
 * Z-API consigam interpretar sem adaptação.
 */
import { db } from './db'
import { integrations, integrationMessageLogs } from './schema'
import { eq, and, isNull } from 'drizzle-orm'

export const OUTBOUND_WEBHOOK_INTEGRATION_TYPE = 'outbound_webhook'
export const OUTBOUND_WEBHOOK_INTEGRATION_NAME = 'Webhook de Saída'

type MediaType = 'image' | 'video' | 'audio' | 'document' | 'sticker'

export interface OutboundWebhookMessage {
  leadId?: string | null
  phone: string
  fromMe: boolean
  isGroup?: boolean
  chatLid?: string | null
  senderName?: string | null
  chatName?: string | null
  senderPhoto?: string | null
  content: string
  messageId?: string | null
  /** epoch em milissegundos */
  timestamp?: number | null
  instanceId?: string | null
  connectedPhone?: string | null
  mediaType?: MediaType | null
  mediaUrl?: string | null
  mediaMimetype?: string | null
  mediaFilename?: string | null
  audioSeconds?: number | null
  audioPtt?: boolean | null
}

function buildMediaField(msg: OutboundWebhookMessage): Record<string, any> {
  const caption = msg.content || ''

  switch (msg.mediaType) {
    case 'image':
      return { image: { imageUrl: msg.mediaUrl ?? null, caption, mimeType: msg.mediaMimetype || 'image/jpeg' } }
    case 'video':
      return { video: { videoUrl: msg.mediaUrl ?? null, caption, mimeType: msg.mediaMimetype || 'video/mp4' } }
    case 'audio':
      return {
        audio: {
          ptt: msg.audioPtt ?? true,
          seconds: msg.audioSeconds ?? 0,
          audioUrl: msg.mediaUrl ?? null,
          mimeType: msg.mediaMimetype || 'audio/ogg; codecs=opus',
          viewOnce: false,
        },
      }
    case 'document':
      return {
        document: {
          documentUrl: msg.mediaUrl ?? null,
          fileName: msg.mediaFilename || caption || 'documento',
          mimeType: msg.mediaMimetype || 'application/octet-stream',
        },
      }
    case 'sticker':
      return { sticker: { stickerUrl: msg.mediaUrl ?? null, mimeType: msg.mediaMimetype || 'image/webp' } }
    default:
      return { text: { message: caption } }
  }
}

/** Monta o corpo do webhook no formato usado pela Z-API (ReceivedCallback). */
export function buildZApiStylePayload(msg: OutboundWebhookMessage): Record<string, any> {
  const senderName = msg.senderName || msg.phone
  const senderPhoto = msg.senderPhoto ?? null

  return {
    isStatusReply: false,
    chatLid: msg.chatLid ?? null,
    connectedPhone: msg.connectedPhone ?? null,
    waitingMessage: false,
    isEdit: false,
    isGroup: !!msg.isGroup,
    isNewsletter: false,
    instanceId: msg.instanceId ?? null,
    messageId: msg.messageId ?? null,
    phone: msg.phone,
    fromMe: msg.fromMe,
    momment: msg.timestamp ?? Date.now(),
    status: 'RECEIVED',
    chatName: msg.chatName || senderName,
    senderPhoto,
    senderName,
    photo: senderPhoto,
    broadcast: false,
    participantLid: null,
    messageExpirationSeconds: 0,
    forwarded: false,
    type: 'ReceivedCallback',
    fromApi: false,
    ...buildMediaField(msg),
  }
}

async function getWebhookConfig(orgId: string): Promise<{ url: string; enabled: boolean } | null> {
  const [integration] = await db
    .select({ config: integrations.config })
    .from(integrations)
    .where(
      and(
        eq(integrations.organizationId, orgId),
        eq(integrations.type, OUTBOUND_WEBHOOK_INTEGRATION_TYPE),
        isNull(integrations.deletedAt)
      )
    )
    .limit(1)

  const config = integration?.config as { url?: string; enabled?: boolean } | undefined
  if (!config?.url) return null
  return { url: config.url, enabled: config.enabled !== false }
}

/**
 * Envia a mensagem para o webhook de saída configurado pela organização, se houver.
 * Nunca lança erro: falhas de rede/URL apenas ficam registradas em integration_message_logs
 * para não interromper o processamento do webhook de entrada que a originou.
 */
export async function dispatchOutboundWebhook(orgId: string, msg: OutboundWebhookMessage): Promise<void> {
  try {
    const config = await getWebhookConfig(orgId)
    if (!config || !config.enabled) return

    const payload = buildZApiStylePayload(msg)

    let status: 'success' | 'error' = 'success'
    let error: string | null = null

    try {
      const controller = new AbortController()
      const timeout = setTimeout(() => controller.abort(), 8000)
      const res = await fetch(config.url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller.signal,
      }).finally(() => clearTimeout(timeout))

      if (!res.ok) {
        status = 'error'
        error = `HTTP ${res.status}`
      }
    } catch (err: any) {
      status = 'error'
      error = err?.message || 'Falha ao conectar no webhook'
    }

    await db.insert(integrationMessageLogs).values({
      organizationId: orgId,
      source: 'outbound_webhook',
      direction: 'outbound',
      phone: msg.phone,
      content: msg.content,
      leadId: msg.leadId || undefined,
      status,
      error,
      payload,
    })
  } catch (err) {
    console.error('[outbound-webhook] dispatch failed', err)
  }
}
