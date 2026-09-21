import { sendInstagramMessage, sendInstagramMedia } from '@/lib/instagram'
import type { ChannelAdapter } from './types'

export const instagramAdapter: ChannelAdapter = {
  metadataIdKey: 'instagram_message_id',
  supportsGroups: false,

  async sendText(organizationId, integrationId, recipient, content) {
    if (!integrationId) throw { status: 400, message: 'Lead do Instagram sem integração associada.' }
    const result = await sendInstagramMessage(organizationId, integrationId, recipient, content)
    return { externalId: result?.message_id, raw: result }
  },

  async sendMedia(organizationId, integrationId, recipient, mediaType, mediaUrl) {
    if (!integrationId) throw { status: 400, message: 'Lead do Instagram sem integração associada.' }
    const result = await sendInstagramMedia(
      organizationId,
      integrationId,
      recipient,
      mediaType as 'image' | 'video' | 'audio' | 'document' | 'sticker',
      mediaUrl
    )
    return { externalId: result?.message_id, raw: result }
  },
}
