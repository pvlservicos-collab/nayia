import { db } from './db'
import { integrations, integrationSecrets } from './schema'
import { eq, and, isNull } from 'drizzle-orm'

async function getEvolutionCredentials(organizationId: string) {
  const [integration] = await db
    .select({ id: integrations.id, config: integrations.config })
    .from(integrations)
    .where(
      and(
        eq(integrations.organizationId, organizationId),
        eq(integrations.type, 'whatsapp_evolution'),
        isNull(integrations.deletedAt)
      )
    )
    .limit(1)

  if (!integration) throw new Error('Integração Evolution não configurada.')

  const [secretRow] = await db
    .select({ secret: integrationSecrets.secret })
    .from(integrationSecrets)
    .where(eq(integrationSecrets.integrationId, integration.id))
    .limit(1)

  const instanceName = (integration.config as any)?.instanceName
  const apiKey = (secretRow?.secret as any)?.api_key || process.env.EVOLUTION_API_KEY
  const server = process.env.EVOLUTION_API_URL

  if (!instanceName) throw new Error('Nome da instância Evolution não configurado.')
  if (!server) throw new Error('EVOLUTION_API_URL não configurada.')

  return { instanceName, apiKey, server }
}

/**
 * A URL que vem no payload do webhook (`msg.imageMessage.url` etc.) aponta pro CDN
 * criptografado do WhatsApp (`mmg.whatsapp.net/.../*.enc`) — só abre com a mediaKey,
 * que não temos aqui, e ainda expira em poucos dias. Por isso pedimos pra própria
 * Evolution API decriptar (ela tem a mediaKey da instância) e devolver em base64,
 * pra então re-hospedar num link estável no Blob — igual já fazemos com WhatsApp
 * Cloud API e Instagram.
 */
export async function downloadEvolutionMedia(
  organizationId: string,
  key: { id: string; remoteJid: string; fromMe?: boolean }
): Promise<{ url: string; mimetype?: string } | null> {
  try {
    const { instanceName, apiKey, server } = await getEvolutionCredentials(organizationId)

    // A Evolution/Baileys indexa mensagens no armazenamento dela pela chave completa
    // (remoteJid + fromMe + id), não só pelo id — mandar só o id fazia a busca falhar
    // sistematicamente pra mensagens enviadas (fromMe: true), porque o registro sem
    // fromMe explícito não batia com o que estava guardado. Sempre reenvia a key
    // original recebida no próprio payload do webhook, não uma reconstrução parcial.
    const res = await fetch(`${server}/chat/getBase64FromMediaMessage/${instanceName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: apiKey },
      body: JSON.stringify({ message: { key }, convertToMp4: false }),
    })
    if (!res.ok) return null

    const data = await res.json().catch(() => null)
    const base64: string | undefined = data?.base64
    if (!base64) return null

    const mimetype = data?.mimetype || 'application/octet-stream'
    const buffer = Buffer.from(base64, 'base64')

    const { put } = await import('@vercel/blob')
    const ext = mimetype.split('/')[1]?.split(';')[0] || 'bin'
    const blob = await put(`evolution-media/${organizationId}/${key.id}.${ext}`, buffer, {
      access: 'public',
      contentType: mimetype,
    })

    return { url: blob.url, mimetype }
  } catch (err) {
    console.error('[Evolution] media download failed', err)
    return null
  }
}

/**
 * Busca a foto de perfil do contato via Evolution API e re-hospeda no Blob — mesmo
 * padrão de downloadEvolutionMedia acima. A Evolution respeita a configuração de
 * privacidade de cada contato (retorna vazio se a pessoa não permite ver a foto), igual
 * o próprio WhatsApp Web faria; nesse caso a função retorna null sem erro.
 */
export async function fetchEvolutionProfilePicture(
  organizationId: string,
  phone: string
): Promise<string | null> {
  try {
    const { instanceName, apiKey, server } = await getEvolutionCredentials(organizationId)

    const res = await fetch(`${server}/chat/fetchProfilePictureUrl/${instanceName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: apiKey },
      body: JSON.stringify({ number: phone }),
    })
    if (!res.ok) return null

    const data = await res.json().catch(() => null)
    const pictureUrl: string | undefined = data?.profilePictureUrl
    if (!pictureUrl || typeof pictureUrl !== 'string') return null

    const imgRes = await fetch(pictureUrl)
    if (!imgRes.ok) return null

    const mimetype = imgRes.headers.get('content-type') || 'image/jpeg'
    const buffer = Buffer.from(await imgRes.arrayBuffer())

    const { put } = await import('@vercel/blob')
    const ext = mimetype.split('/')[1]?.split(';')[0] || 'jpg'
    const blob = await put(`evolution-avatars/${organizationId}/${phone}-${Date.now()}.${ext}`, buffer, {
      access: 'public',
      contentType: mimetype,
    })

    return blob.url
  } catch (err) {
    console.error('[Evolution] profile picture fetch failed', err)
    return null
  }
}

/** Grupo precisa do JID completo (`<id>@g.us`); contato usa só os dígitos do telefone. */
function formatRecipient(phone: string, isGroup?: boolean) {
  const digits = phone.replace(/\D/g, '')
  return isGroup ? `${digits}@g.us` : digits
}

/**
 * Em erro, a Evolution normalmente responde com o motivo real em `response.message`
 * (ex: `["Error: Connection Closed"]`), não em `data.message` — usar só `data.message`
 * fazia esses erros caírem sempre no texto genérico de fallback, escondendo a causa
 * real (ex: instância deslogada) tanto do log quanto do `lead_activities.metadata`.
 */
function extractEvolutionError(data: any, fallback: string): string {
  const responseMessage = data?.response?.message
  if (Array.isArray(responseMessage) && responseMessage.length > 0) return responseMessage.join('; ')
  if (typeof responseMessage === 'string' && responseMessage) return responseMessage
  if (typeof data?.message === 'string' && data.message) return data.message
  return fallback
}

export async function sendEvolutionMessage(
  organizationId: string,
  phone: string,
  text: string,
  isGroup?: boolean
) {
  const { instanceName, apiKey, server } = await getEvolutionCredentials(organizationId)
  const formattedPhone = formatRecipient(phone, isGroup)

  const res = await fetch(`${server}/message/sendText/${instanceName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: apiKey },
    body: JSON.stringify({ number: formattedPhone, text }),
  })

  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(extractEvolutionError(data, 'Falha ao enviar mensagem via Evolution'))
  return data
}

export async function sendEvolutionMedia(
  organizationId: string,
  phone: string,
  mediaType: string,
  mediaUrl: string,
  caption?: string,
  fileName?: string,
  isGroup?: boolean
) {
  const { instanceName, apiKey, server } = await getEvolutionCredentials(organizationId)
  const formattedPhone = formatRecipient(phone, isGroup)

  // Áudio (nota de voz) precisa do endpoint dedicado: é ele quem converte o arquivo de
  // origem (ex: .webm gravado no navegador) para o OGG/Opus que o WhatsApp exige pra tocar
  // como balão de áudio. O endpoint genérico de mídia abaixo aceita a chamada e retorna
  // sucesso, mas a mensagem não chega tocável no destinatário quando o arquivo não é
  // ogg/opus — foi exatamente isso que aconteceu com os áudios gravados pelo app.
  if (mediaType === 'audio') {
    const res = await fetch(`${server}/message/sendWhatsAppAudio/${instanceName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: apiKey },
      body: JSON.stringify({ number: formattedPhone, audio: mediaUrl }),
    })

    const data = await res.json().catch(() => ({}))
    if (!res.ok) throw new Error(extractEvolutionError(data, 'Falha ao enviar áudio via Evolution'))
    return data
  }

  const evoMediaType =
    mediaType === 'image' ? 'image' :
    mediaType === 'video' ? 'video' : 'document'

  const res = await fetch(`${server}/message/sendMedia/${instanceName}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: apiKey },
    body: JSON.stringify({
      number: formattedPhone,
      mediatype: evoMediaType,
      media: mediaUrl,
      caption: caption || '',
      fileName: fileName || '',
    }),
  })

  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(extractEvolutionError(data, 'Falha ao enviar mídia via Evolution'))
  return data
}

/**
 * Apaga a mensagem "para todos" (revoke) — só existe pra Evolution porque ela fala o
 * protocolo real do WhatsApp (Baileys); a Cloud API oficial da Meta não expõe essa
 * operação pra mensagens enviadas por negócios (ver ChannelAdapter.deleteMessage).
 */
export async function deleteEvolutionMessage(
  organizationId: string,
  phone: string,
  messageId: string,
  isGroup?: boolean
) {
  const { instanceName, apiKey, server } = await getEvolutionCredentials(organizationId)
  const formattedPhone = formatRecipient(phone, isGroup)

  const res = await fetch(`${server}/chat/deleteMessageForEveryone/${instanceName}`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json', apikey: apiKey },
    body: JSON.stringify({
      id: messageId,
      remoteJid: formattedPhone,
      fromMe: true,
    }),
  })

  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error(extractEvolutionError(data, 'Falha ao apagar mensagem via Evolution'))
  return data
}
