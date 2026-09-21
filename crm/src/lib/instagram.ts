import { db } from '@/lib/db'
import { integrations, integrationSecrets } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'
import { convertAudioToVoiceNote } from '@/lib/audioConvert'

/**
 * Uma organização pode ter várias contas do Instagram conectadas — por isso
 * a busca é sempre pela integração específica (integrationId), nunca só por
 * organizationId+type como no WhatsApp Cloud (que é singleton por org).
 */
async function getInstagramCredentials(organizationId: string, integrationId: string) {
  const [integration] = await db.select({ id: integrations.id, config: integrations.config })
    .from(integrations)
    .where(and(
      eq(integrations.id, integrationId),
      eq(integrations.organizationId, organizationId),
      eq(integrations.type, 'instagram_direct'),
      isNull(integrations.deletedAt),
    ))
    .limit(1)

  if (!integration) throw { status: 400, message: 'Integração com Instagram não encontrada ou desconectada.' }

  const [secretRow] = await db.select({ secret: integrationSecrets.secret })
    .from(integrationSecrets)
    .where(eq(integrationSecrets.integrationId, integration.id))
    .limit(1)

  const config = integration.config as { instagram_business_account_id?: string; graph_api_version?: string }
  const secret = secretRow?.secret as { system_token?: string } | undefined

  if (!config?.instagram_business_account_id || !secret?.system_token) {
    throw { status: 400, message: 'Integração com Instagram incompleta (faltando instagram_business_account_id ou token).' }
  }

  return {
    apiVersion: config.graph_api_version || 'v21.0',
    igUserId: config.instagram_business_account_id,
    token: secret.system_token,
  }
}

/**
 * recipientId é o IGSID (Instagram-scoped ID) do usuário, não um telefone —
 * Instagram Direct não tem conceito de telefone.
 */
export async function sendInstagramMessage(organizationId: string, integrationId: string, recipientId: string, content: string) {
  const { apiVersion, igUserId, token } = await getInstagramCredentials(organizationId, integrationId)

  // Tokens gerados via "API do Instagram com login do Instagram" (não Facebook Login)
  // só são reconhecidos em graph.instagram.com — graph.facebook.com responde
  // "Cannot parse access token" para esse tipo de token.
  const res = await fetch(`https://graph.instagram.com/${apiVersion}/${igUserId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      recipient: { id: recipientId },
      message: { text: content },
    }),
  })

  const data = await res.json().catch(() => ({}))

  if (!res.ok) {
    // Fora da janela de resposta de 24h ou rate limit (~200 msgs/hora) chegam
    // aqui como erro da Graph API — propaga a mensagem original da Meta.
    const errMsg = data?.error?.message || `Falha ao enviar mensagem (HTTP ${res.status})`
    throw { status: 502, message: errMsg, details: data }
  }

  return data
}

/**
 * Busca nome, @usuário e foto de perfil de quem mandou mensagem (pelo IGSID) —
 * usado só pra exibir a conversa de forma legível no CRM, nunca falha o
 * recebimento da mensagem em si (retorna null em qualquer erro).
 */
export async function getInstagramUserProfile(organizationId: string, integrationId: string, igsid: string) {
  try {
    const { apiVersion, token } = await getInstagramCredentials(organizationId, integrationId)

    const res = await fetch(`https://graph.instagram.com/${apiVersion}/${igsid}?fields=name,username,profile_pic&access_token=${encodeURIComponent(token)}`)
    if (!res.ok) return null

    const data = await res.json()
    return {
      name: data.name as string | undefined,
      username: data.username as string | undefined,
      profilePic: data.profile_pic as string | undefined,
    }
  } catch {
    return null
  }
}

/**
 * A Instagram Messaging API não aceita texto + anexo na mesma mensagem (diferente
 * do WhatsApp Cloud API) — caption é ignorada aqui; se necessário, envie como
 * mensagem de texto separada antes da mídia.
 */
export async function sendInstagramMedia(
  organizationId: string,
  integrationId: string,
  recipientId: string,
  mediaType: 'image' | 'video' | 'audio' | 'document' | 'sticker',
  mediaUrl: string
) {
  const { apiVersion, igUserId, token } = await getInstagramCredentials(organizationId, integrationId)

  const attachmentType = mediaType === 'document' ? 'file' : mediaType === 'sticker' ? 'image' : mediaType

  // Mesma restrição de formato da Meta que afeta o WhatsApp Cloud API — o navegador
  // grava em webm, que não é aceito; remuxa pra Ogg/Opus antes de enviar.
  const effectiveMediaUrl = mediaType === 'audio' ? await convertAudioToVoiceNote(mediaUrl) : mediaUrl

  const res = await fetch(`https://graph.instagram.com/${apiVersion}/${igUserId}/messages`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      recipient: { id: recipientId },
      message: { attachment: { type: attachmentType, payload: { url: effectiveMediaUrl } } },
    }),
  })

  const data = await res.json().catch(() => ({}))

  if (!res.ok) {
    const errMsg = data?.error?.message || `Falha ao enviar mídia (HTTP ${res.status})`
    throw { status: 502, message: errMsg, details: data }
  }

  return data
}
