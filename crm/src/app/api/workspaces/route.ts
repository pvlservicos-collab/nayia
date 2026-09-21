import { NextRequest } from 'next/server'
import { auth } from '@/lib/auth'
import { apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationMembers, organizations } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const session = await auth()
    if (!session?.user?.id) return apiError(401, 'Não autenticado.')

    const data = await db
      .select({
        id: organizationMembers.id,
        organizationId: organizationMembers.organizationId,
        status: organizationMembers.status,
        organization: {
          id: organizations.id,
          name: organizations.name,
          logoUrl: organizations.logoUrl,
        },
      })
      .from(organizationMembers)
      .leftJoin(organizations, eq(organizations.id, organizationMembers.organizationId))
      .where(
        and(
          eq(organizationMembers.userId, session.user.id),
          eq(organizationMembers.status, 'active'),
          isNull(organizationMembers.deletedAt)
        )
      )

    const formatted = data.map((m) => ({
      id: m.id,
      organization_id: m.organizationId,
      organization: m.organization
        ? { id: m.organization.id, name: m.organization.name, logo_url: m.organization.logoUrl }
        : null,
    }))

    return Response.json({ data: formatted })
  } catch (err: any) {
    return apiError(500, err.message || 'Erro interno.')
  }
}
