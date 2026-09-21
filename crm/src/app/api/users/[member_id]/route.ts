import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationMembers, profiles, users, organizationRoles } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'
import bcrypt from 'bcryptjs'

type Params = { params: Promise<{ member_id: string }> }

export async function PUT(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { member_id } = await params
    const body = await req.json()

    const missing = validateRequired(body, ['name', 'email', 'role_id'])
    if (missing) return apiError(400, missing)

    const { name, email, password, role_id } = body

    const [member] = await db.select({ userId: organizationMembers.userId })
      .from(organizationMembers)
      .where(and(eq(organizationMembers.id, member_id), eq(organizationMembers.organizationId, auth.organizationId)))
      .limit(1)

    if (!member) return apiError(404, 'Membro não encontrado.')

    const profileUpdates: any = { fullName: name }
    await db.update(profiles).set(profileUpdates).where(eq(profiles.id, member.userId))

    const userUpdates: any = { email }
    if (password && password.trim() !== '') {
      userUpdates.passwordHash = await bcrypt.hash(password, 12)
    }
    await db.update(users).set(userUpdates).where(eq(users.id, member.userId))

    await db.update(organizationMembers).set({ roleId: role_id }).where(eq(organizationMembers.id, member_id))

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { member_id } = await params

    if (auth.memberId === member_id) return apiError(400, 'Você não pode remover a si mesmo.')

    const [member] = await db.select({ id: organizationMembers.id })
      .from(organizationMembers)
      .where(and(eq(organizationMembers.id, member_id), eq(organizationMembers.organizationId, auth.organizationId)))
      .limit(1)

    if (!member) return apiError(404, 'Membro não encontrado.')

    await db.update(organizationMembers)
      .set({ status: 'disabled', deletedAt: new Date() })
      .where(eq(organizationMembers.id, member_id))

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
