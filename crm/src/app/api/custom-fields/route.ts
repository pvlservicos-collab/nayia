import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { customFieldDefinitions, customFieldCategories } from '@/lib/schema'
import { eq, and, isNull, asc } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)

    const [definitions, categories] = await Promise.all([
      db.select().from(customFieldDefinitions)
        .where(and(eq(customFieldDefinitions.organizationId, auth.organizationId), isNull(customFieldDefinitions.deletedAt)))
        .orderBy(asc(customFieldDefinitions.rank)),
      db.select().from(customFieldCategories)
        .where(eq(customFieldCategories.organizationId, auth.organizationId))
        .orderBy(asc(customFieldCategories.rank)),
    ])

    return Response.json({ categories, definitions })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    if (body.type === 'category') {
      const missing = validateRequired(body, ['name'])
      if (missing) return apiError(400, missing)
      const [cat] = await db.insert(customFieldCategories).values({
        organizationId: auth.organizationId,
        name: body.name,
        rank: body.rank ?? 0,
      }).returning()
      return Response.json({ data: cat }, { status: 201 })
    }

    const missing = validateRequired(body, ['name', 'field_type'])
    if (missing) return apiError(400, missing)

    const slug = body.name.toLowerCase().replace(/[^a-z0-9]/g, '_')
    const fieldKey = body.key || `${slug}_${Date.now()}`

    const [def] = await db.insert(customFieldDefinitions).values({
      organizationId: auth.organizationId,
      categoryId: body.category_id || null,
      name: body.name,
      fieldKey,
      fieldType: body.field_type,
      options: body.options || [],
      isRequired: !!body.required,
      rank: body.rank ?? (Date.now() % 100000),
    }).returning()

    return Response.json({ data: def }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
