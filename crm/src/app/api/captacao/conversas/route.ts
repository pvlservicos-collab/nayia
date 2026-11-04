/**
 * GET /api/captacao/conversas -- as CONVERSAS DE CAPTAÇÃO (Pedro, 03/11/2026: "cria um item no menu, Captação, lá tu coloca
 * todos os chats que estão em cadastro incompleto ... e nos chats normais as conversas de captação ficam com uma tag").
 *
 * São duas fontes:
 *   - os donos dos Cadastros incompletos (crm_cadastros_incompletos, 571): a conversa do CRM do número por onde ele falava
 *     (Oficial ou Leads), como a tela de Cadastros incompletos acha;
 *   - as conversas marcadas como de captação (custom_attributes.conversa_captacao), que a tela Imóveis captar OLX abre pela
 *     Parceria (POST /api/leads/{id}/organizar { captacao: true }).
 * Quem tem a marca FALSE ("Mandar de volta para os proprietários", 03/11 à noite) sai, mesmo sendo cadastro incompleto;
 * volta só se o cadastro dele andar depois disso.
 * Devolve os ids e o CONTEXTO de cada conversa (Pedro: "no card tem que ter um contexto, ex.: estávamos cadastrando esse
 * imóvel dia X e ele parou de responder"): o cadastro (o que já tinha, o que faltou, quando parou) ou o anúncio da OLX.
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

let cadastrosGuardados: { em: number; lista: any[] } | null = null

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const ids = new Set<string>()

    const contexto: Record<string, any> = {}
    const marcadas = await db.execute(sql`
      SELECT id::text AS id, (custom_attributes->>'conversa_captacao')::boolean AS marca, custom_attributes->'captacao_origem' AS origem,
             custom_attributes->>'conversa_captacao_em' AS marca_em
        FROM leads
       WHERE organization_id = ${auth.organizationId}::uuid AND deleted_at IS NULL
         AND custom_attributes ? 'conversa_captacao'`)
    const devolvidas = new Map<string, number>()   // id -> quando foi mandada de volta
    for (const r of marcadas.rows as any[]) {
      if (r.marca === false) { devolvidas.set(r.id, r.marca_em ? new Date(r.marca_em).getTime() : Infinity); continue }
      ids.add(r.id)
      if (r.origem) contexto[r.id] = { fonte: 'olx', ...r.origem }
    }

    // 04/11 (o CRM lento): cada aba aberta pedia isto a cada 3 min e a função leva 4-5 s; guardado 90 s no servidor
    if (!cadastrosGuardados || Date.now() - cadastrosGuardados.em > 90_000) {
      const a = await naydb().query('SELECT crm_cadastros_incompletos(14) AS j')
      cadastrosGuardados = { em: Date.now(), lista: (a.rows[0]?.j || []) as any[] }
    }
    const cadastros = cadastrosGuardados.lista
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
        // mandada de volta: só volta se o cadastro andou DEPOIS (um cadastro novo que também parou)
        if (!x || (devolvidas.has(x.id) && !(new Date(c.atualizado_em).getTime() > devolvidas.get(x.id)!))) continue
        ids.add(x.id)
        contexto[x.id] = {
          fonte: 'cadastro', tipo: c.tipo, codigo: c.codigo, dados: c.dados || {}, fotos: c.fotos ?? 0,
          criado_em: c.criado_em, atualizado_em: c.atualizado_em, faltou: c.melhor?.faltou || [], nota: c.nota ?? null,
          humano: !!c.humano, opt_out: !!c.opt_out,
        }
      }
    }
    return Response.json({ ids: Array.from(ids), contexto })
  } catch (err: any) {
    console.error('[captacao/conversas]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui achar as conversas de captação.')
  }
}
