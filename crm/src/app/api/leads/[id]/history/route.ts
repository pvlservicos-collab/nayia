import { NextRequest } from 'next/server'
import { authenticateRequest, apiError, validateRequired, validateSource } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, leadActivities, leadStageHistory, pipelineStages, orders, orderItems } from '@/lib/schema'
import { eq, and, isNull, asc, desc, inArray } from 'drizzle-orm'
import { isUniqueViolation } from '@/lib/db-helpers'

type Params = { params: Promise<{ id: string }> }

async function resolveLead(organizationId: string, id: string) {
  const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
  const [lead] = await db
    .select({ id: leads.id, createdAt: leads.createdAt, title: leads.title, value: leads.value })
    .from(leads)
    .where(and(
      isUuid ? eq(leads.id, id) : eq(leads.phone, decodeURIComponent(id)),
      eq(leads.organizationId, organizationId),
      isNull(leads.deletedAt)
    ))
    .limit(1)
  return lead
}

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const lead = await resolveLead(auth.organizationId, id)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    const activities = await db
      .select({
        id: leadActivities.id,
        type: leadActivities.type,
        content: leadActivities.content,
        metadata: leadActivities.metadata,
        actorMemberId: leadActivities.actorMemberId,
        createdAt: leadActivities.createdAt,
      })
      .from(leadActivities)
      .where(and(eq(leadActivities.leadId, lead.id), eq(leadActivities.organizationId, auth.organizationId)))
      .orderBy(desc(leadActivities.createdAt))

    const stageHistory = await db
      .select({
        id: leadStageHistory.id,
        fromStageId: leadStageHistory.fromStageId,
        toStageId: leadStageHistory.toStageId,
        movedAt: leadStageHistory.movedAt,
        movedByMemberId: leadStageHistory.movedByMemberId,
      })
      .from(leadStageHistory)
      .where(eq(leadStageHistory.leadId, lead.id))
      .orderBy(desc(leadStageHistory.movedAt))

    // Histórico de compras — para o vendedor ver o que o cliente já comprou
    const leadOrders = await db
      .select({
        id: orders.id,
        paymentStatus: orders.paymentStatus,
        totalValue: orders.totalValue,
        createdAt: orders.createdAt,
      })
      .from(orders)
      .where(and(eq(orders.leadId, lead.id), isNull(orders.deletedAt)))
      .orderBy(desc(orders.createdAt))

    const orderIds = leadOrders.map(o => o.id)
    const items = orderIds.length > 0
      ? await db
          .select({ orderId: orderItems.orderId, productName: orderItems.productName, quantity: orderItems.quantity })
          .from(orderItems)
          .where(inArray(orderItems.orderId, orderIds))
      : []

    const itemsByOrder = items.reduce((acc: Record<string, typeof items>, item) => {
      if (!acc[item.orderId]) acc[item.orderId] = []
      acc[item.orderId].push(item)
      return acc
    }, {})

    const ordersWithItems = leadOrders.map(o => ({
      id: o.id,
      paymentStatus: o.paymentStatus,
      totalValue: o.totalValue,
      createdAt: o.createdAt,
      items: (itemsByOrder[o.id] || []).map(i => ({ productName: i.productName, quantity: i.quantity })),
    }))

    return Response.json({
      data: activities,
      stageHistory,
      orders: ordersWithItems,
      lead: { createdAt: lead.createdAt, title: lead.title, value: lead.value },
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const requiredError = validateRequired(body, ['content', 'type', 'source'])
    if (requiredError) return apiError(400, requiredError)
    const sourceError = validateSource(body.source)
    if (sourceError) return apiError(400, sourceError)

    let lead = await resolveLead(auth.organizationId, id)
    const isUuid = /^[0-9a-f]{8}/.test(id)

    if (!lead) {
      if (isUuid) return apiError(404, 'Lead não encontrado.')

      const decodedPhone = decodeURIComponent(id)
      const [firstStage] = await db
        .select({ id: pipelineStages.id })
        .from(pipelineStages)
        .where(and(eq(pipelineStages.organizationId, auth.organizationId), isNull(pipelineStages.deletedAt)))
        .orderBy(asc(pipelineStages.rank))
        .limit(1)

      try {
        const [newLead] = await db.insert(leads).values({
          organizationId: auth.organizationId,
          title: decodedPhone,
          phone: decodedPhone,
          stageId: firstStage?.id || null,
          lastActivityAt: new Date(),
          customAttributes: { source: body.source },
        }).returning({ id: leads.id, createdAt: leads.createdAt, title: leads.title, value: leads.value })

        lead = newLead
      } catch (err) {
        // leads_org_phone_unique cobre corrida entre duas requisições simultâneas
        // pra esse mesmo telefone.
        if (!isUniqueViolation(err)) throw err
        const [raceLead] = await db
          .select({ id: leads.id, createdAt: leads.createdAt, title: leads.title, value: leads.value })
          .from(leads)
          .where(and(eq(leads.organizationId, auth.organizationId), eq(leads.phone, decodedPhone), isNull(leads.deletedAt)))
          .limit(1)
        if (!raceLead) throw err
        lead = raceLead
      }
    }

    const [activity] = await db.insert(leadActivities).values({
      organizationId: auth.organizationId,
      leadId: lead.id,
      actorMemberId: auth.memberId || null,
      type: body.type,
      content: body.content,
      metadata: { ...body.metadata, source: body.source },
    }).returning()

    await db.update(leads).set({
      lastActivityAt: new Date(),
      lastActivityType: body.type as any,
      lastActivityByMemberId: auth.memberId || null,
    }).where(eq(leads.id, lead.id))

    return Response.json(activity, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
