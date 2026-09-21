import { db } from '@/lib/db'
import { organizationRoles } from '@/lib/schema'
import { eq } from 'drizzle-orm'

const ADMIN_ROLE_NAMES = new Set(['administrador', 'owner', 'master'])

export async function getOrgRole(roleId: string | null) {
  if (!roleId) return null
  const [role] = await db
    .select({ name: organizationRoles.name, permissions: organizationRoles.permissions })
    .from(organizationRoles)
    .where(eq(organizationRoles.id, roleId))
    .limit(1)
  return role ?? null
}

/** Cargos "administrador"/"owner"/"master" sempre podem ações restritas; superadmin sempre pode. */
export async function isOrgAdmin(auth: { isSuperAdmin?: boolean; roleId: string | null }): Promise<boolean> {
  if (auth.isSuperAdmin) return true
  const role = await getOrgRole(auth.roleId)
  if (!role?.name) return false
  return ADMIN_ROLE_NAMES.has(role.name.toLowerCase())
}
