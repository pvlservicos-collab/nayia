import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationRoles } from '@/lib/schema'
import { eq, asc } from 'drizzle-orm'

// Mesmo formato que RolePermissionsPanel.tsx espera (defaultPermissions) — um cargo
// novo nasce com acesso às telas principais e sem permissões administrativas/de gestão.
const DEFAULT_NEW_ROLE_PERMISSIONS = {
  leads: { view_own_only: true, create_edit: false, export: false },
  pipeline: { manage_deals: false, configure_funnels: false },
  settings: {
    manage_members: false,
    view_dashboard: true,
    view_pipeline: true,
    view_chat: true,
    view_leads: true,
    view_settings: false,
    view_funnels: true,
    view_logs: true,
    view_metrics: true,
  },
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const data = await db.select().from(organizationRoles)
      .where(eq(organizationRoles.organizationId, auth.organizationId))
      .orderBy(asc(organizationRoles.createdAt))
    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    if (!body.name || !String(body.name).trim()) {
      return apiError(400, 'Nome do cargo é obrigatório.')
    }

    const [role] = await db.insert(organizationRoles).values({
      organizationId: auth.organizationId,
      name: String(body.name).trim(),
      permissions: DEFAULT_NEW_ROLE_PERMISSIONS,
    }).returning()

    return Response.json({ data: role }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
