import { NextRequest } from 'next/server'
import { apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, leadActivities, pipelineStages, integrationMessageLogs } from '@/lib/schema'
import { eq, and, isNull, ilike, asc, sql } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { isUniqueViolation } from '@/lib/db-helpers'

const ORGANIZATION_ID = '91a7f4af-9e58-4e30-906b-b0ebc9386da4'

/**
 * POST /api/webhooks/n8n-outbound
 * Webhook para registrar no CRM mensagens já enviadas pelo WhatsApp via n8n.
 *
 * Sem autenticação (uso interno). Tolerante a payloads desformatados:
 * - aceita JSON inválido/vazio
 * - aceita array (usa o primeiro item)
 * - aceita tanto { phone, content, ... } quanto a resposta crua da API do
 *   WhatsApp (com "contacts"/"messages"), extraindo phone/content/whatsapp_message_id
 *   de vários formatos possíveis
 */
export async function POST(req: NextRequest) {
  const raw = await req.text()

  let parsed: any = null
  let parseError: string | null = null
  try {
    parsed = raw ? JSON.parse(raw) : {}
  } catch (err: any) {
    parseError = `JSON inválido: ${err.message}`
  }

  const body = Array.isArray(parsed) ? (parsed[0] ?? {}) : (parsed ?? {})

  const rawPhone =
    body.phone ??
    body.wa_id ??
    body.contacts?.[0]?.wa_id ??
    body.contacts?.[0]?.input ??
    body.messages?.[0]?.from ??
    null

  const content =
    body.content ??
    body.text ??
    body.message ??
    body.messages?.[0]?.text?.body ??
    body.messages?.[0]?.template?.name ??
    null

  const phone = rawPhone != null ? String(rawPhone).replace(/\D/g, '') : ''

  const senderName = body.sender_name || body.contacts?.[0]?.profile?.name || null

  const whatsappMessageId =
    body.whatsapp_message_id ??
    body.messages?.[0]?.id ??
    body.message_id ??
    null

  const messageStatus =
    body.message_status ??
    body.messages?.[0]?.message_status ??
    null

  try {
    if (parseError) throw { status: 200, message: parseError }

    // Atualização de status (ex: "accepted"/"delivered"/"read"), sem conteúdo novo:
    // apenas atualiza a mensagem existente pelo whatsapp_message_id, sem criar lead/atividade.
    if (!content && whatsappMessageId) {
      const [activity] = await db.select({ id: leadActivities.id, leadId: leadActivities.leadId, metadata: leadActivities.metadata })
        .from(leadActivities)
        .where(sql`${leadActivities.metadata}->>'whatsapp_message_id' = ${whatsappMessageId}`)
        .limit(1)

      if (activity) {
        await db.update(leadActivities)
          .set({ metadata: { ...(activity.metadata as object), whatsapp_status: messageStatus } })
          .where(eq(leadActivities.id, activity.id))
        await publishEvent(channels.leadActivities(activity.leadId), events.ACTIVITY_UPDATED, { id: activity.id })
      }

      await db.insert(integrationMessageLogs).values({
        organizationId: ORGANIZATION_ID,
        source: 'n8n',
        direction: 'outbound',
        phone: phone || null,
        content: null,
        leadId: activity?.leadId,
        status: 'success',
        payload: { raw, parsed },
      })

      return Response.json({ status: 'ok', updated: !!activity })
    }

    if (!phone) throw { status: 200, message: 'Não foi possível identificar o telefone (phone) na mensagem. Nenhum lead foi atualizado.' }
    if (!content) throw { status: 200, message: 'Não foi possível identificar o conteúdo (content) da mensagem. Nenhum lead foi atualizado.' }

    const [existing] = await db.select({ id: leads.id, title: leads.title })
      .from(leads)
      .where(and(eq(leads.organizationId, ORGANIZATION_ID), ilike(leads.phone, `%${phone}%`), isNull(leads.deletedAt)))
      .limit(1)

    let leadId = existing?.id
    if (!leadId) {
      const [firstStage] = await db.select({ id: pipelineStages.id }).from(pipelineStages)
        .where(and(eq(pipelineStages.organizationId, ORGANIZATION_ID), isNull(pipelineStages.deletedAt)))
        .orderBy(asc(pipelineStages.rank)).limit(1)

      try {
        const [newLead] = await db.insert(leads).values({
          organizationId: ORGANIZATION_ID,
          title: senderName || phone,
          phone,
          stageId: firstStage?.id || null,
          lastActivityAt: new Date(),
          customAttributes: { source: 'n8n' },
        }).returning({ id: leads.id })
        leadId = newLead.id
      } catch (err) {
        // Mesma race condition dos outros webhooks: duas chamadas quase simultâneas pro
        // mesmo telefone, cada uma criava seu próprio lead sem constraint. Agora
        // leads_org_phone_unique garante que só uma vence.
        if (!isUniqueViolation(err)) throw err
        const [raceLead] = await db.select({ id: leads.id }).from(leads)
          .where(and(eq(leads.organizationId, ORGANIZATION_ID), eq(leads.phone, phone), isNull(leads.deletedAt)))
          .limit(1)
        if (!raceLead) throw err
        leadId = raceLead.id
      }
    }

    let activity: { id: string }
    try {
      ;[activity] = await db.insert(leadActivities).values({
        organizationId: ORGANIZATION_ID,
        leadId,
        type: 'whatsapp',
        content,
        metadata: {
          source: 'n8n',
          direction: 'outbound',
          send_status: 'sent',
          sender_name: senderName,
          whatsapp_message_id: whatsappMessageId,
          whatsapp_status: messageStatus,
        },
      }).returning({ id: leadActivities.id })
    } catch (err) {
      // Reenvio do mesmo webhook do n8n (retry, replay manual) — antes duplicava
      // incondicionalmente quando havia conteúdo (só o ramo de status-sem-conteúdo,
      // acima, tinha alguma checagem). lead_activities_whatsapp_msgid_unique cobre isso.
      if (!isUniqueViolation(err)) throw err
      return Response.json({ status: 'ok', skipped: 'duplicate' })
    }

    const leadUpdates: any = {
      lastMessageContent: content,
      lastMessageSenderType: 'human',
      lastActivityAt: new Date(),
      isUnread: false,
    }

    // Ao responder o lead, move a conversa para o pipeline "Em atendimento"
    const [emAtendimento] = await db.select({ id: pipelineStages.id }).from(pipelineStages)
      .where(and(eq(pipelineStages.organizationId, ORGANIZATION_ID), isNull(pipelineStages.deletedAt), ilike(pipelineStages.name, 'Em atendimento')))
      .limit(1)
    if (emAtendimento) leadUpdates.stageId = emAtendimento.id

    await db.update(leads).set(leadUpdates).where(eq(leads.id, leadId))

    await publishEvent(channels.leadActivities(leadId), events.ACTIVITY_CREATED, { id: activity.id })
    await publishEvent(channels.orgLeads(ORGANIZATION_ID), events.LEAD_UPDATED, { id: leadId })

    await db.insert(integrationMessageLogs).values({
      organizationId: ORGANIZATION_ID,
      source: 'n8n',
      direction: 'outbound',
      phone,
      content,
      leadId,
      status: 'success',
      payload: { raw, parsed },
    })

    return Response.json({ status: 'ok', lead_id: leadId, activity_id: activity.id })
  } catch (err: any) {
    await db.insert(integrationMessageLogs).values({
      organizationId: ORGANIZATION_ID,
      source: 'n8n',
      direction: 'outbound',
      phone: phone || null,
      content: content != null ? String(content) : null,
      status: 'error',
      error: err.message || 'Erro interno.',
      payload: { raw, parsed },
    }).catch(() => {})
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
