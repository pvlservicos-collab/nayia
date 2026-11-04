/**
 * GET /api/captacao/conversas -- as CONVERSAS DE CAPTAÇÃO (Pedro, 03/11/2026: "cria um item no menu, Captação, lá tu coloca
 * todos os chats que estão em cadastro incompleto ... e nos chats normais as conversas de captação ficam com uma tag").
 *
 * São duas fontes:
 *   - os donos dos Cadastros incompletos (crm_cadastros_incompletos, 571): a conversa do CRM do número por onde ele falava
 *     (Oficial ou Leads), como a tela de Cadastros incompletos acha;
 *   - as conversas marcadas como de captação (custom_attributes.conversa_captacao), que a tela Imóveis captar OLX abre pela
 *     Parceria (POST /api/leads/{id}/organizar { captacao: true }).
 * Devolve só os ids; quem desenha (Chat Captação e as listas dos números) usa as conversas que já tem.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const TIPO_DA_LINHA: Record<string, string> = { oficial: 'whatsapp_cloud_official', zapi: 'whatsapp_zapi_captacao' }
const so8 = (t: string | null) => (t || '').replace(/\D/g, '').slice(-8)

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const ids = new Set<string>()

    const marcadas = await db.execute(sql`
      SELECT id::text AS id FROM leads
       WHERE organization_id = ${auth.organizationId}::uuid AND deleted_at IS NULL
         AND (custom_attributes->>'conversa_captacao')::boolean IS TRUE`)
    for (const r of marcadas.rows as any[]) ids.add(r.id)

    const a = await naydb().query('SELECT crm_cadastros_incompletos(14) AS j')
    const cadastros = (a.rows[0]?.j || []) as any[]
    const fones = Array.from(new Set(cadastros.map((c) => so8(c.telefone)).filter((f) => f.length === 8)))
    if (fones.length) {
      const l = await db.execute(sql`
        SELECT l.id::text AS id, i.type AS linha, right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 8) AS f8
          FROM leads l JOIN integrations i ON i.id = l.integration_id
         WHERE l.organization_id = ${auth.organizationId}::uuid AND l.deleted_at IS NULL
           AND right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 8) IN (${sql.join(fones.map((f) => sql`${f}`), sql`, `)})`)
      const leads = l.rows as any[]
      for (const c of cadastros) {
        const tipo = TIPO_DA_LINHA[c.canal] || 'whatsapp_cloud_official'
        const x = leads.find((y) => y.f8 === so8(c.telefone) && y.linha === tipo) || leads.find((y) => y.f8 === so8(c.telefone) && y.linha !== 'whatsapp_zapi')
        if (x) ids.add(x.id)
      }
    }
    return Response.json({ ids: Array.from(ids) })
  } catch (err: any) {
    console.error('[captacao/conversas]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui achar as conversas de captação.')
  }
}
