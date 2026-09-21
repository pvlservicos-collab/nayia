import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations, integrationSecrets, organizationRoles, leads } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

async function assertManageIntegrations(auth: Awaited<ReturnType<typeof authenticateRequest>>) {
  if (auth.isSuperAdmin || !auth.memberId || !auth.roleId) return
  const [role] = await db.select({ permissions: organizationRoles.permissions })
    .from(organizationRoles).where(eq(organizationRoles.id, auth.roleId)).limit(1)
  if (!role) throw { status: 403, message: 'Não foi possível validar permissões.' }
  const perms = (role.permissions || {}) as Record<string, any>
  if (!perms.manage_integrations && !perms['*'] && !perms.all) {
    throw { status: 403, message: 'Permissão negada: requer manage_integrations.' }
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    await assertManageIntegrations(auth)
    const body = await req.json().catch(() => ({}))
    const missing = validateRequired(body ?? {}, ['waba_id', 'phone_number_id', 'system_token'])
    if (missing) return apiError(400, missing)

    const { waba_id, phone_number_id, system_token, graph_api_version } = body
    const config = { waba_id, phone_number_id, graph_api_version: graph_api_version ?? 'v21.0' }

    const existing = await db.select({ id: integrations.id }).from(integrations)
      .where(and(eq(integrations.organizationId, auth.organizationId), eq(integrations.type, 'whatsapp_cloud_official')))
      .limit(1)

    let integrationId: string
    if (existing.length > 0) {
      integrationId = existing[0].id
      await db.update(integrations).set({ config, status: 'active', updatedAt: new Date() })
        .where(and(eq(integrations.id, integrationId), eq(integrations.organizationId, auth.organizationId)))
    } else {
      const [created] = await db.insert(integrations).values({
        organizationId: auth.organizationId,
        name: 'WhatsApp Cloud (Oficial)',
        type: 'whatsapp_cloud_official',
        status: 'active',
        config,
      }).returning({ id: integrations.id })
      integrationId = created.id
    }

    // Upsert integration secret
    const existingSecret = await db.select({ id: integrationSecrets.id }).from(integrationSecrets)
      .where(eq(integrationSecrets.integrationId, integrationId)).limit(1)

    if (existingSecret.length > 0) {
      await db.update(integrationSecrets).set({ secret: { system_token }, updatedAt: new Date() })
        .where(eq(integrationSecrets.integrationId, integrationId))
    } else {
      await db.insert(integrationSecrets).values({
        integrationId,
        organizationId: auth.organizationId,
        secret: { system_token },
      })
    }

    return Response.json({ integration_id: integrationId })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const [integration] = await db.select({ id: integrations.id, status: integrations.status, config: integrations.config })
      .from(integrations)
      .where(and(eq(integrations.organizationId, auth.organizationId), eq(integrations.type, 'whatsapp_cloud_official')))
      .limit(1)

    if (!integration) return Response.json(null)

    // Passo 2 do onboarding ("confirmar conexão"): um lead só nasce dessa integração
    // depois que uma mensagem de verdade chegou pelo webhook — não precisa de coluna
    // nova, só checar se já existe algum lead apontando pra essa integração.
    const [leadRow] = await db.select({ id: leads.id }).from(leads)
      .where(eq(leads.integrationId, integration.id)).limit(1)

    return Response.json({ ...integration, hasInboundMessage: !!leadRow })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
