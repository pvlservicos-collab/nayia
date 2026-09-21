import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizations } from '@/lib/schema'
import { eq } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const [org] = await db.select().from(organizations).where(eq(organizations.id, auth.organizationId)).limit(1)
    if (!org) return apiError(404, 'Organização não encontrada.')
    return Response.json({ data: org })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function PATCH(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()
    const updates: any = {}
    if (body.name !== undefined) updates.name = body.name
    if (body.logo_url !== undefined) updates.logoUrl = body.logo_url
    if (!Object.keys(updates).length) return apiError(400, 'Nada para atualizar.')
    const [updated] = await db.update(organizations)
      .set({ ...updates, updatedAt: new Date() })
      .where(eq(organizations.id, auth.organizationId))
      .returning()
    return Response.json({ data: updated })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
