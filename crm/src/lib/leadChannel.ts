import type { LeadWithOwner } from '@/lib/types'

export type LeadChannel = 'whatsapp' | 'instagram' | 'other'

/**
 * Deriva o canal de uma conversa a partir do tipo da integração associada.
 * Sem integration.type (não veio via JOIN) mas com integration_id, assume
 * WhatsApp — mesmo fallback já usado em IntegrationBadge, já que hoje toda
 * integração sem tipo mapeado é WhatsApp Lite.
 */
export function getLeadChannel(lead: LeadWithOwner): LeadChannel {
  const type = lead.integration?.type
  if (!type) return lead.integration_id ? 'whatsapp' : 'other'
  if (type === 'instagram_direct') return 'instagram'
  if (type.includes('whatsapp')) return 'whatsapp'
  return 'other'
}

/**
 * As TRÊS LINHAS DE WHATSAPP da Imob Easy, uma aba cada (Tel, 28/09/2026):
 * "São 3 WhatsApp, cada um em uma tab lá no CRM: API oficial com as coisas que
 * recebemos só da API oficial, a de parceria que já está lá certinho, e o
 * número de captação, que é o outro, em outra instância da Z-API... preciso
 * das 3 lá funcionais, e não misturando contatos".
 *
 *   oficial   -- (92) 8456-0874, API Oficial da Meta (Cloud API).
 *   parceria  -- (92) 9445-3618, Z-API, onde a Nay atende corretor parceiro.
 *   captacao  -- (92) 8595-6408, Z-API, o WhatsApp da Imob Easy e da captação.
 *
 * A conversa sabe de qual linha é pelo TIPO da integração -- e não pelo
 * número -- porque o número muda e o tipo não. E cada lead é de UMA linha só:
 * a mesma pessoa falando com dois números são duas conversas, uma em cada aba
 * (ver `leadDaLinha.ts`).
 *
 * Até 28/09 a aba "captação" era a da API Oficial; o nome passou para a Z-API
 * da captação, que é como o Tel chama esse número.
 */
export type LinhaWhatsapp = 'oficial' | 'parceria' | 'captacao'

export const LINHA_DO_TIPO: Record<string, LinhaWhatsapp> = {
  whatsapp_cloud_official: 'oficial',
  whatsapp_zapi: 'parceria',
  whatsapp_zapi_captacao: 'captacao',
}

/** O endereço da aba de cada linha. */
export const CAMINHO_DA_LINHA: Record<LinhaWhatsapp, string> = {
  oficial: '/chat',
  parceria: '/chat/parceria',
  captacao: '/chat/captacao',
}

/** A linha de um tipo de integração, ou null quando o tipo não é WhatsApp. */
export function linhaDoTipo(type: string | null | undefined): LinhaWhatsapp | null {
  return (type && LINHA_DO_TIPO[type]) || null
}

export function getLinhaWhatsapp(lead: LeadWithOwner): LinhaWhatsapp | null {
  const doTipo = linhaDoTipo(lead.integration?.type)
  if (doTipo) return doTipo
  // Sem tipo (nao veio pelo JOIN) mas com integracao: cai na parceria, que e
  // a linha que ja existia antes das abas. Assim nenhuma conversa antiga some
  // da tela enquanto a integracao nova nao esta configurada.
  if (!lead.integration?.type && lead.integration_id) return 'parceria'
  return null
}

/**
 * A linha desta conversa, numa lista (a forma que as abas e a busca usam).
 *
 * De 26/09 a 28/09 isto juntava as linhas de TODAS as mensagens do lead, para
 * a mesma conversa aparecer em mais de uma aba. Era o remendo de um lead só
 * por telefone, e misturava: a mesma conversa em duas abas, e a resposta saía
 * pelo número da última mensagem, não pelo da aba. Agora cada lead é de uma
 * linha, e a conversa aparece só na dela.
 */
export function linhasDaConversa(lead: LeadWithOwner): LinhaWhatsapp[] {
  const doServidor = lead.linhas
  if (Array.isArray(doServidor) && doServidor.length > 0) return doServidor
  const unica = getLinhaWhatsapp(lead)
  return unica ? [unica] : []
}

export function conversaEstaNaLinha(lead: LeadWithOwner, linha: LinhaWhatsapp): boolean {
  return linhasDaConversa(lead).includes(linha)
}
