/**
 * GET /api/leads/{id}/pausa-da-nay -- a Nay Leads em pausa porque a equipe escreveu (Pedro, 28/10/2026: "quando alguém
 * mandar msg para o lead fica claro que a Nay parou por 30 minutos, deixa um avisinho lá").
 *
 * A regra é do nay-olx (whatsapp._responder_um, 21/10): a equipe escreveu por este número, pelo CRM ou pelo celular, e a
 * Nay espera 30 min desde a ÚLTIMA mensagem da equipe; depois responde lendo o que a equipe disse. Aqui só se lê essa
 * última mensagem (lead_activities: source 'human' ou do_celular, as mesmas do da_equipe_no_crm) e se devolve até
 * quando vai a pausa. { equipeEm, ate, quem } ou { ate: null } quando não há pausa agora.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

/** o gap_equipe_min do nay-olx (30, sem chave no banco) */
const PAUSA_MIN = 30

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [lead] = await db
      .select({ id: leads.id })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    const r = await db.execute(sql`
      SELECT a.created_at AS em, p.full_name AS quem
        FROM lead_activities a
        LEFT JOIN organization_members m ON m.id = a.actor_member_id
        LEFT JOIN profiles p ON p.id = m.user_id
       WHERE a.lead_id = ${id} AND a.type = 'whatsapp' AND a.metadata->>'direction' = 'outbound'
         AND (a.metadata->>'source' = 'human' OR a.metadata->>'do_celular' = 'true')
         AND coalesce(btrim(a.content), '') <> ''
         AND a.created_at > now() - make_interval(mins => ${PAUSA_MIN})
       ORDER BY a.created_at DESC
       LIMIT 1`)
    const u = r.rows[0] as { em: string | Date; quem: string | null } | undefined
    if (!u) return Response.json({ ate: null })
    const em = new Date(u.em)
    return Response.json({
      equipeEm: em.toISOString(),
      ate: new Date(em.getTime() + PAUSA_MIN * 60_000).toISOString(),
      quem: (u.quem || '').trim().split(/\s+/)[0] || null,
    })
  } catch (e) {
    return apiError(500, e instanceof Error ? e.message : 'Erro ao ler a pausa da Nay')
  }
}
