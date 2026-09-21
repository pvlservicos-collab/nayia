import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { customFieldDefinitions, customFieldCategories } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [field] = await db.select().from(customFieldDefinitions)
      .where(and(eq(customFieldDefinitions.id, id), eq(customFieldDefinitions.organizationId, auth.organizationId), isNull(customFieldDefinitions.deletedAt)))
      .limit(1)

    if (!field) return apiError(404, 'Custom field not found')
    return Response.json({ data: field })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    const type = req.nextUrl.searchParams.get('type') || body.type

    if (type === 'category') {
      const updates: any = {}
      if (body.name !== undefined) updates.name = body.name
      if (body.rank !== undefined) updates.rank = body.rank
      const [updated] = await db.update(customFieldCategories)
        .set(updates)
        .where(and(eq(customFieldCategories.id, id), eq(customFieldCategories.organizationId, auth.organizationId)))
        .returning()
      return Response.json({ data: updated })
    }

    const updates: any = {}
    if (body.name !== undefined) updates.name = body.name
    if (body.field_type !== undefined) updates.fieldType = body.field_type
    if (body.category_id !== undefined) updates.categoryId = body.category_id
    if (body.rank !== undefined) updates.rank = body.rank
    if (body.is_required !== undefined) updates.isRequired = body.is_required
    if (body.options !== undefined) updates.options = body.options

    const [updated] = await db.update(customFieldDefinitions)
      .set({ ...updates, updatedAt: new Date() })
      .where(and(eq(customFieldDefinitions.id, id), eq(customFieldDefinitions.organizationId, auth.organizationId)))
      .returning()

    return Response.json({ data: updated })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const type = req.nextUrl.searchParams.get('type')

    if (type === 'category') {
      await db.delete(customFieldCategories)
        .where(and(eq(customFieldCategories.id, id), eq(customFieldCategories.organizationId, auth.organizationId)))
      return Response.json({ success: true })
    }

    await db.update(customFieldDefinitions)
      .set({ deletedAt: new Date() })
      .where(and(eq(customFieldDefinitions.id, id), eq(customFieldDefinitions.organizationId, auth.organizationId)))

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
