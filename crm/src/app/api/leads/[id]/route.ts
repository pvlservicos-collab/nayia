import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import { leads, leadTags, tags, leadStageHistory, organizationMembers, profiles } from '@/lib/schema'
import { eq, and, isNull, asc } from 'drizzle-orm'
import { mapLead } from '@/lib/mappers'
import { isUniqueViolation } from '@/lib/db-helpers'

type Params = { params: Promise<{ id: string }> }

function resolveCondition(id: string, organizationId: string) {
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
  return isUuid
    ? and(eq(leads.id, id), eq(leads.organizationId, organizationId), isNull(leads.deletedAt))
    : and(eq(leads.phone, decodeURIComponent(id)), eq(leads.organizationId, organizationId), isNull(leads.deletedAt))
}

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [lead] = await db.select().from(leads).where(resolveCondition(id, auth.organizationId)).limit(1)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    const leadTagsData = await db
      .select({ tagId: leadTags.tagId, name: tags.name, color: tags.color })
      .from(leadTags)
      .leftJoin(tags, eq(tags.id, leadTags.tagId))
      .where(eq(leadTags.leadId, lead.id))

    let owner: { id: string; profiles: { full_name: string; avatar_url?: string } } | undefined
    if (lead.ownerMemberId) {
      const [ownerRow] = await db
        .select({ id: organizationMembers.id, fullName: profiles.fullName, avatarUrl: profiles.avatarUrl })
        .from(organizationMembers)
        .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
        .where(eq(organizationMembers.id, lead.ownerMemberId))
        .limit(1)
      if (ownerRow) owner = { id: ownerRow.id, profiles: { full_name: ownerRow.fullName || '', avatar_url: ownerRow.avatarUrl || undefined } }
    }

    return Response.json({ data: { ...mapLead(lead), lead_tags: leadTagsData.map(t => ({ tag_id: t.tagId, tag: t })), owner } })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const [existing] = await db.select().from(leads).where(resolveCondition(id, auth.organizationId)).limit(1)

    // Auto-criar se busca por phone e não existe
    if (!existing) {
      const isUuid = /^[0-9a-f]{8}/.test(id)
      if (isUuid) return apiError(404, 'Lead não encontrado.')

      const decodedPhone = decodeURIComponent(id)
      try {
        const [created] = await db
          .insert(leads)
          .values({
            organizationId: auth.organizationId,
            title: body.title || decodedPhone,
            phone: decodedPhone,
            stageId: body.stage_id || null,
            customAttributes: body.custom_fields || {},
            lastActivityAt: new Date(),
          })
          .returning()

        await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_CREATED, { id: created.id })
        return Response.json({ data: created })
      } catch (err) {
        // leads_org_phone_unique cobre corrida entre duas requisições simultâneas
        // pra esse mesmo telefone (ex: dois PATCH concorrentes antes de qualquer um
        // ver o lead que o outro está criando).
        if (!isUniqueViolation(err)) throw err
        const [raceLead] = await db.select().from(leads)
          .where(and(eq(leads.organizationId, auth.organizationId), eq(leads.phone, decodedPhone), isNull(leads.deletedAt)))
          .limit(1)
        if (!raceLead) throw err
        return Response.json({ data: raceLead })
      }
    }

    const updates: any = {}
    const allowedFields = ['title', 'email', 'phone', 'stage_id', 'owner_member_id', 'custom_attributes', 'ai_interest_level', 'ai_next_action_short', 'is_unread', 'is_pinned', 'is_archived', 'value', 'avatar_url', 'cep', 'address', 'address_number', 'address_complement', 'neighborhood', 'city', 'state']
    for (const field of allowedFields) {
      if (body[field] !== undefined) {
        // Convert snake_case to camelCase
        const camel = field.replace(/_([a-z])/g, (_, c) => c.toUpperCase())
        updates[camel] = body[field]
      }
    }
    if (body.custom_fields) updates.customAttributes = body.custom_fields

    if (Object.keys(updates).length > 0) {
      await db.update(leads).set({ ...updates, updatedAt: new Date() }).where(eq(leads.id, existing.id))
    }

    // Stage history
    if (body.stage_id && body.stage_id !== existing.stageId) {
      await db.insert(leadStageHistory).values({
        organizationId: auth.organizationId,
        leadId: existing.id,
        fromStageId: existing.stageId || null,
        toStageId: body.stage_id,
        movedByMemberId: auth.memberId || null,
        movedAt: new Date(),
      })
    }

    // Tags
    if (body.tags !== undefined) {
      await db.delete(leadTags).where(eq(leadTags.leadId, existing.id))
      if (Array.isArray(body.tags) && body.tags.length > 0) {
        await db.insert(leadTags).values(
          body.tags.map((tagId: string) => ({ leadId: existing.id, tagId, organizationId: auth.organizationId }))
        ).onConflictDoNothing()
      }
    }

    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id: existing.id })

    const [updated] = await db.select().from(leads).where(eq(leads.id, existing.id)).limit(1)
    return Response.json({ data: updated })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [existing] = await db.select({ id: leads.id }).from(leads).where(resolveCondition(id, auth.organizationId)).limit(1)
    if (!existing) return apiError(404, 'Lead não encontrado.')

    await db.update(leads).set({ deletedAt: new Date() }).where(eq(leads.id, existing.id))
    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_DELETED, { id: existing.id })

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
