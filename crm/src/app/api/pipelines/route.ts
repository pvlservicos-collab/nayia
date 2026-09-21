import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { pipelines, pipelineStages } from '@/lib/schema'
import { eq, and, isNull, asc } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)

    const pipelinesData = await db
      .select()
      .from(pipelines)
      .where(and(eq(pipelines.organizationId, auth.organizationId), isNull(pipelines.deletedAt)))
      .orderBy(asc(pipelines.createdAt))

    const stagesData = await db
      .select()
      .from(pipelineStages)
      .where(and(eq(pipelineStages.organizationId, auth.organizationId), isNull(pipelineStages.deletedAt)))
      .orderBy(asc(pipelineStages.rank))

    const data = pipelinesData.map((p) => ({
      ...p,
      stages: stagesData.filter((s) => s.pipelineId === p.id),
    }))

    return Response.json({ data })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    const requiredError = validateRequired(body, ['name', 'source'])
    if (requiredError) return apiError(400, requiredError)

    const [pipeline] = await db
      .insert(pipelines)
      .values({
        organizationId: auth.organizationId,
        name: body.name,
        settings: body.settings || {},
      })
      .returning()

    return Response.json({ data: pipeline }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
