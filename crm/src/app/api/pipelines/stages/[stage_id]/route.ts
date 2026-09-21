import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { pipelineStages } from '@/lib/schema'
import { eq, and } from 'drizzle-orm'

type Params = { params: Promise<{ stage_id: string }> }

/**
 * Busca uma etapa pelo id. Usado por useLeadPipelineStages: o chat sabe em que
 * etapa o lead está, mas precisa descobrir a qual pipeline ela pertence pra
 * listar as etapas irmãs no seletor.
 *
 * A rota só tinha PATCH e DELETE, então esse GET respondia 405 e o seletor
 * ficava vazio. Passou despercebido porque o modo demo interceptava esta
 * chamada no cliente e devolvia uma etapa fake — quando o demo saiu, o buraco
 * apareceu.
 */
export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { stage_id } = await params
    const [stage] = await db.select().from(pipelineStages)
      .where(and(eq(pipelineStages.id, stage_id), eq(pipelineStages.organizationId, auth.organizationId)))
      .limit(1)
    if (!stage) return apiError(404, 'Etapa não encontrada.')
    // pipeline_id em snake_case: é o nome que o hook lê (e o resto da API usa).
    return Response.json({
      data: {
        id: stage.id,
        pipeline_id: stage.pipelineId,
        name: stage.name,
        color: stage.color,
        rank: stage.rank,
        target_volume: stage.targetVolume,
      },
    })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { stage_id } = await params
    const body = await req.json()
    const updates: any = {}
    if (body.name) updates.name = body.name
    if (body.color !== undefined) updates.color = body.color
    if (body.rank !== undefined) updates.rank = body.rank
    if (body.target_volume !== undefined) updates.targetVolume = body.target_volume
    if (!Object.keys(updates).length) return apiError(400, 'Nada para atualizar.')
    const [updated] = await db.update(pipelineStages).set({ ...updates, updatedAt: new Date() })
      .where(and(eq(pipelineStages.id, stage_id), eq(pipelineStages.organizationId, auth.organizationId)))
      .returning()
    return Response.json({ data: updated })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { stage_id } = await params
    await db.update(pipelineStages).set({ deletedAt: new Date() })
      .where(and(eq(pipelineStages.id, stage_id), eq(pipelineStages.organizationId, auth.organizationId)))
    return Response.json({ success: true })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
