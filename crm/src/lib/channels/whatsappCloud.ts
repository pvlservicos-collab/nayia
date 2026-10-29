import { sendWhatsAppMessage, sendWhatsAppMedia } from '@/lib/whatsapp'
import type { ChannelAdapter } from './types'

export const whatsappCloudAdapter: ChannelAdapter = {
  metadataIdKey: 'whatsapp_message_id',
  supportsGroups: false,

  async sendText(organizationId, _integrationId, recipient, content, _isGroup, replyToMessageId) {
    const result = await sendWhatsAppMessage(organizationId, recipient, content, replyToMessageId)
    return { externalId: result?.messages?.[0]?.id, raw: result }
  },

  async sendMedia(organizationId, _integrationId, recipient, mediaType, mediaUrl, caption, filename) {
    const result = await sendWhatsAppMedia(
      organizationId,
      recipient,
      mediaType as 'image' | 'video' | 'audio' | 'document' | 'sticker',
      mediaUrl,
      caption,
      filename
    )
    return { externalId: result?.messages?.[0]?.id, raw: result }
  },
}
