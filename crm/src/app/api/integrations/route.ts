import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations } from '@/lib/schema'
import { eq, and, isNull, asc } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const name = req.nextUrl.searchParams.get('name')
    let query = db.select().from(integrations)
      .where(and(eq(integrations.organizationId, auth.organizationId), isNull(integrations.deletedAt)))
      .$dynamic()
    const data = await db.select().from(integrations)
      .where(and(eq(integrations.organizationId, auth.organizationId), isNull(integrations.deletedAt)))
      .orderBy(asc(integrations.name))
    const filtered = name ? data.filter(i => i.name === name) : data
    return Response.json({ data: filtered })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()
    if (!body.name) return apiError(400, 'name é obrigatório.')
    const [integration] = await db.insert(integrations).values({
      organizationId: auth.organizationId,
      name: body.name,
      type: body.type || null,
      config: body.config || {},
      status: body.status || 'active',
    }).returning()
    return Response.json({ data: integration }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function PATCH(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()
    if (!body.id && !body.name) return apiError(400, 'id ou name é obrigatório.')
    const updates: any = {}
    if (body.config !== undefined) updates.config = body.config
    if (body.status !== undefined) updates.status = body.status

    let condition: any
    if (body.id) {
      condition = and(eq(integrations.id, body.id), eq(integrations.organizationId, auth.organizationId))
    } else {
      const existing = await db.select({ id: integrations.id, config: integrations.config }).from(integrations)
        .where(and(eq(integrations.organizationId, auth.organizationId), eq(integrations.name, body.name)))
        .limit(1)
      if (!existing.length) return apiError(404, 'Integração não encontrada.')
      if (body.config && body.mergeConfig) {
        updates.config = { ...(existing[0].config as any || {}), ...body.config }
      }
      condition = and(eq(integrations.id, existing[0].id), eq(integrations.organizationId, auth.organizationId))
    }

    const [updated] = await db.update(integrations).set({ ...updates, updatedAt: new Date() }).where(condition).returning()
    return Response.json({ data: updated })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
