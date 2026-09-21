import { getOrgRole, isOrgAdmin } from '@/lib/admin-auth'

/**
 * Segue a mesma heurística de admin usada em RolePermissionsPanel.tsx / financeiro/layout.tsx
 * (cargos "administrador"/"owner"/"master" sempre podem; os demais dependem da permissão
 * granular settings.manage_quick_replies).
 */
export async function canManageSharedQuickReplies(roleId: string | null): Promise<boolean> {
  if (await isOrgAdmin({ roleId })) return true

  const role = await getOrgRole(roleId)
  return !!(role?.permissions as any)?.settings?.manage_quick_replies
}
