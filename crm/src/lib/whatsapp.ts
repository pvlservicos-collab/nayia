import { db } from '@/lib/db'
import { integrations, integrationSecrets } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'
import { convertAudioToVoiceNote } from '@/lib/audioConvert'
import { credencialMeta } from '@/lib/metaTemplates'
import { enderecoParaFora } from '@/lib/armazem'

/**
 * A credencial da API oficial para mandar TEXTO e MÍDIA -- a mesma dos templates.
 *
 * Até 28/09 esta função só olhava `integration_secrets`, e o token nunca esteve
 * lá: gravar segredo ali é barrado, e ele mora no .env (META_TOKEN), que é de
 * onde a tela de Templates sempre leu (`credencialMeta`). Resultado: o template
 * saía, mas responder a conversa da aba API Oficial pelo chat falhava sempre com
 * "Integração com WhatsApp incompleta" (Pedro: "quando clico em um chat da api
 * oficial não dá para mandar msg pra ele"). Agora é uma credencial só, na mesma
 * ordem: a do banco se existir, senão a do .env.
 */
export async function getWhatsAppCredentials(organizationId: string) {
  const cred = await credencialMeta(organizationId)
  if (!cred?.token || !cred.phoneNumberId) {
    throw { status: 400, message: 'Integração com WhatsApp incompleta (faltando phone_number_id ou token).' }
  }
  return {
    apiVersion: cred.versao || 'v21.0',
    phoneNumberId: cred.phoneNumberId,
    token: cred.token,
  }
}

export async function sendWhatsAppMessage(organizationId: string, phone: string, content: string, replyToMessageId?: string | null) {
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
      ...(replyToMessageId ? { context: { message_id: replyToMessageId } } : {}),
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

  // a Meta baixa sem sessão: endereço assinado do armazém (ver src/lib/armazem.ts)
  const mediaPayload: Record<string, any> = { link: enderecoParaFora(effectiveMediaUrl) }
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
