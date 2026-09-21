import { db } from '@/lib/db'
import { integrations, integrationSecrets } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'
import { convertAudioToVoiceNote } from '@/lib/audioConvert'

export async function getWhatsAppCredentials(organizationId: string) {
  const [integration] = await db.select({ id: integrations.id, config: integrations.config })
    .from(integrations)
    .where(and(
      eq(integrations.organizationId, organizationId),
      eq(integrations.type, 'whatsapp_cloud_official'),
      isNull(integrations.deletedAt),
    ))
    .limit(1)

  if (!integration) throw { status: 400, message: 'Integração com WhatsApp não configurada.' }

  const [secretRow] = await db.select({ secret: integrationSecrets.secret })
    .from(integrationSecrets)
    .where(eq(integrationSecrets.integrationId, integration.id))
    .limit(1)

  const config = integration.config as { phone_number_id?: string; graph_api_version?: string }
  const secret = secretRow?.secret as { system_token?: string } | undefined

  if (!config?.phone_number_id || !secret?.system_token) {
    throw { status: 400, message: 'Integração com WhatsApp incompleta (faltando phone_number_id ou token).' }
  }

  return {
    apiVersion: config.graph_api_version || 'v21.0',
    phoneNumberId: config.phone_number_id,
    token: secret.system_token,
  }
}

export async function sendWhatsAppMessage(organizationId: string, phone: string, content: string) {
  const { apiVersion, phoneNumberId, token } = await getWhatsAppCredentials(organizationId)
  const to = phone.replace(/\D/g, '')

  const res = await fetch(`https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to,
      type: 'text',
      text: { body: content },
    }),
  })

  const data = await res.json().catch(() => ({}))

  if (!res.ok) {
    const errMsg = data?.error?.message || `Falha ao enviar mensagem (HTTP ${res.status})`
    throw { status: 502, message: errMsg, details: data }
  }

  return data
}

/**
 * Envia mídia (imagem, vídeo, áudio ou documento) via WhatsApp Cloud API a partir de uma URL pública.
 */
export async function sendWhatsAppMedia(
  organizationId: string,
  phone: string,
  mediaType: 'image' | 'video' | 'audio' | 'document' | 'sticker',
  mediaUrl: string,
  caption?: string,
  filename?: string
) {
  const { apiVersion, phoneNumberId, token } = await getWhatsAppCredentials(organizationId)
  const to = phone.replace(/\D/g, '')

  // A Cloud API só aceita áudio em AAC/AMR/MP3/MP4 ou Ogg com codec Opus puro; o
  // navegador grava em webm (ou mp4/aac no Safari) — remuxa pra Ogg/Opus antes de
  // enviar, senão a Meta rejeita com "Unsupported MIME type" (ver audioConvert.ts).
  const effectiveMediaUrl = mediaType === 'audio' ? await convertAudioToVoiceNote(mediaUrl) : mediaUrl

  const mediaPayload: Record<string, any> = { link: effectiveMediaUrl }
  if (caption && mediaType !== 'audio' && mediaType !== 'sticker') mediaPayload.caption = caption
  if (filename && mediaType === 'document') mediaPayload.filename = filename

  // WhatsApp Cloud API não tem tipo 'sticker' para mídia externa via link; envia como imagem
  const apiType = mediaType === 'sticker' ? 'image' : mediaType

  const res = await fetch(`https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to,
      type: apiType,
      [apiType]: mediaPayload,
    }),
  })

  const data = await res.json().catch(() => ({}))

  if (!res.ok) {
    const errMsg = data?.error?.message || `Falha ao enviar mídia (HTTP ${res.status})`
    throw { status: 502, message: errMsg, details: data }
  }

  return data
}
