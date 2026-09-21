import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired, validateSource } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import {
  leads, leadActivities, pipelineStages, organizationMembers, profiles, notifications,
} from '@/lib/schema'
import { eq, and, isNull, desc, asc, ilike, sql } from 'drizzle-orm'
import { getChannelAdapter } from '@/lib/channels/registry'
import { integrations } from '@/lib/schema'
import { isOrgAdmin } from '@/lib/admin-auth'
import { isUniqueViolation } from '@/lib/db-helpers'

const CHANNEL_LABELS: Record<string, string> = {
  whatsapp_zapi: 'Z-API',
  whatsapp_evolution: 'Nº 2 (Evolution)',
  whatsapp_cloud_official: 'API Oficial',
  instagram_direct: 'Instagram',
}

/**
 * GET /api/leads/[id]/messages
 * Lista mensagens da conversa do lead (whatsapp, note, email, system)
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)

    const [lead] = await db
      .select({ id: leads.id })
      .from(leads)
      .where(
        and(
          eq(leads.organizationId, auth.organizationId),
          isNull(leads.deletedAt),
          isUuid ? eq(leads.id, id) : eq(leads.phone, decodeURIComponent(id))
        )
      )
      .limit(1)

    if (!lead) return apiError(404, 'Lead não encontrado.')

    // Só as últimas 300 (desc + limit, revertido pra ordem cronológica depois) — sem
    // isso, uma conversa antiga com histórico longo vem inteira de uma vez só e trava
    // o navegador ao montar centenas/milhares de bolhas na timeline, principalmente em
    // celular (o desktop absorve, o celular não). Carregar mensagens mais antigas que
    // isso fica pra uma paginação futura, se algum dia fizer falta.
    const rowsDesc = await db
      .select({
        id: leadActivities.id,
        type: leadActivities.type,
        content: leadActivities.content,
        metadata: leadActivities.metadata,
        actor_member_id: leadActivities.actorMemberId,
        created_at: leadActivities.createdAt,
        actor_id: organizationMembers.id,
        actor_full_name: profiles.fullName,
        actor_avatar_url: profiles.avatarUrl,
      })
      .from(leadActivities)
      .leftJoin(organizationMembers, eq(organizationMembers.id, leadActivities.actorMemberId))
      .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
      .where(
        and(
          eq(leadActivities.organizationId, auth.organizationId),
          eq(leadActivities.leadId, lead.id),
          sql`${leadActivities.type} IN ('whatsapp','note','email','system')`
        )
      )
      .orderBy(desc(leadActivities.createdAt))
      .limit(300)
    const rows = rowsDesc.reverse()

    // Mensagem apagada: não devolve mais o conteúdo/mídia originais na API (só o carimbo
    // "apagada") — a UI já esconde isso, mas sem redigir aqui o texto/mídia original
    // continuaria visível pra quem inspecionasse a resposta de rede, o que anula o
    // propósito de "apagar por engano" pra conteúdo sensível.
    const data = rows.map(r => {
      const metadata = (r.metadata as Record<string, any>) || {}
      if (metadata.deleted) {
        const { media_url, media_type, media_mimetype, media_filename, quoted_media_url, ...rest } = metadata
        return {
          id: r.id,
          type: r.type,
          content: null,
          metadata: rest,
          actor_member_id: r.actor_member_id,
          created_at: r.created_at,
          actor: r.actor_id ? { profiles: { full_name: r.actor_full_name || '', avatar_url: r.actor_avatar_url || undefined } } : undefined,
        }
      }
      return {
        id: r.id,
        type: r.type,
        content: r.content,
        metadata: r.metadata,
        actor_member_id: r.actor_member_id,
        created_at: r.created_at,
        actor: r.actor_id ? { profiles: { full_name: r.actor_full_name || '', avatar_url: r.actor_avatar_url || undefined } } : undefined,
      }
    })

    return Response.json({ data })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * POST /api/leads/[id]/messages
 * Envia uma mensagem no chat do lead
 */
export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const requiredError = validateRequired(body, ['content', 'type', 'source'])
    if (requiredError) return apiError(400, requiredError)
    const sourceError = validateSource(body.source)
    if (sourceError) return apiError(400, sourceError)

    const validTypes = ['whatsapp', 'note', 'email', 'system']
    if (!validTypes.includes(body.type)) {
      return apiError(400, `Tipo inválido: "${body.type}". Valores aceitos: ${validTypes.join(', ')}`)
    }

    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
    let decodedPhone = ''

    let leadQuery = db
      .select({ id: leads.id, title: leads.title, phone: leads.phone, isGroup: leads.isGroup, externalId: leads.externalId })
      .from(leads)
      .where(
        and(
          eq(leads.organizationId, auth.organizationId),
          isNull(leads.deletedAt),
          isUuid ? eq(leads.id, id) : (() => { decodedPhone = decodeURIComponent(id); return eq(leads.phone, decodedPhone) })()
        )
      )
      .limit(1)

    const [lead] = await leadQuery
    let actualLeadId = lead?.id

    if (!actualLeadId) {
      if (isUuid) return apiError(404, 'Lead não encontrado.')

      // Auto-criar lead pelo telefone
      const [firstStage] = await db
        .select({ id: pipelineStages.id })
        .from(pipelineStages)
        .where(
          and(
            eq(pipelineStages.organizationId, auth.organizationId),
            isNull(pipelineStages.deletedAt)
          )
        )
        .orderBy(asc(pipelineStages.rank))
        .limit(1)

      try {
        const [newLead] = await db
          .insert(leads)
          .values({
            organizationId: auth.organizationId,
            title: body.sender_name || decodedPhone,
            phone: decodedPhone,
            stageId: firstStage?.id || null,
            lastActivityAt: new Date(),
            customAttributes: { source: body.source },
          })
          .returning({ id: leads.id })

        actualLeadId = newLead.id
      } catch (err) {
        // leads_org_phone_unique cobre corrida entre duas requisições simultâneas
        // pra esse mesmo telefone.
        if (!isUniqueViolation(err)) throw err
        const [raceLead] = await db.select({ id: leads.id }).from(leads)
          .where(and(eq(leads.organizationId, auth.organizationId), eq(leads.phone, decodedPhone), isNull(leads.deletedAt)))
          .limit(1)
        if (!raceLead) throw err
        actualLeadId = raceLead.id
      }
    }

    const direction = body.direction || 'outbound'
    const metadata: Record<string, any> = {
      source: body.source,
      direction,
    }
    if (body.sender_name) metadata.sender_name = body.sender_name
    if (body.reply_to_message_id) metadata.reply_to_message_id = body.reply_to_message_id
    if (body.media_url) metadata.media_url = body.media_url
    if (body.media_type) metadata.media_type = body.media_type

    // Determina o canal de envio pelo integration_id do lead
    if (direction === 'outbound' && body.type === 'whatsapp' && !body.skip_send) {
      const phone = lead?.phone || decodedPhone

      // Lookup lead's integration type
      let integrationTyp: string | null = null
      let leadIntegrationId: string | null = null
      if (lead) {
        const [fullLead] = await db
          .select({ integrationId: leads.integrationId })
          .from(leads)
          .where(eq(leads.id, actualLeadId!))
          .limit(1)
        if (fullLead?.integrationId) {
          const [integ] = await db
            .select({ type: integrations.type })
            .from(integrations)
            .where(and(eq(integrations.id, fullLead.integrationId), isNull(integrations.deletedAt)))
            .limit(1)
          if (integ?.type) {
            integrationTyp = integ.type
            leadIntegrationId = fullLead.integrationId
          }
        }
      }
      // Lead sem conversa ligada a um número — o caso de todo lead que chega pela
      // Agenda, pelo site ou por indicação, até ele responder — sai pela Z-API,
      // o mesmo número da mensagem automática. Antes caía na API Oficial, que não
      // está configurada: a primeira mensagem manual pra um lead novo falhava
      // sempre com "Integração com WhatsApp não configurada" (triângulo vermelho).
      if (!integrationTyp) integrationTyp = 'whatsapp_zapi'
      metadata.channel = integrationTyp

      try {
        const adapter = getChannelAdapter(integrationTyp)

        // Grupos só existem no WhatsApp (via Evolution) — outros canais (Cloud API,
        // Instagram) não suportam; evita uma chamada fadada ao fracasso.
        if (lead?.isGroup && !adapter.supportsGroups) {
          throw new Error('Grupos só podem ser respondidos pela Evolution API — este canal não suporta grupos.')
        }

        // Instagram não tem telefone — o destinatário é o IGSID (external_id do lead).
        const recipient = integrationTyp === 'instagram_direct' ? (lead?.externalId || '') : phone
        if (integrationTyp === 'instagram_direct' && !recipient) {
          throw new Error('Lead do Instagram sem external_id (IGSID) — não é possível enviar.')
        }

        // Legenda real de mídia (só existe se alguém escreveu de verdade) — nunca usar
        // "body.content" aqui, porque pode ser só um rótulo interno da timeline do CRM
        // (ex: "📷 Imagem") que nunca deveria virar legenda de verdade no WhatsApp.
        const mediaCaption = typeof body.caption === 'string' ? body.caption : ''

        const result = body.media_url
          ? await adapter.sendMedia(auth.organizationId, leadIntegrationId, recipient, body.media_type, body.media_url, mediaCaption, body.media_filename, lead?.isGroup ?? false)
          : await adapter.sendText(auth.organizationId, leadIntegrationId, recipient, body.content, lead?.isGroup ?? false)

        metadata.send_status = 'sent'
        if (result.externalId) metadata[adapter.metadataIdKey] = result.externalId

        // O canal pode ter descoberto que o número só funciona na outra forma
        // (celular brasileiro com e sem o nono dígito). Grava a que deu certo:
        // sem isso, toda mensagem seguinte pra essa pessoa gastaria de novo uma
        // tentativa perdida, e o telefone do lead continuaria errado na tela.
        // Nunca em grupo, e só se o valor novo for telefone de verdade (só
        // dígitos): a correção existe pro nono dígito de celular. Um id de grupo
        // "corrigido" perde o "-group" e o grupo para de receber mensagem — já
        // aconteceu uma vez.
        if (
          result.recipienteCorrigido &&
          actualLeadId &&
          integrationTyp !== 'instagram_direct' &&
          !lead?.isGroup &&
          /^\d{10,15}$/.test(result.recipienteCorrigido) &&
          result.recipienteCorrigido !== phone
        ) {
          metadata.telefone_corrigido = result.recipienteCorrigido
          try {
            await db.update(leads)
              .set({ phone: result.recipienteCorrigido })
              .where(eq(leads.id, actualLeadId))
          } catch (err) {
            // Corrigir telefone é melhoria, não pode derrubar um envio que já
            // deu certo (ex: o número corrigido já pertence a outro lead).
            console.error('[messages] falha ao gravar o telefone corrigido:', err)
          }
        }
      } catch (err: any) {
        metadata.send_status = 'failed'
        metadata.send_error = err.message || 'Erro ao enviar mensagem.'

        // Sem isso, uma falha de envio só aparece pro toast do agente e fica invisível
        // no `vercel logs` — foi por isso que o bug do ffmpeg-static (ENOENT em produção
        // nos áudios via API Oficial/Instagram) só foi encontrado via query direta no
        // banco, e não pelos logs. Loga aqui pra qualquer falha futura (áudio, imagem,
        // vídeo, documento, qualquer canal) já sair visível.
        console.error(`[messages] Falha ao enviar ${body.media_type ? `mídia (${body.media_type})` : 'texto'} via ${integrationTyp} para lead ${actualLeadId}:`, err)

        // Notificação persistente (sino) — best-effort, não deve derrubar a resposta
        // se o próprio insert de notificação falhar.
        if (auth.memberId) {
          const channelLabel = CHANNEL_LABELS[integrationTyp] || 'API Oficial'
          db.insert(notifications).values({
            organizationId: auth.organizationId,
            recipientMemberId: auth.memberId,
            type: 'error',
            title: 'Falha ao enviar mensagem',
            body: `Não foi possível enviar a mensagem para ${lead?.title || phone} via ${channelLabel}: ${metadata.send_error}`,
            metadata: { linkUrl: `/chat?leadId=${actualLeadId}`, leadId: actualLeadId },
          }).catch(notifErr => console.error('[messages] Falha ao gravar notificação de erro:', notifErr))
        }
      }
    } else if (direction === 'outbound' && body.type === 'whatsapp' && body.skip_send) {
      metadata.send_status = 'sent'
    }

    const [activity] = await db
      .insert(leadActivities)
      .values({
        organizationId: auth.organizationId,
        leadId: actualLeadId,
        actorMemberId: auth.memberId || null,
        type: body.type,
        content: body.content,
        metadata,
      })
      .returning({ id: leadActivities.id, content: leadActivities.content, createdAt: leadActivities.createdAt })

    // Atualizar lead
    const updates: any = {
      lastMessageContent: body.content,
      lastMessageSenderType: direction === 'inbound' ? 'lead' : body.source,
      lastActivityAt: new Date(),
      lastActivityType: body.type,
      lastActivityByMemberId: auth.memberId || null,
      isUnread: direction === 'inbound',
    }

    if (body.sender_name && lead) {
      const title = lead.title?.trim() || ''
      if (!title || title === 'Desconhecido' || title === lead.phone || title === decodedPhone) {
        updates.title = body.sender_name
      }
    }

    // Ao responder o lead, move a conversa para o pipeline "Em atendimento"
    if (direction === 'outbound' && body.type === 'whatsapp') {
      const [stage] = await db.select({ id: pipelineStages.id }).from(pipelineStages)
        .where(and(eq(pipelineStages.organizationId, auth.organizationId), isNull(pipelineStages.deletedAt), ilike(pipelineStages.name, 'Em atendimento')))
        .limit(1)
      if (stage) updates.stageId = stage.id
    }

    await db.update(leads).set(updates).where(eq(leads.id, actualLeadId))

    // Publicar evento realtime
    await publishEvent(channels.leadActivities(actualLeadId), events.ACTIVITY_CREATED, { id: activity.id })
    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id: actualLeadId })

    return Response.json({
      ...activity,
      send_status: metadata.send_status,
      send_error: metadata.send_error,
      channel: metadata.channel,
      lead_name: lead?.title,
    }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * DELETE /api/leads/[id]/messages
 * Apaga o histórico de mensagens da conversa do lead (mantém o lead/contato).
 * Restrito a administradores.
 */
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!(await isOrgAdmin(auth))) {
      return apiError(403, 'Apenas administradores podem apagar o histórico de conversas.')
    }

    const { id } = await params
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)

    const [lead] = await db
      .select({ id: leads.id })
      .from(leads)
      .where(
        and(
          eq(leads.organizationId, auth.organizationId),
          isNull(leads.deletedAt),
          isUuid ? eq(leads.id, id) : eq(leads.phone, decodeURIComponent(id))
        )
      )
      .limit(1)

    if (!lead) return apiError(404, 'Lead não encontrado.')

    // Mesmo filtro de tipos exibidos na timeline do chat (GET acima)
    await db
      .delete(leadActivities)
      .where(
        and(
          eq(leadActivities.organizationId, auth.organizationId),
          eq(leadActivities.leadId, lead.id),
          sql`${leadActivities.type} IN ('whatsapp','note','email','system')`
        )
      )

    await db
      .update(leads)
      .set({
        lastMessageContent: null,
        lastMessageSenderType: null,
        lastActivityType: null,
        lastActivityByMemberId: null,
        isUnread: false,
        updatedAt: new Date(),
      })
      .where(eq(leads.id, lead.id))

    await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_UPDATED, { id: lead.id })
    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id: lead.id })

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
