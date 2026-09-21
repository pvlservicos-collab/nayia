import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import { leads, leadActivities, pinnedMessages, organizationMembers, profiles } from '@/lib/schema'
import { eq, and, isNull, desc } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

async function resolveLead(id: string, organizationId: string) {
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
  const [lead] = await db
    .select({ id: leads.id })
    .from(leads)
    .where(
      and(
        eq(leads.organizationId, organizationId),
        isNull(leads.deletedAt),
        isUuid ? eq(leads.id, id) : eq(leads.phone, decodeURIComponent(id))
      )
    )
    .limit(1)
  return lead
}

/**
 * GET /api/leads/[id]/pinned-messages
 * Lista mensagens fixadas da conversa (sem limite de quantidade).
 */
export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const lead = await resolveLead(id, auth.organizationId)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    const rows = await db
      .select({
        id: pinnedMessages.id,
        activityId: pinnedMessages.activityId,
        pinnedByMemberId: pinnedMessages.pinnedByMemberId,
        pinnedAt: pinnedMessages.pinnedAt,
        activityType: leadActivities.type,
        activityContent: leadActivities.content,
        activityMetadata: leadActivities.metadata,
        activityCreatedAt: leadActivities.createdAt,
        actorId: organizationMembers.id,
        actorFullName: profiles.fullName,
        actorAvatarUrl: profiles.avatarUrl,
      })
      .from(pinnedMessages)
      .innerJoin(leadActivities, eq(leadActivities.id, pinnedMessages.activityId))
      .leftJoin(organizationMembers, eq(organizationMembers.id, leadActivities.actorMemberId))
      .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
      .where(eq(pinnedMessages.leadId, lead.id))
      .orderBy(desc(pinnedMessages.pinnedAt))

    const data = rows.map((r) => ({
      id: r.id,
      activity_id: r.activityId,
      pinned_by_member_id: r.pinnedByMemberId,
      pinned_at: r.pinnedAt,
      activity: {
        id: r.activityId,
        type: r.activityType,
        content: r.activityContent,
        metadata: r.activityMetadata,
        created_at: r.activityCreatedAt,
        actor: r.actorId ? { profiles: { full_name: r.actorFullName || '', avatar_url: r.actorAvatarUrl || undefined } } : undefined,
      },
    }))

    return Response.json({ data })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * POST /api/leads/[id]/pinned-messages
 * Fixa uma mensagem existente da conversa. Sem limite de quantidade.
 */
export async function POST(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const requiredError = validateRequired(body, ['activity_id'])
    if (requiredError) return apiError(400, requiredError)

    const lead = await resolveLead(id, auth.organizationId)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    const [activity] = await db
      .select({ id: leadActivities.id })
      .from(leadActivities)
      .where(
        and(
          eq(leadActivities.id, body.activity_id),
          eq(leadActivities.leadId, lead.id),
          eq(leadActivities.organizationId, auth.organizationId)
        )
      )
      .limit(1)
    if (!activity) return apiError(404, 'Mensagem não encontrada nesta conversa.')

    let [pin] = await db
      .insert(pinnedMessages)
      .values({
        organizationId: auth.organizationId,
        leadId: lead.id,
        activityId: activity.id,
        pinnedByMemberId: auth.memberId || null,
      })
      .onConflictDoNothing()
      .returning()

    if (!pin) {
      // Já estava fixada — POST é idempotente, devolve o registro existente.
      ;[pin] = await db
        .select()
        .from(pinnedMessages)
        .where(and(eq(pinnedMessages.leadId, lead.id), eq(pinnedMessages.activityId, activity.id)))
        .limit(1)
    }

    await publishEvent(channels.leadActivities(lead.id), events.PIN_CREATED, { activity_id: activity.id })

    return Response.json({ data: pin }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
