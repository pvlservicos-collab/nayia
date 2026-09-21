/**
 * GET /api/users/me — retorna o membro + role da sessão atual
 * PATCH /api/users/me — atualiza perfil (nome, avatar)
 * Usado pelo AuthContext para carregar org/role do usuário logado
 */
import { NextRequest } from 'next/server'
import { auth } from '@/lib/auth'
import { apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationMembers, profiles, organizationRoles } from '@/lib/schema'
import { eq, and } from 'drizzle-orm'
import bcrypt from 'bcryptjs'
import { users } from '@/lib/schema'

export async function GET(req: NextRequest) {
  try {
    const session = await auth()
    if (!session?.user?.id) return apiError(401, 'Não autenticado.')

    const userId = session.user.id
    const orgId = new URL(req.url).searchParams.get('org_id')

    let memberQuery = db
      .select({
        id: organizationMembers.id,
        organizationId: organizationMembers.organizationId,
        roleId: organizationMembers.roleId,
        status: organizationMembers.status,
      })
      .from(organizationMembers)
      .where(
        and(
          eq(organizationMembers.userId, userId),
          eq(organizationMembers.status, 'active'),
          orgId ? eq(organizationMembers.organizationId, orgId) : undefined
        )
      )
      .limit(1)

    const [member] = await memberQuery
    if (!member) return apiError(404, 'Membro não encontrado.')

    const [role] = await db
      .select({ name: organizationRoles.name, permissions: organizationRoles.permissions })
      .from(organizationRoles)
      .where(eq(organizationRoles.id, member.roleId))
      .limit(1)

    const [profileRow] = await db
      .select({ onboardingCompleted: profiles.onboardingCompleted })
      .from(profiles)
      .where(eq(profiles.id, userId))
      .limit(1)

    return Response.json({
      member: {
        id: member.id,
        organization_id: member.organizationId,
        role_id: member.roleId,
        status: member.status,
      },
      role: role || null,
      onboarding_completed: profileRow?.onboardingCompleted ?? false,
    })
  } catch (err: any) {
    return apiError(500, err.message || 'Erro interno.')
  }
}

export async function PATCH(req: NextRequest) {
  try {
    const session = await auth()
    if (!session?.user?.id) return apiError(401, 'Não autenticado.')

    const body = await req.json()
    if (body.new_password) {
      const hash = await bcrypt.hash(body.new_password, 12)
      await db.update(users).set({ passwordHash: hash }).where(eq(users.id, session.user.id))
      return Response.json({ success: true })
    }

    const updates: any = {}
    if (body.full_name !== undefined) updates.fullName = body.full_name
    if (body.avatar_url !== undefined) updates.avatarUrl = body.avatar_url
    if (body.timezone !== undefined) updates.timezone = body.timezone
    if (body.onboarding_completed !== undefined) updates.onboardingCompleted = body.onboarding_completed

    if (Object.keys(updates).length === 0) {
      return apiError(400, 'Nenhum campo para atualizar.')
    }

    await db.update(profiles).set(updates).where(eq(profiles.id, session.user.id))
    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(500, err.message || 'Erro interno.')
  }
}
