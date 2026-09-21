import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { orderStatusHistory, organizationMembers, profiles } from '@/lib/schema'
import { eq, and, desc } from 'drizzle-orm'

/**
 * GET /api/orders/[id]/history
 * Linha do tempo de mudanças de status (pagamento e entrega) de um pedido,
 * com data/hora e responsável — base do rastreamento na Logística.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const rows = await db
      .select({
        id: orderStatusHistory.id,
        field: orderStatusHistory.field,
        fromStatus: orderStatusHistory.fromStatus,
        toStatus: orderStatusHistory.toStatus,
        changedAt: orderStatusHistory.changedAt,
        actorName: profiles.fullName,
      })
      .from(orderStatusHistory)
      .leftJoin(organizationMembers, eq(organizationMembers.id, orderStatusHistory.changedByMemberId))
      .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
      .where(and(eq(orderStatusHistory.orderId, id), eq(orderStatusHistory.organizationId, auth.organizationId)))
      .orderBy(desc(orderStatusHistory.changedAt))

    return Response.json({
      data: rows.map(r => ({
        id: r.id,
        field: r.field,
        from_status: r.fromStatus,
        to_status: r.toStatus,
        changed_at: r.changedAt,
        actor_name: r.actorName || null,
      })),
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
