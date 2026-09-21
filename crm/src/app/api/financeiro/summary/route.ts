import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { orders, expenses } from '@/lib/schema'
import { eq, and, gte, lt, isNull, asc, sql, SQL } from 'drizzle-orm'
import { startOfDay, startOfMonth, endOfMonth, subDays, addDays, subHours, eachHourOfInterval, eachDayOfInterval } from 'date-fns'
import { ensureRecurringInstallments } from '@/lib/expenses-recurrence'

type Period = 'day' | 'week' | 'month'
type Bucket = 'hour' | 'day'

function resolveRange(period: Period, now: Date): { from: Date; to: Date; bucket: Bucket } {
  const to = addDays(startOfDay(now), 1)
  if (period === 'day') return { from: startOfDay(now), to, bucket: 'hour' }
  if (period === 'week') return { from: startOfDay(subDays(now, 6)), to, bucket: 'day' }
  return { from: startOfMonth(now), to, bucket: 'day' }
}

function bucketTrunc(column: SQL.Aliased | any, bucket: Bucket) {
  return bucket === 'hour' ? sql<string>`date_trunc('hour', ${column})` : sql<string>`date_trunc('day', ${column})`
}

function effectiveStatus(status: string, dueDate: Date | string): string {
  if (status === 'pending' && new Date(dueDate) < new Date()) return 'overdue'
  return status
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const orgId = auth.organizationId
    await ensureRecurringInstallments(orgId)

    const params = req.nextUrl.searchParams
    const period = (params.get('period') || 'day') as Period
    if (!['day', 'week', 'month'].includes(period)) return apiError(400, 'period inválido. Use day, week ou month.')

    const now = new Date()
    const { from, to, bucket } = resolveRange(period, now)
    const todayFrom = startOfDay(now)
    const todayTo = addDays(todayFrom, 1)
    const monthFrom = startOfMonth(now)
    const monthTo = endOfMonth(now)

    // ── Totais acumulados (desde o início, sem saldo inicial configurável) ──
    const [orderAllTime] = await db.select({
      paidTotal: sql<string>`coalesce(sum(${orders.totalValue}) filter (where ${orders.paymentStatus} = 'paid'), 0)`,
      refundedTotal: sql<string>`coalesce(sum(${orders.totalValue}) filter (where ${orders.paymentStatus} = 'refunded'), 0)`,
    }).from(orders).where(and(eq(orders.organizationId, orgId), isNull(orders.deletedAt)))

    const [expenseAllTime] = await db.select({
      paidTotal: sql<string>`coalesce(sum(${expenses.amount}) filter (where ${expenses.status} = 'paid'), 0)`,
    }).from(expenses).where(and(eq(expenses.organizationId, orgId), isNull(expenses.deletedAt)))

    const accumulatedBalance = Number(orderAllTime.paidTotal) - Number(orderAllTime.refundedTotal) - Number(expenseAllTime.paidTotal)

    // ── Estatísticas do período selecionado ──
    const [periodOrders] = await db.select({
      revenueTotal: sql<string>`coalesce(sum(${orders.totalValue}) filter (where ${orders.paymentStatus} = 'paid'), 0)`,
      ordersCount: sql<number>`count(*) filter (where ${orders.paymentStatus} = 'paid')::int`,
      refundedTotal: sql<string>`coalesce(sum(${orders.totalValue}) filter (where ${orders.paymentStatus} = 'refunded'), 0)`,
    }).from(orders).where(and(eq(orders.organizationId, orgId), isNull(orders.deletedAt), gte(orders.createdAt, from), lt(orders.createdAt, to)))

    const [periodExpenses] = await db.select({
      paidTotal: sql<string>`coalesce(sum(${expenses.amount}) filter (where ${expenses.status} = 'paid'), 0)`,
    }).from(expenses).where(and(
      eq(expenses.organizationId, orgId), isNull(expenses.deletedAt),
      gte(expenses.paidAt, from), lt(expenses.paidAt, to),
    ))

    const inflow = Number(periodOrders.revenueTotal)
    const outflow = Number(periodExpenses.paidTotal) + Number(periodOrders.refundedTotal)

    // ── Fixos do dia (não mudam com o seletor de período) ──
    const [todayOrders] = await db.select({
      salesCount: sql<number>`count(*)::int`,
      refundedTotal: sql<string>`coalesce(sum(${orders.totalValue}) filter (where ${orders.paymentStatus} = 'refunded'), 0)`,
    }).from(orders).where(and(eq(orders.organizationId, orgId), isNull(orders.deletedAt), gte(orders.createdAt, todayFrom), lt(orders.createdAt, todayTo)))

    const [todayExpenses] = await db.select({
      paidTotal: sql<string>`coalesce(sum(${expenses.amount}) filter (where ${expenses.status} = 'paid'), 0)`,
    }).from(expenses).where(and(
      eq(expenses.organizationId, orgId), isNull(expenses.deletedAt),
      gte(expenses.paidAt, todayFrom), lt(expenses.paidAt, todayTo),
    ))

    const expensesTodayTotal = Number(todayExpenses.paidTotal) + Number(todayOrders.refundedTotal)

    // ── Passivo do mês corrente (sempre o mês atual, independente do período selecionado) ──
    const [liabilityTotals] = await db.select({
      monthTotal: sql<string>`coalesce(sum(${expenses.amount}) filter (where ${expenses.status} = 'pending' and ${expenses.dueDate} >= ${monthFrom} and ${expenses.dueDate} <= ${monthTo}), 0)`,
      overdueTotal: sql<string>`coalesce(sum(${expenses.amount}) filter (where ${expenses.status} = 'pending' and ${expenses.dueDate} < ${now}), 0)`,
    }).from(expenses).where(and(eq(expenses.organizationId, orgId), isNull(expenses.deletedAt)))

    const upcomingRows = await db.select().from(expenses)
      .where(and(eq(expenses.organizationId, orgId), isNull(expenses.deletedAt), eq(expenses.status, 'pending')))
      .orderBy(asc(expenses.dueDate))
      .limit(8)

    const upcoming = upcomingRows.map(e => ({
      id: e.id,
      description: e.description,
      category: e.category,
      amount: e.amount,
      due_date: e.dueDate,
      effective_status: effectiveStatus(e.status, e.dueDate),
    }))

    // ── Dinheiro pendente de repasse (motoboy recebeu, ainda não passou pra empresa) ──
    // Saldo corrente, não filtra por período — representa dinheiro que ainda não voltou.
    const [cashPendingTotals] = await db.select({
      total: sql<string>`coalesce(sum(${orders.totalValue}), 0)`,
      count: sql<number>`count(*)::int`,
    }).from(orders).where(and(
      eq(orders.organizationId, orgId), isNull(orders.deletedAt),
      eq(orders.paymentMethod, 'dinheiro'), eq(orders.paymentStatus, 'paid'), eq(orders.cashSettled, false),
    ))

    const cashPendingRows = await db.select().from(orders)
      .where(and(
        eq(orders.organizationId, orgId), isNull(orders.deletedAt),
        eq(orders.paymentMethod, 'dinheiro'), eq(orders.paymentStatus, 'paid'), eq(orders.cashSettled, false),
      ))
      .orderBy(asc(orders.createdAt))
      .limit(20)

    const cash_pending = {
      total: cashPendingTotals.total,
      count: cashPendingTotals.count,
      orders: cashPendingRows.map(o => ({
        id: o.id,
        customer_name: o.customerName,
        total_value: o.totalValue,
        created_at: o.createdAt,
      })),
    }

    // ── Série temporal para os gráficos ──
    const orderSeries = await db.select({
      bucket: bucketTrunc(orders.createdAt, bucket),
      inflow: sql<string>`coalesce(sum(${orders.totalValue}) filter (where ${orders.paymentStatus} = 'paid'), 0)`,
      refunded: sql<string>`coalesce(sum(${orders.totalValue}) filter (where ${orders.paymentStatus} = 'refunded'), 0)`,
      salesCount: sql<number>`count(*) filter (where ${orders.paymentStatus} = 'paid')::int`,
    }).from(orders)
      .where(and(eq(orders.organizationId, orgId), isNull(orders.deletedAt), gte(orders.createdAt, from), lt(orders.createdAt, to)))
      .groupBy(bucketTrunc(orders.createdAt, bucket))

    const expenseSeries = await db.select({
      bucket: bucketTrunc(expenses.paidAt, bucket),
      outflow: sql<string>`coalesce(sum(${expenses.amount}), 0)`,
    }).from(expenses)
      .where(and(
        eq(expenses.organizationId, orgId), isNull(expenses.deletedAt), eq(expenses.status, 'paid'),
        gte(expenses.paidAt, from), lt(expenses.paidAt, to),
      ))
      .groupBy(bucketTrunc(expenses.paidAt, bucket))

    const seriesMap = new Map<string, { inflow: number; outflow: number; sales_count: number }>()
    for (const row of orderSeries) {
      const key = new Date(row.bucket).toISOString()
      const entry = seriesMap.get(key) || { inflow: 0, outflow: 0, sales_count: 0 }
      entry.inflow += Number(row.inflow)
      entry.outflow += Number(row.refunded)
      entry.sales_count += Number(row.salesCount)
      seriesMap.set(key, entry)
    }
    for (const row of expenseSeries) {
      const key = new Date(row.bucket).toISOString()
      const entry = seriesMap.get(key) || { inflow: 0, outflow: 0, sales_count: 0 }
      entry.outflow += Number(row.outflow)
      seriesMap.set(key, entry)
    }

    const bucketDates = bucket === 'hour'
      ? eachHourOfInterval({ start: from, end: subHours(to, 1) })
      : eachDayOfInterval({ start: from, end: subDays(to, 1) })

    const time_series = bucketDates.map(d => {
      const entry = seriesMap.get(d.toISOString()) || { inflow: 0, outflow: 0, sales_count: 0 }
      return {
        date: d.toISOString(),
        inflow: entry.inflow.toFixed(2),
        outflow: entry.outflow.toFixed(2),
        sales_count: entry.sales_count,
      }
    })

    // ── Breakdowns ──
    const paymentMethodRows = await db.select({
      method: orders.paymentMethod,
      total: sql<string>`coalesce(sum(${orders.totalValue}), 0)`,
    }).from(orders)
      .where(and(eq(orders.organizationId, orgId), isNull(orders.deletedAt), eq(orders.paymentStatus, 'paid'), gte(orders.createdAt, from), lt(orders.createdAt, to)))
      .groupBy(orders.paymentMethod)

    const payment_methods = paymentMethodRows
      .map(r => ({ method: r.method, total: r.total, pct: inflow > 0 ? Math.round((Number(r.total) / inflow) * 1000) / 10 : 0 }))
      .sort((a, b) => Number(b.total) - Number(a.total))

    const categoryRows = await db.select({
      category: expenses.category,
      total: sql<string>`coalesce(sum(${expenses.amount}), 0)`,
    }).from(expenses)
      .where(and(
        eq(expenses.organizationId, orgId), isNull(expenses.deletedAt), eq(expenses.status, 'paid'),
        gte(expenses.paidAt, from), lt(expenses.paidAt, to),
      ))
      .groupBy(expenses.category)

    const expenseOutflowTotal = Number(periodExpenses.paidTotal)
    const expenses_by_category = categoryRows
      .map(r => ({ category: r.category, total: r.total, pct: expenseOutflowTotal > 0 ? Math.round((Number(r.total) / expenseOutflowTotal) * 1000) / 10 : 0 }))
      .sort((a, b) => Number(b.total) - Number(a.total))

    return Response.json({
      data: {
        period: { type: period, from: from.toISOString(), to: new Date(to.getTime() - 1).toISOString() },
        revenue: { total: periodOrders.revenueTotal, orders_count: periodOrders.ordersCount },
        inflow: inflow.toFixed(2),
        outflow: outflow.toFixed(2),
        balance: (inflow - outflow).toFixed(2),
        accumulated_balance: accumulatedBalance.toFixed(2),
        sales_today_count: todayOrders.salesCount,
        expenses_today_total: expensesTodayTotal.toFixed(2),
        liabilities: {
          month_total: liabilityTotals.monthTotal,
          overdue_total: liabilityTotals.overdueTotal,
          upcoming,
        },
        cash_pending,
        time_series,
        payment_methods,
        expenses_by_category,
      },
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
