/**
 * GET /api/lead-sources — as abas da tela /leads.
 *
 * Devolve a definição de cada fonte (rótulo, colunas) junto com a contagem e a
 * data do último lead recebido. Numa chamada só: a tela precisa das duas coisas
 * pra desenhar as abas, e são poucas fontes.
 */
import { NextRequest } from 'next/server'
import { and, eq, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leadSourceSubmissions } from '@/lib/schema'
import { LEAD_SOURCES, LEAD_SOURCE_ORDER } from '@/lib/leadSources'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)

    const counts = await db
      .select({
        source: leadSourceSubmissions.source,
        total: sql<number>`count(*)::int`,
        lastReceivedAt: sql<string | null>`max(${leadSourceSubmissions.receivedAt})`,
      })
      .from(leadSourceSubmissions)
      .where(eq(leadSourceSubmissions.organizationId, auth.organizationId))
      .groupBy(leadSourceSubmissions.source)

    const bySource = new Map(counts.map((c) => [c.source, c]))

    const data = LEAD_SOURCE_ORDER.map((key) => {
      const def = LEAD_SOURCES[key]
      const stats = bySource.get(key)
      return {
        key: def.key,
        label: def.label,
        description: def.description,
        columns: def.columns,
        required: def.required,
        total: stats?.total ?? 0,
        last_received_at: stats?.lastReceivedAt ?? null,
      }
    })

    return Response.json({ data })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Erro interno.')
  }
}
