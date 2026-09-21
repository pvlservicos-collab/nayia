/**
 * Aviso num grupo do WhatsApp quando um lead responde a mensagem automática.
 *
 * É o complemento humano do funil: a mensagem da Michele sai sozinha, e a
 * resposta do lead é o momento em que alguém do time precisa entrar na
 * conversa. O som grande avisa quem está com o CRM aberto; o grupo avisa quem
 * está com o celular na mão.
 *
 * Liga e desliga pela configuração da integração Z-API
 * (`integrations.config.aviso_resposta_grupo` = id do grupo, ou ausente). Fica
 * na configuração e não no código porque é temporário por natureza — o pedido
 * foi "por enquanto, depois desativo" — e desligar não pode depender de deploy.
 * A tela da Z-API tem o interruptor.
 */
import { db } from '@/lib/db'
import { integrations, leads } from '@/lib/schema'
import { and, eq, isNull } from 'drizzle-orm'
import { ZAPI_INTEGRATION_TYPE, sendZapiMessage } from '@/lib/zapi'
import { LEAD_SOURCES, isLeadSourceKey } from '@/lib/leadSources'
import { getBaseUrl } from '@/lib/funnel-engine'

/** "5511987654321" → "(11) 98765-4321". */
function telefoneLegivel(phone: string | null): string {
  const d = (phone || '').replace(/\D/g, '')
  const local = d.startsWith('55') && d.length >= 12 ? d.slice(2) : d
  if (local.length === 11) return `(${local.slice(0, 2)}) ${local.slice(2, 7)}-${local.slice(7)}`
  if (local.length === 10) return `(${local.slice(0, 2)}) ${local.slice(2, 6)}-${local.slice(6)}`
  return phone || '—'
}

function fonteDoLead(attrs?: Record<string, unknown> | null): string {
  const chave = String(attrs?.lead_source ?? '')
  return isLeadSourceKey(chave) ? LEAD_SOURCES[chave].label : 'WhatsApp'
}

/**
 * Manda o aviso, se estiver ligado. Nunca lança: é um recado pro time, e
 * falhar aqui não pode derrubar o registro da mensagem do lead, que é o que
 * importa de verdade.
 */
export async function avisarGrupoRespostaAutomacao(
  organizationId: string,
  leadId: string,
  resposta: string
): Promise<void> {
  try {
    // Busca aqui em vez de receber pronto: quem chama (a entrada de mensagem)
    // não carrega custom_attributes, e a fonte do lead vem de lá.
    const [lead] = await db
      .select({ id: leads.id, title: leads.title, phone: leads.phone, customAttributes: leads.customAttributes })
      .from(leads)
      .where(eq(leads.id, leadId))
      .limit(1)
    if (!lead) return

    const [integracao] = await db
      .select({ config: integrations.config })
      .from(integrations)
      .where(and(
        eq(integrations.organizationId, organizationId),
        eq(integrations.type, ZAPI_INTEGRATION_TYPE),
        isNull(integrations.deletedAt)
      ))
      .limit(1)

    const grupo = (integracao?.config as Record<string, unknown> | undefined)?.aviso_resposta_grupo
    if (typeof grupo !== 'string' || !grupo) return // desligado

    // Trecho curto: o grupo é pra chamar atenção, a conversa inteira está no CRM.
    const trecho = resposta.length > 160 ? resposta.slice(0, 157) + '…' : resposta

    const texto = [
      '🔔 *Lead respondeu a mensagem automática*',
      '',
      `👤 ${lead.title || 'Sem nome'}`,
      `📱 ${telefoneLegivel(lead.phone)}`,
      `📍 ${fonteDoLead(lead.customAttributes as Record<string, unknown> | null)}`,
      '',
      `💬 "${trecho}"`,
      '',
      `Abrir no CRM: ${getBaseUrl()}/chat?leadId=${lead.id}`,
    ].join('\n')

    await sendZapiMessage(organizationId, grupo, texto)
  } catch (err) {
    console.error('[aviso-grupo] não consegui avisar o grupo:', err)
  }
}
