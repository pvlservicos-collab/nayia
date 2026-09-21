import type { ChannelAdapter } from './types'
import { whatsappCloudAdapter } from './whatsappCloud'
import { evolutionAdapter } from './evolution'
import { instagramAdapter } from './instagram'
import { zapiAdapter } from './zapi'

/**
 * Qualquer tipo de integração não mapeado explicitamente (whatsapp_cloud_official,
 * whatsapp_lite, desconhecido, ausente) cai no adapter da Cloud API — mesmo
 * fallback que já existia no if/else original, preservado para não mudar
 * comportamento de leads com integração não mapeada.
 */
export function getChannelAdapter(integrationType: string | null | undefined): ChannelAdapter {
  if (integrationType === 'whatsapp_zapi') return zapiAdapter
  if (integrationType === 'whatsapp_evolution') return evolutionAdapter
  if (integrationType === 'instagram_direct') return instagramAdapter
  return whatsappCloudAdapter
}

/**
 * O canal de DISPARO e AUTOMAÇÃO — sempre a Z-API.
 *
 * Resposta manual segue o canal por onde o lead falou (getChannelAdapter acima):
 * quem escreveu no número da Evolution recebe resposta pela Evolution, senão a
 * conversa apareceria pra pessoa vindo de um número que ela não conhece.
 *
 * Mensagem que o SISTEMA inicia é outra história: o funil e os disparos saem
 * sempre pelo mesmo número, decidido aqui e não caso a caso. Isso importa porque
 * o primeiro contato é justamente o que a API oficial não deixa fazer sem
 * template aprovado — era por isso que o funil, apontado pra Cloud API, ficava
 * mudo com lead que nunca escreveu antes.
 *
 * É função, e não constante, pra que trocar o canal de automação seja mudar uma
 * linha só, aqui, em vez de caçar chamadas espalhadas.
 */
export function getAutomationAdapter(): ChannelAdapter {
  return zapiAdapter
}
