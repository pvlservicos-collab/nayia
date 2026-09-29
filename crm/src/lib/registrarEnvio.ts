/**
 * Grava no CRM uma mensagem que NÓS mandamos por fora do chat.
 *
 * Tel, 26/09/2026: "não apareceu a conversa criada ao enviar os templates no
 * crm, isso tem que aparecer, mesmo que seja a gnt mesmo criando pq a meta não
 * nos avisa disso né, tem que criar automaticamente toda mensagem enviada por
 * nos no crm".
 *
 * POR QUE ISTO PRECISA EXISTIR. A Meta só chama o nosso webhook para o que
 * CHEGA e para o status do que saiu (accepted/delivered/read) -- e o status vem
 * sem o texto. Quem manda pela Cloud API fora do chat (a tela de Templates, o
 * n8n, a Nay) é o único que sabe o que foi dito. Se não escrever aqui na hora,
 * ninguém escreve nunca: a conversa nasce só quando a pessoa responde, e a
 * primeira mensagem -- a nossa -- desaparece da história.
 *
 * A Z-API é diferente: ela devolve a nossa própria mensagem no webhook com
 * `fromMe`, e o `zapiInbound` já grava. Esta função é para quem não tem esse eco.
 *
 * SEMPRE NO LEAD DA LINHA POR ONDE SAIU. Cada lead é de uma linha só (ver
 * `leadDaLinha.ts`): o template da API oficial vai para a conversa da aba
 * oficial, mesmo que a mesma pessoa converse todo dia na Parceria. Um lead sem
 * integração não aparece em aba nenhuma, o que é pior que não existir, porque
 * fica invisível sem erro.
 */
import { eq } from 'drizzle-orm'
import { db } from './db'
import { leadActivities, leads } from './schema'
import { ehEspelhoDeTreino, telefoneVariantes } from './leadSources'
import { etapaInicialDaLinha } from './etapaDaLinha'
import { isUniqueViolation } from './db-helpers'
import { channels, events, publishEvent } from './realtime'
import { acharLeadDaLinha, integracaoDoTipo } from './leadDaLinha'
import { linhaDoTipo, type LinhaWhatsapp } from './leadChannel'

export type CanalDeEnvio = 'whatsapp_cloud_official' | 'whatsapp_zapi' | 'whatsapp_zapi_captacao'

export interface EnvioRegistrado {
  leadId: string
  activityId: string | null
  criouLead: boolean
  /** true quando a mensagem já estava gravada (mesmo id da Meta / Z-API) */
  duplicado: boolean
  /** a linha em que a conversa vai aparecer no chat */
  linha: LinhaWhatsapp
}

export async function registrarEnvioNoCrm(p: {
  organizationId: string
  telefone: string
  texto: string
  canal: CanalDeEnvio
  memberId?: string | null
  nomeSugerido?: string | null
  whatsappMessageId?: string | null
  zapiMessageId?: string | null
  /** metadata.source -- de onde partiu o envio ('templates', 'n8n', 'nay'...) */
  origem?: string
  extraMetadata?: Record<string, any>
}): Promise<EnvioRegistrado> {
  const variantes = telefoneVariantes(p.telefone)
  const canonico = variantes[0]
  if (!canonico) throw { status: 400, message: 'Telefone inválido para registrar no CRM.' }

  // Espelho da bateria de treino nunca vira conversa aqui -- o mesmo motivo do
  // guarda no `zapiInbound`: a rodada de treino conversa pelo fluxo real, e o
  // CRM não é lugar de guardar cliente inventado.
  if (ehEspelhoDeTreino(canonico)) {
    throw { status: 400, message: 'Telefone de espelho de treino: não entra no CRM.' }
  }

  // A integração da linha por onde a mensagem saiu. Sem ela o lead ficaria fora
  // das abas (ver o comentário no topo).
  const linhaId = await integracaoDoTipo(p.organizationId, p.canal)

  // O lead DESTA linha; o telefone pode estar gravado com ou sem o nono
  // dígito, e o `acharLeadDaLinha` procura as duas formas.
  const achado = await acharLeadDaLinha(p.organizationId, variantes, linhaId)

  let leadId = achado?.id
  let criouLead = false

  if (!leadId) {
    // A etapa do pipeline DA LINHA, não a primeira da organização -- os dois
    // pipelines têm etapa de rank 1 e o banco devolvia qualquer uma.
    const etapa = await etapaInicialDaLinha(p.organizationId, p.canal)

    try {
      const [novo] = await db.insert(leads).values({
        organizationId: p.organizationId,
        title: p.nomeSugerido?.trim() || canonico,
        phone: canonico,
        integrationId: linhaId,
        stageId: etapa,
        lastActivityAt: new Date(),
        customAttributes: { source: p.origem || 'envio_nosso' },
      }).returning({ id: leads.id })
      leadId = novo.id
      criouLead = true
    } catch (err) {
      // Duas chamadas quase simultâneas para o mesmo telefone: o índice
      // leads_org_phone_unique (telefone + linha) deixa uma passar, e a outra
      // usa o que venceu.
      if (!isUniqueViolation(err)) throw err
      const corrida = await acharLeadDaLinha(p.organizationId, variantes, linhaId)
      if (!corrida) throw err
      leadId = corrida.id
    }
  }
  // (O lead sem linha nenhuma é adotado por esta dentro do `acharLeadDaLinha`.)

  const metadata: Record<string, any> = {
    source: p.origem || 'envio_nosso',
    direction: 'outbound',
    channel: p.canal,
    send_status: 'sent',
    ...(p.extraMetadata || {}),
  }
  if (p.whatsappMessageId) metadata.whatsapp_message_id = p.whatsappMessageId
  if (p.zapiMessageId) metadata.zapi_message_id = p.zapiMessageId

  let activityId: string | null = null
  let duplicado = false
  try {
    const [atividade] = await db.insert(leadActivities).values({
      organizationId: p.organizationId,
      leadId: leadId!,
      actorMemberId: p.memberId || null,
      type: 'whatsapp',
      content: p.texto,
      metadata,
    }).returning({ id: leadActivities.id })
    activityId = atividade.id
  } catch (err) {
    // O mesmo id da Meta chegando duas vezes (retry, replay do webhook de
    // status): os índices únicos de whatsapp_message_id / zapi_message_id
    // impedem a mensagem repetida na timeline.
    if (!isUniqueViolation(err)) throw err
    duplicado = true
  }

  if (!duplicado) {
    await db.update(leads).set({
      lastMessageContent: p.texto,
      lastMessageSenderType: 'human',
      lastActivityAt: new Date(),
      lastActivityType: 'whatsapp',
      lastActivityByMemberId: p.memberId || null,
      isUnread: false,
    }).where(eq(leads.id, leadId!))

    // Sem isto a conversa só aparece depois de recarregar a página.
    await publishEvent(channels.leadActivities(leadId!), events.ACTIVITY_CREATED, { id: activityId })
    await publishEvent(channels.orgLeads(p.organizationId), events.LEAD_UPDATED, { id: leadId })
  }

  return {
    leadId: leadId!,
    activityId,
    criouLead,
    duplicado,
    linha: linhaDoTipo(p.canal) ?? 'parceria',
  }
}

/**
 * O texto que vai para a timeline quando o que saiu foi um template.
 *
 * O corpo aprovado tem `{{1}}` / `{{name}}`; quem lê a conversa no CRM precisa
 * ver a frase que a pessoa recebeu, não o molde. Então os valores entram no
 * lugar dos buracos, na ordem.
 */
export function textoDoTemplate(corpo: string, valores: string[]): string {
  let i = 0
  const preenchido = (corpo || '').replace(/\{\{\s*[^}\s]+\s*\}\}/g, () => {
    const v = valores[i]
    i += 1
    return v || '…'
  })
  return preenchido
}
