import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { messageFunnels, funnelBlocks, funnelExecutions, leadActivities, funnelClickEvents } from '@/lib/schema'
import { eq, and, isNull, sql } from 'drizzle-orm'

const VALID_TRIGGERS = ['novo_pago', 'novo_recuperacao']

/**
 * GET /api/funnels
 * Lista os funis de mensagens da organização com métricas resumidas.
 */
export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)

    const funnels = await db.select().from(messageFunnels)
      .where(and(eq(messageFunnels.organizationId, auth.organizationId), isNull(messageFunnels.deletedAt)))
      .orderBy(messageFunnels.createdAt)

    const data = await Promise.all(funnels.map(async (funnel) => {
      const [{ count: entradas }] = await db.select({ count: sql<number>`count(*)::int` })
        .from(funnelExecutions).where(eq(funnelExecutions.funnelId, funnel.id))

      const [{ count: mensagens }] = await db.select({ count: sql<number>`count(*)::int` })
        .from(leadActivities).where(sql`${leadActivities.metadata}->>'funnel_id' = ${funnel.id}`)

      const [{ total: cliquesTotal, clicados: cliquesClicados }] = await db.select({
        total: sql<number>`count(*)::int`,
        clicados: sql<number>`count(*) filter (where ${funnelClickEvents.clicked})::int`,
      }).from(funnelClickEvents)
        .innerJoin(funnelExecutions, eq(funnelExecutions.id, funnelClickEvents.executionId))
        .where(eq(funnelExecutions.funnelId, funnel.id))

      return {
        id: funnel.id,
        name: funnel.name,
        trigger: funnel.trigger,
        is_active: funnel.isActive,
        created_at: funnel.createdAt,
        metrics: {
          entradas,
          mensagens_enviadas: mensagens,
          cliques: cliquesClicados,
          cliques_total: cliquesTotal,
          taxa_clique: cliquesTotal > 0 ? cliquesClicados / cliquesTotal : 0,
        },
      }
    }))

    return Response.json({ data })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * POST /api/funnels
 * Cria um novo funil com um bloco "trigger" inicial.
 */
export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    const requiredError = validateRequired(body, ['name', 'trigger'])
    if (requiredError) return apiError(400, requiredError)
    if (!VALID_TRIGGERS.includes(body.trigger)) {
      return apiError(400, `Gatilho inválido. Valores aceitos: ${VALID_TRIGGERS.join(', ')}`)
    }

    const [funnel] = await db.insert(messageFunnels).values({
      organizationId: auth.organizationId,
      name: body.name,
      trigger: body.trigger,
      isActive: false,
    }).returning()

    await db.insert(funnelBlocks).values({
      funnelId: funnel.id,
      type: 'trigger',
      config: {},
      positionX: '50',
      positionY: '50',
    })

    return Response.json({ data: funnel }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
