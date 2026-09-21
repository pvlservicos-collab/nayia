import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { pipelineStages } from '@/lib/schema'
import { eq, and, isNull, asc } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const data = await db.select().from(pipelineStages)
      .where(and(eq(pipelineStages.pipelineId, id), eq(pipelineStages.organizationId, auth.organizationId), isNull(pipelineStages.deletedAt)))
      .orderBy(asc(pipelineStages.rank))
    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    if (!body.name) return apiError(400, 'Campo obrigatório ausente: name')
    const [stage] = await db.insert(pipelineStages).values({
      organizationId: auth.organizationId,
      pipelineId: id,
      name: body.name,
      color: body.color || null,
      rank: body.rank ?? 1000,
      targetVolume: body.target_volume || null,
    }).returning()
    return Response.json({ data: stage }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
