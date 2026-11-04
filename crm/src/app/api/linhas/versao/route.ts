/**
 * GET/PUT /api/linhas/versao -- a VERSÃO DA ORGANIZAÇÃO DO CRM (Pedro, 03/11/2026: "quero testar uma nova organização do
 * CRM, sem mexer em nada agora, mas tendo um input lá em cima que eu ligo e desligo para mudar a versão de organização; a
 * versão hoje é v1, a v2 vamos organizar por etapas" e "só tem isso no Tel e muda de todos").
 * Fica em integrations.config.versao_crm da linha Leads (como os tipos de contato); sem nada gravado, 'v1'.
 * Só o administrador troca (o botão só aparece para ele, e a rota confere de novo).
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const r = await db.execute(sql`
      SELECT config->>'versao_crm' AS versao FROM integrations
       WHERE organization_id = ${auth.organizationId} AND type = 'whatsapp_zapi_captacao' AND deleted_at IS NULL
       ORDER BY created_at LIMIT 1`)
    const v = (r.rows[0] as { versao: string | null } | undefined)?.versao
    return Response.json({ versao: v === 'v2' ? 'v2' : 'v1' })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler a versão do CRM.')
  }
}

export async function PUT(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.roleId) return apiError(403, 'Só o administrador troca a versão do CRM.')
    const papel = await db.execute(sql`SELECT lower(name) AS nome FROM organization_roles WHERE id = ${auth.roleId}::uuid`)
    const nome = (papel.rows[0] as { nome: string } | undefined)?.nome || ''
    if (!['admin', 'administrador', 'owner'].includes(nome)) return apiError(403, 'Só o administrador troca a versão do CRM.')
    const corpo = await req.json().catch(() => ({}))
    const versao = corpo?.versao === 'v2' ? 'v2' : 'v1'
    await db.execute(sql`
      UPDATE integrations SET config = coalesce(config, '{}'::jsonb) || jsonb_build_object('versao_crm', ${versao}::text), updated_at = now()
       WHERE organization_id = ${auth.organizationId} AND type = 'whatsapp_zapi_captacao' AND deleted_at IS NULL`)
    return Response.json({ ok: true, versao })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui trocar a versão do CRM.')
  }
}
