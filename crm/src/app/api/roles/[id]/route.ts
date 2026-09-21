import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationRoles } from '@/lib/schema'
import { eq, and } from 'drizzle-orm'

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [role] = await db.select().from(organizationRoles)
      .where(and(eq(organizationRoles.id, id), eq(organizationRoles.organizationId, auth.organizationId)))
      .limit(1)
    if (!role) return apiError(404, 'Cargo não encontrado.')
    return Response.json({ data: role })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    const updates: any = {}
    if (body.permissions !== undefined) updates.permissions = body.permissions
    if (body.name !== undefined) updates.name = body.name
    if (!Object.keys(updates).length) return apiError(400, 'Nada para atualizar.')
    const [updated] = await db.update(organizationRoles)
      .set({ ...updates, updatedAt: new Date() })
      .where(and(eq(organizationRoles.id, id), eq(organizationRoles.organizationId, auth.organizationId)))
      .returning()
    return Response.json({ data: updated })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
