import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, leadActivities } from '@/lib/schema'
import { eq, and, isNull, asc } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

async function resolveLead(organizationId: string, id: string) {
  const [lead] = await db.select({ id: leads.id }).from(leads)
    .where(and(eq(leads.id, id), eq(leads.organizationId, organizationId), isNull(leads.deletedAt)))
    .limit(1)
  return lead
}

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const lead = await resolveLead(auth.organizationId, id)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    const data = await db.select()
      .from(leadActivities)
      .where(and(eq(leadActivities.leadId, lead.id), eq(leadActivities.organizationId, auth.organizationId)))
      .orderBy(asc(leadActivities.createdAt))

    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    if (!body.type || !body.content) return apiError(400, 'type e content são obrigatórios.')

    const lead = await resolveLead(auth.organizationId, id)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    const [activity] = await db.insert(leadActivities).values({
      organizationId: auth.organizationId,
      leadId: lead.id,
      actorMemberId: auth.memberId || null,
      type: body.type,
      content: body.content,
      metadata: body.metadata || {},
    }).returning()

    await db.update(leads).set({
      lastActivityAt: new Date(),
      lastActivityType: body.type as any,
      lastActivityByMemberId: auth.memberId || null,
    }).where(eq(leads.id, lead.id))

    return Response.json({ data: activity }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
