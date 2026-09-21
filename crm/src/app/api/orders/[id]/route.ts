import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { orders, orderItems, products, orderStatusHistory } from '@/lib/schema'
import { eq, and, inArray, isNull } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { syncLeadLastOrderAttributes } from '@/lib/db-helpers'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [order] = await db
      .select()
      .from(orders)
      .where(and(eq(orders.id, id), eq(orders.organizationId, auth.organizationId), isNull(orders.deletedAt)))
      .limit(1)

    if (!order) return apiError(404, 'Pedido não encontrado.')

    const items = await db
      .select()
      .from(orderItems)
      .where(eq(orderItems.orderId, id))

    const productIds = [...new Set(items.map(i => i.productId).filter(Boolean))] as string[]
    let productNameById = new Map<string, string>()
    if (productIds.length > 0) {
      const productRows = await db
        .select({ id: products.id, name: products.name })
        .from(products)
        .where(inArray(products.id, productIds))
      productNameById = new Map(productRows.map(p => [p.id, p.name]))
    }

    return Response.json({ data: {
      id: order.id,
      payment_method: order.paymentMethod,
      payment_status: order.paymentStatus,
      delivery_status: order.deliveryStatus,
      total_value: order.totalValue,
      notes: order.notes,
      customer_name: order.customerName,
      customer_phone: order.customerPhone,
      customer_email: order.customerEmail,
      customer_cpf: order.customerCpf,
      customer_cep: order.customerCep,
      customer_address: order.customerAddress,
      customer_address_number: order.customerAddressNumber,
      customer_address_complement: order.customerAddressComplement,
      customer_neighborhood: order.customerNeighborhood,
      customer_city: order.customerCity,
      customer_state: order.customerState,
      cash_settled: order.cashSettled,
      cash_settled_at: order.cashSettledAt,
      created_at: order.createdAt,
      updated_at: order.updatedAt,
      delivered_at: order.deliveredAt,
      items: items.map(i => ({
        id: i.id,
        product_id: i.productId,
        product_name: (i.productId && productNameById.get(i.productId)) || i.productName,
        quantity: i.quantity,
        unit_price: i.unitPrice,
      })),
    }})
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const [existing] = await db
      .select({ paymentStatus: orders.paymentStatus, deliveryStatus: orders.deliveryStatus })
      .from(orders)
      .where(and(eq(orders.id, id), eq(orders.organizationId, auth.organizationId), isNull(orders.deletedAt)))
      .limit(1)

    if (!existing) return apiError(404, 'Pedido não encontrado.')

    const updates: Record<string, any> = { updatedAt: new Date() }
    if (body.payment_status !== undefined) updates.paymentStatus = body.payment_status
    if (body.delivery_status !== undefined) {
      updates.deliveryStatus = body.delivery_status
      // delivered_at é sempre calculado pelo servidor, nunca aceito do client
      updates.deliveredAt = body.delivery_status === 'delivered' ? new Date() : null
    }
    if (body.payment_method !== undefined) updates.paymentMethod = body.payment_method
    if (body.notes !== undefined) updates.notes = body.notes
    if (body.total_value !== undefined) updates.totalValue = body.total_value

    // Endereço de entrega — editável pelo vendedor (Chat) e pela Logística
    const addressFields = ['customer_cep', 'customer_address', 'customer_address_number', 'customer_address_complement', 'customer_neighborhood', 'customer_city', 'customer_state']
    const addressChanged = addressFields.some(f => body[f] !== undefined)
    if (body.customer_cep !== undefined) updates.customerCep = body.customer_cep
    if (body.customer_address !== undefined) updates.customerAddress = body.customer_address
    if (body.customer_address_number !== undefined) updates.customerAddressNumber = body.customer_address_number
    if (body.customer_address_complement !== undefined) updates.customerAddressComplement = body.customer_address_complement
    if (body.customer_neighborhood !== undefined) updates.customerNeighborhood = body.customer_neighborhood
    if (body.customer_city !== undefined) updates.customerCity = body.customer_city
    if (body.customer_state !== undefined) updates.customerState = body.customer_state

    // Repasse do dinheiro físico que o motoboy coletou — ação de confirmação, não
    // precisa suportar desfazer (não existe "desmarcar repassado").
    if (body.cash_settled === true) {
      updates.cashSettled = true
      updates.cashSettledAt = new Date()
    }

    const [order] = await db
      .update(orders)
      .set(updates)
      .where(and(eq(orders.id, id), eq(orders.organizationId, auth.organizationId), isNull(orders.deletedAt)))
      .returning()

    if (!order) return apiError(404, 'Pedido não encontrado.')

    // Rastreamento de status — só grava evento quando o valor realmente muda
    const historyRows: (typeof orderStatusHistory.$inferInsert)[] = []
    if (body.payment_status !== undefined && body.payment_status !== existing.paymentStatus) {
      historyRows.push({
        organizationId: auth.organizationId, orderId: order.id, field: 'payment_status',
        fromStatus: existing.paymentStatus, toStatus: order.paymentStatus, changedByMemberId: auth.memberId || null,
      })
    }
    if (body.delivery_status !== undefined && body.delivery_status !== existing.deliveryStatus) {
      historyRows.push({
        organizationId: auth.organizationId, orderId: order.id, field: 'delivery_status',
        fromStatus: existing.deliveryStatus, toStatus: order.deliveryStatus, changedByMemberId: auth.memberId || null,
      })
    }
    if (historyRows.length > 0) await db.insert(orderStatusHistory).values(historyRows)

    // Mantém a etiqueta "Pago/Pendente" da lista de conversas em dia e avisa
    // quem estiver com o Chat aberto (lista + perfil do cliente) em tempo real.
    if (order.leadId && (body.payment_status !== undefined || addressChanged)) {
      await syncLeadLastOrderAttributes(
        auth.organizationId, order.leadId, order.paymentStatus, order.paymentMethod,
        addressChanged ? {
          cep: order.customerCep,
          address: order.customerAddress,
          addressNumber: order.customerAddressNumber,
          addressComplement: order.customerAddressComplement,
          neighborhood: order.customerNeighborhood,
          city: order.customerCity,
          state: order.customerState,
        } : undefined,
        order.id
      )
    }
    if (order.leadId) {
      await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id: order.leadId })
    }

    return Response.json({ data: {
      id: order.id,
      payment_method: order.paymentMethod,
      payment_status: order.paymentStatus,
      delivery_status: order.deliveryStatus,
      total_value: order.totalValue,
      notes: order.notes,
      customer_name: order.customerName,
      customer_phone: order.customerPhone,
      customer_cep: order.customerCep,
      customer_address: order.customerAddress,
      customer_address_number: order.customerAddressNumber,
      customer_address_complement: order.customerAddressComplement,
      customer_neighborhood: order.customerNeighborhood,
      customer_city: order.customerCity,
      customer_state: order.customerState,
      cash_settled: order.cashSettled,
      cash_settled_at: order.cashSettledAt,
      created_at: order.createdAt,
      updated_at: order.updatedAt,
      delivered_at: order.deliveredAt,
    }})
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [order] = await db
      .update(orders)
      .set({ deletedAt: new Date() })
      .where(and(eq(orders.id, id), eq(orders.organizationId, auth.organizationId), isNull(orders.deletedAt)))
      .returning()

    if (!order) return apiError(404, 'Pedido não encontrado.')
    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
