import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { pipelines } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [pipeline] = await db.select().from(pipelines)
      .where(and(eq(pipelines.id, id), eq(pipelines.organizationId, auth.organizationId), isNull(pipelines.deletedAt)))
      .limit(1)
    if (!pipeline) return apiError(404, 'Pipeline não encontrado.')
    return Response.json({ data: pipeline })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    const updates: any = {}
    if (body.name) updates.name = body.name
    if (body.settings) updates.settings = body.settings
    if (!Object.keys(updates).length) return apiError(400, 'Nada para atualizar.')
    const [updated] = await db.update(pipelines).set({ ...updates, updatedAt: new Date() })
      .where(and(eq(pipelines.id, id), eq(pipelines.organizationId, auth.organizationId)))
      .returning()
    return Response.json({ data: updated })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    await db.update(pipelines).set({ deletedAt: new Date() })
      .where(and(eq(pipelines.id, id), eq(pipelines.organizationId, auth.organizationId)))
    return Response.json({ success: true })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
