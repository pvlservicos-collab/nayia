import { sendZapiMessage, sendZapiMedia, deleteZapiMessage } from '@/lib/zapi'
import type { ChannelAdapter } from './types'

/**
 * Z-API como canal do CRM.
 *
 * `supportsGroups: true`: a Z-API endereça grupo pelo mesmo campo `phone`,
 * usando o id do grupo ("1203...-group") no lugar do número — que é exatamente
 * o valor que a entrada guarda em `leads.phone` pra conversa de grupo. Então
 * responder um grupo é o mesmo caminho de responder uma pessoa.
 */
export const zapiAdapter: ChannelAdapter = {
  metadataIdKey: 'zapi_message_id',
  supportsGroups: true,

  async sendText(organizationId, _integrationId, recipient, content) {
    const { data, telefone } = await sendZapiMessage(organizationId, recipient, content)
    return { externalId: data?.messageId || data?.id, raw: data, recipienteCorrigido: telefone }
  },

  async sendMedia(organizationId, _integrationId, recipient, mediaType, mediaUrl, caption, filename) {
    const { data, telefone } = await sendZapiMedia(organizationId, recipient, mediaType, mediaUrl, caption, filename)
    return { externalId: data?.messageId || data?.id, raw: data, recipienteCorrigido: telefone }
  },

  async deleteMessage(organizationId, _integrationId, recipient, externalMessageId) {
    await deleteZapiMessage(organizationId, recipient, externalMessageId, true)
  },
}
