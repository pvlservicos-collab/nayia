import { sendEvolutionMessage, sendEvolutionMedia, deleteEvolutionMessage } from '@/lib/evolution'
import type { ChannelAdapter } from './types'

export const evolutionAdapter: ChannelAdapter = {
  metadataIdKey: 'evolution_message_id',
  supportsGroups: true,

  async sendText(organizationId, _integrationId, recipient, content, isGroup) {
    const result = await sendEvolutionMessage(organizationId, recipient, content, isGroup)
    return { externalId: result?.key?.id, raw: result }
  },

  async sendMedia(organizationId, _integrationId, recipient, mediaType, mediaUrl, caption, filename, isGroup) {
    const result = await sendEvolutionMedia(organizationId, recipient, mediaType, mediaUrl, caption, filename, isGroup)
    return { externalId: result?.key?.id, raw: result }
  },

  async deleteMessage(organizationId, _integrationId, recipient, externalMessageId, isGroup) {
    await deleteEvolutionMessage(organizationId, recipient, externalMessageId, isGroup)
  },
}
