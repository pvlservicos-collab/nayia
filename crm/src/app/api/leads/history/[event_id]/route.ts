import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired, validateSource } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadActivities } from '@/lib/schema'
import { eq, and } from 'drizzle-orm'

type Params = { params: Promise<{ event_id: string }> }

export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { event_id } = await params
    const body = await req.json()

    const requiredError = validateRequired(body, ['source'])
    if (requiredError) return apiError(400, requiredError)
    const sourceError = validateSource(body.source)
    if (sourceError) return apiError(400, sourceError)

    const [existing] = await db.select({ id: leadActivities.id, metadata: leadActivities.metadata })
      .from(leadActivities)
      .where(and(eq(leadActivities.id, event_id), eq(leadActivities.organizationId, auth.organizationId)))
      .limit(1)

    if (!existing) return apiError(404, 'Evento não encontrado.')

    const updates: any = {}
    if (body.content !== undefined) updates.content = body.content
    if (body.metadata !== undefined) updates.metadata = { ...(existing.metadata as any || {}), ...body.metadata, source: body.source }

    const [updated] = await db.update(leadActivities)
      .set({ ...updates, updatedAt: new Date() })
      .where(eq(leadActivities.id, event_id))
      .returning()

    return Response.json(updated)
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { event_id } = await params

    const source = req.nextUrl.searchParams.get('source')
    if (!source) return apiError(400, 'Campo obrigatório ausente: source (query param)')
    const sourceError = validateSource(source)
    if (sourceError) return apiError(400, sourceError)

    const [existing] = await db.select({ id: leadActivities.id })
      .from(leadActivities)
      .where(and(eq(leadActivities.id, event_id), eq(leadActivities.organizationId, auth.organizationId)))
      .limit(1)

    if (!existing) return apiError(404, 'Evento não encontrado.')

    await db.delete(leadActivities).where(eq(leadActivities.id, event_id))
    return new Response(null, { status: 204 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
