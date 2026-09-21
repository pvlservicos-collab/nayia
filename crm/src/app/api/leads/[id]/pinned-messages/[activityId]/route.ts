import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import { leads, pinnedMessages } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

type Params = { params: Promise<{ id: string; activityId: string }> }

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
 * DELETE /api/leads/[id]/pinned-messages/[activityId]
 * Desafixa uma mensagem da conversa.
 */
export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id, activityId } = await params

    const lead = await resolveLead(id, auth.organizationId)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    await db
      .delete(pinnedMessages)
      .where(and(eq(pinnedMessages.leadId, lead.id), eq(pinnedMessages.activityId, activityId)))

    await publishEvent(channels.leadActivities(lead.id), events.PIN_DELETED, { activity_id: activityId })

    return Response.json({ data: { activity_id: activityId } })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
