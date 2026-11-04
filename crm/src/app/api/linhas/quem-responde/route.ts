/**
 * GET /api/linhas/quem-responde -- QUEM MANDOU A ÚLTIMA MENSAGEM de cada conversa, para o selo da v3 (Pedro, 04/11/2026:
 * "no número dele quem está respondendo é a equipe e mesmo assim na v3 tá IA no canto do contato").
 * Só devolve as conversas em que a última mensagem nossa saiu de GENTE (pelo CRM, source 'human', ou pelo celular,
 * do_celular); o resto é a Nay. A mesma régua do balão (ActivityTimeline.autorV3). Últimos 14 dias.
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
      SELECT * FROM (
        SELECT DISTINCT ON (a.lead_id)
               a.lead_id::text AS id,
               (a.metadata->>'source' = 'human' OR coalesce(a.metadata->>'do_celular', '') = 'true') AS humano,
               coalesce(a.metadata->>'do_celular', '') = 'true' AS celular,
               split_part(coalesce(p.full_name, ''), ' ', 1) AS nome,
               a.created_at AS em
          FROM lead_activities a
          LEFT JOIN organization_members om ON om.id = a.actor_member_id
          LEFT JOIN profiles p ON p.id = om.user_id
         WHERE a.organization_id = ${auth.organizationId}
           AND a.type = 'whatsapp'
           AND a.metadata->>'direction' = 'outbound'
           AND a.created_at > now() - interval '14 days'
         ORDER BY a.lead_id, a.created_at DESC
      ) t WHERE t.humano`)
    const mapa: Record<string, { nome: string; celular: boolean; em: string }> = {}
    for (const x of r.rows as Array<{ id: string; nome: string; celular: boolean; em: string | Date }>) {
      mapa[x.id] = { nome: x.nome || '', celular: !!x.celular, em: new Date(x.em).toISOString() }
    }
    return Response.json({ humanos: mapa })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler quem está respondendo.')
  }
}
