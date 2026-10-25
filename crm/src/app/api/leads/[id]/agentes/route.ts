/**
 * GET /api/leads/{id}/agentes -- a legenda dos agentes da Nay Leads e o histórico deste lead em etiquetas (Pedro, 24/10/2026:
 * "uma legenda de cores para cada agente visível no card do lead ... um histórico de atendimento em cada card do lead,
 * mostrando em tags cada agente que ativou incluindo se um humano assumiu").
 * Devolve { modo, agentes, eventos } com os eventos do mais recente para o mais antigo.
 *   - do banco da Nay: crm_agentes() e crm_agentes_do_lead(telefone) (nayia 489: os eventos gravados pelos agentes e o que
 *     a busca, a visita, a fila de perguntas e o celular já registram);
 *   - daqui: a equipe respondendo pelo CRM (mensagem manual com autor), uma etiqueta Humano por hora.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import type { Agente, EventoDeAgente } from '@/lib/agentes'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const LIMITE = 80

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [lead] = await db
      .select({ id: leads.id, phone: leads.phone })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')

    const [cad, hist, crm] = await Promise.all([
      naydb().query('SELECT crm_agentes() AS j'),
      naydb().query('SELECT em, agente, nome, cor, acao, detalhe, modo FROM crm_agentes_do_lead($1, $2)', [lead.phone || '', LIMITE]),
      db.execute(sql`
        SELECT date_trunc('hour', a.created_at) AS hora, min(a.created_at) AS em, count(*)::int AS n,
               string_agg(DISTINCT coalesce(p.full_name, 'equipe'), ', ') AS quem
          FROM lead_activities a
          LEFT JOIN organization_members m ON m.id = a.actor_member_id
          LEFT JOIN profiles p ON p.id = m.user_id
         WHERE a.lead_id = ${lead.id} AND a.organization_id = ${auth.organizationId}
           AND a.metadata->>'direction' = 'outbound' AND a.actor_member_id IS NOT NULL
           AND coalesce(a.metadata->>'automated', 'false') <> 'true'
           AND coalesce(a.metadata->>'source', '') NOT IN ('funnel', 'ai', 'ai_agent', 'automation')
           AND a.created_at > now() - interval '60 days'
         GROUP BY 1 ORDER BY 1 DESC LIMIT 40`),
    ])
    const j = (cad.rows[0]?.j || {}) as { modo?: string; agentes?: Agente[] }
    const agentes = j.agentes || []
    const humano = agentes.find((a) => a.chave === 'humano')
    const eventos: EventoDeAgente[] = (hist.rows as any[]).map((r) => ({
      em: new Date(r.em).toISOString(), agente: r.agente, nome: r.nome, cor: r.cor, acao: r.acao,
      detalhe: r.detalhe || '', modo: r.modo,
    }))
    for (const r of crm.rows as { em: string; n: number; quem: string }[]) {
      eventos.push({
        em: new Date(r.em).toISOString(), agente: 'humano', nome: humano?.nome || 'Humano', cor: humano?.cor || '#374151',
        acao: 'equipe_no_crm', detalhe: `${r.n} mensagem(ns) de ${r.quem}`, modo: 'real',
      })
    }
    eventos.sort((a, b) => (a.em < b.em ? 1 : -1))
    return Response.json({ modo: j.modo || 'nao', agentes, eventos: eventos.slice(0, LIMITE) })
  } catch (e) {
    return apiError(500, e instanceof Error ? e.message : 'Erro ao ler os agentes')
  }
}
