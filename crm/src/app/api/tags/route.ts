import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { tags } from '@/lib/schema'
import { eq, and, asc, sql } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const data = await db.select().from(tags)
      .where(eq(tags.organizationId, auth.organizationId))
      .orderBy(asc(tags.name))
    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()
    const missing = validateRequired(body, ['name', 'source'])
    if (missing) return apiError(400, missing)
    const [tag] = await db.insert(tags).values({
      organizationId: auth.organizationId,
      name: body.name,
      color: body.color || '#6366f1',
    }).returning()
    return Response.json({ data: tag }, { status: 201 })
  } catch (err: any) {
    if (err?.code === '23505') return apiError(409, 'Já existe uma tag com esse nome.')
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function PATCH(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const id = req.nextUrl.searchParams.get('id')
    if (!id) return apiError(400, 'id é obrigatório.')

    const body = await req.json()
    const updates: Record<string, any> = {}
    /* RENOMEAR (Pedro, 19/10/2026: "editar o nome de todas as tags"). A etiqueta e a etapa do funil de mesmo nome são
       uma coisa só (marcar a etiqueta move o card): as duas mudam juntas, e o nome de nascença fica em nome_original
       (0133), onde o funil automático, a etapa "Em atendimento" e o Orgânico continuam achando. */
    if (body.name !== undefined) {
      const novo = String(body.name || '').trim().slice(0, 40)
      if (!novo) return apiError(400, 'O nome não pode ficar vazio.')
      const [atual] = await db.select({ name: tags.name }).from(tags)
        .where(and(eq(tags.id, id), eq(tags.organizationId, auth.organizationId))).limit(1)
      if (!atual) return apiError(404, 'Tag não encontrada.')
      if (atual.name !== novo) {
        const outra = await db.execute(sql`
          SELECT 1 FROM tags WHERE organization_id = ${auth.organizationId} AND id <> ${id} AND lower(name) = lower(${novo}) LIMIT 1`)
        if (outra.rows.length) return apiError(409, 'Já existe uma etiqueta com esse nome.')
        await db.execute(sql`
          UPDATE pipeline_stages SET name = ${novo}, nome_original = coalesce(nome_original, name), updated_at = now()
           WHERE organization_id = ${auth.organizationId} AND name = ${atual.name} AND deleted_at IS NULL`)
        await db.execute(sql`UPDATE tags SET nome_original = coalesce(nome_original, name) WHERE id = ${id}`)
        updates.name = novo
      }
    }
    if (body.color !== undefined) updates.color = body.color
    if (Object.keys(updates).length === 0) {
      if (body.name !== undefined) return Response.json({ data: { id } })      // o mesmo nome: nada a fazer
      return apiError(400, 'Nenhum campo para atualizar.')
    }
    updates.updatedAt = new Date()

    const [tag] = await db.update(tags)
      .set(updates)
      .where(and(eq(tags.id, id), eq(tags.organizationId, auth.organizationId)))
      .returning()

    if (!tag) return apiError(404, 'Tag não encontrada.')
    return Response.json({ data: tag })
  } catch (err: any) {
    if (err?.code === '23505') return apiError(409, 'Já existe uma tag com esse nome.')
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const id = req.nextUrl.searchParams.get('id')
    if (!id) return apiError(400, 'id é obrigatório.')

    const [deleted] = await db.delete(tags)
      .where(and(eq(tags.id, id), eq(tags.organizationId, auth.organizationId)))
      .returning({ id: tags.id })

    if (!deleted) return apiError(404, 'Tag não encontrada.')
    return Response.json({ data: { id: deleted.id } })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
