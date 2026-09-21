import { db } from '@/lib/db'
import { leads, leadActivities, pipelineStages, integrationMessageLogs, tags, leadTags, messageFunnels } from '@/lib/schema'
import { eq, and, isNull, ilike, asc } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { startExecution } from '@/lib/funnel-engine'
import { isUniqueViolation } from '@/lib/db-helpers'

export const ORGANIZATION_ID = 'bdfac9ab-68cd-4434-856c-897199dc267d'

// Pipeline e tag de origem aplicados quando o lead entra via cada webhook automático.
const STAGE_NAME_BY_SOURCE: Record<string, string> = {
  recuperacao: 'Novo Reculperação',
}
const TAG_BY_SOURCE: Record<string, { name: string; color: string }> = {
  recuperacao: { name: 'Recuperação', color: '#f97316' },
}
const FUNNEL_TRIGGER_BY_SOURCE: Record<string, 'novo_pago' | 'novo_recuperacao'> = {
  recuperacao: 'novo_recuperacao',
}

/**
 * Registra no CRM uma mensagem automática (template) como se tivesse sido
 * enviada pelo número oficial da API — sem enviar de fato, pois o disparo
 * real já é feito por outro sistema (ex: API oficial do gateway de pagamento).
 * Cria/atualiza o lead conforme necessário.
 */
export async function sendAutomatedMessage(opts: {
  phone: string
  content: string
  source: string
  raw: string
  parsed: any
}) {
  const { phone, content, source, raw, parsed } = opts

  const [existing] = await db.select({ id: leads.id, title: leads.title })
    .from(leads)
    .where(and(eq(leads.organizationId, ORGANIZATION_ID), ilike(leads.phone, `%${phone}%`), isNull(leads.deletedAt)))
    .limit(1)

  let leadId = existing?.id
  if (!leadId) {
    const stageName = STAGE_NAME_BY_SOURCE[source]
    let stageId: string | null = null
    if (stageName) {
      const [stage] = await db.select({ id: pipelineStages.id }).from(pipelineStages)
        .where(and(eq(pipelineStages.organizationId, ORGANIZATION_ID), isNull(pipelineStages.deletedAt), ilike(pipelineStages.name, stageName)))
        .limit(1)
      stageId = stage?.id || null
    }
    if (!stageId) {
      const [firstStage] = await db.select({ id: pipelineStages.id }).from(pipelineStages)
        .where(and(eq(pipelineStages.organizationId, ORGANIZATION_ID), isNull(pipelineStages.deletedAt)))
        .orderBy(asc(pipelineStages.rank)).limit(1)
      stageId = firstStage?.id || null
    }

    try {
      const [newLead] = await db.insert(leads).values({
        organizationId: ORGANIZATION_ID,
        title: phone,
        phone,
        stageId,
        lastActivityAt: new Date(),
        customAttributes: { source },
      }).returning({ id: leads.id })
      leadId = newLead.id
    } catch (err) {
      // leads_org_phone_unique cobre corrida entre dois webhooks automáticos quase
      // simultâneos pro mesmo telefone (ex: recuperação de carrinho + figurinha liberada
      // chegando juntos).
      if (!isUniqueViolation(err)) throw err
      const [raceLead] = await db.select({ id: leads.id }).from(leads)
        .where(and(eq(leads.organizationId, ORGANIZATION_ID), eq(leads.phone, phone), isNull(leads.deletedAt)))
        .limit(1)
      if (!raceLead) throw err
      leadId = raceLead.id
    }
  }

  // Marca a origem do lead com uma tag visível no painel do contato
  const tagInfo = TAG_BY_SOURCE[source]
  if (tagInfo) {
    let [tag] = await db.select({ id: tags.id }).from(tags)
      .where(and(eq(tags.organizationId, ORGANIZATION_ID), ilike(tags.name, tagInfo.name)))
      .limit(1)
    if (!tag) {
      [tag] = await db.insert(tags).values({
        organizationId: ORGANIZATION_ID,
        name: tagInfo.name,
        color: tagInfo.color,
      }).returning({ id: tags.id })
    }
    await db.insert(leadTags).values({ leadId, tagId: tag.id, organizationId: ORGANIZATION_ID }).onConflictDoNothing()
  }

  const [activity] = await db.insert(leadActivities).values({
    organizationId: ORGANIZATION_ID,
    leadId,
    type: 'whatsapp',
    content,
    metadata: {
      source,
      direction: 'outbound',
      send_status: 'sent',
      automated: true,
    },
  }).returning({ id: leadActivities.id })

  await db.update(leads).set({
    lastMessageContent: content,
    lastMessageSenderType: 'automated',
    lastActivityAt: new Date(),
    // Sem isto a conversa não aparecia na lista do Chat: quem manda pelo CRM
    // grava `last_activity_type`, o funil não gravava, e a lista usa esse
    // marcador. O lead novo só surgia no chat quando ELE respondia.
    lastActivityType: 'whatsapp',
    isUnread: true,
  }).where(eq(leads.id, leadId))

  await publishEvent(channels.leadActivities(leadId), events.ACTIVITY_CREATED, { id: activity.id })
  await publishEvent(channels.orgLeads(ORGANIZATION_ID), events.LEAD_UPDATED, { id: leadId })

  await db.insert(integrationMessageLogs).values({
    organizationId: ORGANIZATION_ID,
    source,
    direction: 'outbound',
    phone,
    content,
    leadId,
    status: 'success',
    payload: { raw, parsed },
  })

  // Dispara funis de mensagens ativos com gatilho correspondente, para leads novos
  if (!existing) {
    const triggerType = FUNNEL_TRIGGER_BY_SOURCE[source]
    if (triggerType) {
      const funnels = await db.select({ id: messageFunnels.id }).from(messageFunnels)
        .where(and(
          eq(messageFunnels.organizationId, ORGANIZATION_ID),
          eq(messageFunnels.trigger, triggerType),
          eq(messageFunnels.isActive, true),
          isNull(messageFunnels.deletedAt),
        ))
      for (const funnel of funnels) {
        await startExecution(funnel.id, ORGANIZATION_ID, leadId)
      }
    }
  }

  return { leadId, activityId: activity.id }
}

/**
 * Extrai o telefone de um payload de webhook de forma tolerante,
 * aceitando vários formatos comuns (n8n, gateways de pagamento, etc).
 */
export function extractPhone(body: any): string {
  const rawPhone =
    body?.phone ??
    body?.telefone ??
    body?.celular ??
    body?.whatsapp ??
    body?.wa_id ??
    body?.customer?.phone ??
    body?.customer?.cellphone ??
    body?.cliente?.telefone ??
    body?.contacts?.[0]?.wa_id ??
    body?.contacts?.[0]?.input ??
    null

  return rawPhone != null ? String(rawPhone).replace(/\D/g, '') : ''
}
