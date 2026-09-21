import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { orders, orderItems, leads, products, orderStatusHistory } from '@/lib/schema'
import { eq, and, desc, gte, lte, inArray, isNull } from 'drizzle-orm'
import { publishEvent, channels, events } from '@/lib/realtime'
import { syncLeadLastOrderAttributes } from '@/lib/db-helpers'

function toSnake(o: any, items: any[] = [], productNameById: Map<string, string> = new Map()) {
  return {
    id: o.id,
    organization_id: o.organizationId,
    lead_id: o.leadId,
    payment_method: o.paymentMethod,
    payment_status: o.paymentStatus,
    delivery_status: o.deliveryStatus,
    total_value: o.totalValue,
    notes: o.notes,
    customer_name: o.customerName,
    customer_phone: o.customerPhone,
    customer_email: o.customerEmail,
    customer_cpf: o.customerCpf,
    customer_cep: o.customerCep,
    customer_address: o.customerAddress,
    customer_address_number: o.customerAddressNumber,
    customer_address_complement: o.customerAddressComplement,
    customer_neighborhood: o.customerNeighborhood,
    customer_city: o.customerCity,
    customer_state: o.customerState,
    cash_settled: o.cashSettled,
    cash_settled_at: o.cashSettledAt,
    created_at: o.createdAt,
    updated_at: o.updatedAt,
    delivered_at: o.deliveredAt,
    items: items.map(i => ({
      id: i.id,
      order_id: i.orderId,
      product_id: i.productId,
      // Prefere o nome atual do produto (via product_id); cai pro nome congelado no pedido
      // quando o item não tem produto vinculado (digitado à mão) ou o produto não existe mais.
      product_name: (i.productId && productNameById.get(i.productId)) || i.productName,
      quantity: i.quantity,
      unit_price: i.unitPrice,
      created_at: i.createdAt,
    })),
  }
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const params = req.nextUrl.searchParams
    const paymentStatus = params.get('payment_status')
    const deliveryStatus = params.get('delivery_status')
    const leadId = params.get('lead_id')
    const from = params.get('from')
    const to = params.get('to')
    const limit = Math.min(Number(params.get('limit') || 100), 500)
    const offset = Number(params.get('offset') || 0)

    const conditions: any[] = [eq(orders.organizationId, auth.organizationId), isNull(orders.deletedAt)]
    if (paymentStatus) conditions.push(eq(orders.paymentStatus, paymentStatus))
    if (deliveryStatus) conditions.push(eq(orders.deliveryStatus, deliveryStatus))
    if (leadId) conditions.push(eq(orders.leadId, leadId))
    if (from) conditions.push(gte(orders.createdAt, new Date(from)))
    if (to) conditions.push(lte(orders.createdAt, new Date(to)))

    const rows = await db
      .select()
      .from(orders)
      .where(and(...conditions))
      .orderBy(desc(orders.createdAt))
      .limit(limit)
      .offset(offset)

    let allItems: any[] = []
    if (rows.length > 0) {
      allItems = await db
        .select()
        .from(orderItems)
        .where(eq(orderItems.organizationId, auth.organizationId))
    }

    const itemsByOrder = allItems.reduce((acc: Record<string, any[]>, item) => {
      if (!acc[item.orderId]) acc[item.orderId] = []
      acc[item.orderId].push(item)
      return acc
    }, {})

    const productIds = [...new Set(allItems.map(i => i.productId).filter(Boolean))] as string[]
    let productNameById = new Map<string, string>()
    if (productIds.length > 0) {
      const productRows = await db
        .select({ id: products.id, name: products.name })
        .from(products)
        .where(inArray(products.id, productIds))
      productNameById = new Map(productRows.map(p => [p.id, p.name]))
    }

    const data = rows.map(o => toSnake(o, itemsByOrder[o.id] || [], productNameById))

    return Response.json({ data })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    if (!body.items || body.items.length === 0) {
      return apiError(400, 'Pedido deve ter pelo menos 1 item.')
    }

    const totalValue = body.items.reduce(
      (sum: number, item: any) => sum + (Number(item.unit_price) * Number(item.quantity || 1)),
      0
    )

    const deliveryStatus = body.delivery_status || 'pending'
    const orderDate = body.order_date ? new Date(body.order_date) : undefined
    if (orderDate && isNaN(orderDate.getTime())) {
      return apiError(400, 'Data do pedido inválida.')
    }

    const [order] = await db
      .insert(orders)
      .values({
        organizationId: auth.organizationId,
        leadId: body.lead_id || null,
        paymentMethod: body.payment_method || 'pix',
        paymentStatus: body.payment_status || 'pending',
        deliveryStatus,
        totalValue: body.total_value ?? totalValue,
        notes: body.notes || null,
        customerName: body.customer_name || null,
        customerPhone: body.customer_phone || null,
        customerEmail: body.customer_email || null,
        customerCpf: body.customer_cpf || null,
        customerCep: body.customer_cep || null,
        customerAddress: body.customer_address || null,
        customerAddressNumber: body.customer_address_number || null,
        customerAddressComplement: body.customer_address_complement || null,
        customerNeighborhood: body.customer_neighborhood || null,
        customerCity: body.customer_city || null,
        customerState: body.customer_state || null,
        // Dinheiro nasce "pendente de repasse" (motoboy ainda não passou o físico pra
        // empresa); os outros métodos não passam por essa custódia, nascem resolvidos.
        cashSettled: (body.payment_method || 'pix') !== 'dinheiro',
        ...(orderDate ? { createdAt: orderDate } : {}),
        deliveredAt: deliveryStatus === 'delivered' ? new Date() : null,
      })
      .returning()

    const itemValues = body.items.map((item: any) => ({
      orderId: order.id,
      organizationId: auth.organizationId,
      productId: item.product_id || null,
      productName: item.product_name,
      quantity: item.quantity || 1,
      unitPrice: item.unit_price,
    }))

    const insertedItems = await db.insert(orderItems).values(itemValues).returning()

    // Marca o início do rastreamento de status (pagamento e entrega) deste pedido
    await db.insert(orderStatusHistory).values([
      {
        organizationId: auth.organizationId,
        orderId: order.id,
        field: 'payment_status',
        fromStatus: null,
        toStatus: order.paymentStatus,
        changedByMemberId: auth.memberId || null,
      },
      {
        organizationId: auth.organizationId,
        orderId: order.id,
        field: 'delivery_status',
        fromStatus: null,
        toStatus: order.deliveryStatus,
        changedByMemberId: auth.memberId || null,
      },
    ])

    // Salva último status do pedido no lead para exibir tags na lista, e avisa
    // quem estiver com o Chat aberto (lista de conversas + perfil do cliente)
    if (body.lead_id) {
      await syncLeadLastOrderAttributes(auth.organizationId, body.lead_id, order.paymentStatus, order.paymentMethod, {
        cep: order.customerCep,
        address: order.customerAddress,
        addressNumber: order.customerAddressNumber,
        addressComplement: order.customerAddressComplement,
        neighborhood: order.customerNeighborhood,
        city: order.customerCity,
        state: order.customerState,
      }, order.id)
      await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id: body.lead_id })
    }

    return Response.json({ data: toSnake(order, insertedItems) }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
