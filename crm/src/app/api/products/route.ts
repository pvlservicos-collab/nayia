import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { products } from '@/lib/schema'
import { eq, and, isNull, desc } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const includeInactive = req.nextUrl.searchParams.get('include_inactive') === 'true'

    const rows = await db
      .select()
      .from(products)
      .where(
        and(
          eq(products.organizationId, auth.organizationId),
          isNull(products.deletedAt),
          includeInactive ? undefined : eq(products.status, 'active')
        )
      )
      .orderBy(desc(products.createdAt))

    return Response.json({ data: rows })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    if (!body.name?.trim()) return apiError(400, 'Nome é obrigatório.')

    const [product] = await db
      .insert(products)
      .values({
        organizationId: auth.organizationId,
        name: body.name.trim(),
        description: body.description?.trim() || null,
        price: body.price ?? 0,
        status: body.status || 'active',
      })
      .returning()

    return Response.json({ data: product }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
