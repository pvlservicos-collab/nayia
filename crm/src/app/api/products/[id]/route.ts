import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { products } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [product] = await db
      .select()
      .from(products)
      .where(and(eq(products.id, id), eq(products.organizationId, auth.organizationId), isNull(products.deletedAt)))
      .limit(1)

    if (!product) return apiError(404, 'Produto não encontrado.')
    return Response.json({ data: product })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const updates: Record<string, any> = { updatedAt: new Date() }
    if (body.name !== undefined) updates.name = body.name.trim()
    if (body.description !== undefined) updates.description = body.description?.trim() || null
    if (body.price !== undefined) updates.price = body.price
    if (body.status !== undefined) updates.status = body.status

    const [product] = await db
      .update(products)
      .set(updates)
      .where(and(eq(products.id, id), eq(products.organizationId, auth.organizationId), isNull(products.deletedAt)))
      .returning()

    if (!product) return apiError(404, 'Produto não encontrado.')
    return Response.json({ data: product })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    await db
      .update(products)
      .set({ deletedAt: new Date() })
      .where(and(eq(products.id, id), eq(products.organizationId, auth.organizationId)))

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
