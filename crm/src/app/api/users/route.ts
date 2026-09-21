import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationMembers, profiles, users, organizationRoles } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'
import bcrypt from 'bcryptjs'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const rows = await db
      .select({
        id: organizationMembers.id,
        userId: organizationMembers.userId,
        roleId: organizationMembers.roleId,
        status: organizationMembers.status,
        createdAt: organizationMembers.createdAt,
        fullName: profiles.fullName,
        avatarUrl: profiles.avatarUrl,
        email: users.email,
        roleName: organizationRoles.name,
      })
      .from(organizationMembers)
      .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
      .leftJoin(users, eq(users.id, organizationMembers.userId))
      .leftJoin(organizationRoles, eq(organizationRoles.id, organizationMembers.roleId))
      .where(
        and(
          eq(organizationMembers.organizationId, auth.organizationId),
          isNull(organizationMembers.deletedAt)
        )
      )

    const data = rows.map(r => ({
      id: r.id,
      user_id: r.userId,
      role_id: r.roleId,
      status: r.status,
      created_at: r.createdAt,
      profiles: { full_name: r.fullName, avatar_url: r.avatarUrl, email: r.email },
      organization_roles: { name: r.roleName },
    }))

    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    const missing = validateRequired(body, ['name', 'email', 'password', 'role_id'])
    if (missing) return apiError(400, missing)

    const { name, email, password, role_id } = body

    if (password.length < 6) {
      return apiError(400, 'A senha deve ter no mínimo 6 caracteres.')
    }

    const passwordHash = await bcrypt.hash(password, 12)

    const [user] = await db.insert(users).values({
      email: String(email).toLowerCase().trim(),
      passwordHash,
    }).returning()

    await db.insert(profiles).values({ id: user.id, fullName: name })

    const [member] = await db.insert(organizationMembers).values({
      organizationId: auth.organizationId,
      userId: user.id,
      roleId: role_id,
      status: 'active',
    }).returning()

    return Response.json({ success: true, data: { id: member.id, user_id: user.id } }, { status: 201 })
  } catch (err: any) {
    if (err.code === '23505') return apiError(409, 'E-mail já cadastrado.')
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
