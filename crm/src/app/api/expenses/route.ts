import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { expenses } from '@/lib/schema'
import { eq, and, gte, lte, isNull, desc, asc } from 'drizzle-orm'
import { ensureRecurringInstallments } from '@/lib/expenses-recurrence'

const RECURRENCE_INTERVALS = new Set(['weekly', 'monthly', 'yearly'])

function effectiveStatus(status: string, dueDate: Date): string {
  if (status === 'pending' && new Date(dueDate) < new Date()) return 'overdue'
  return status
}

function toSnake(e: typeof expenses.$inferSelect) {
  return {
    id: e.id,
    organization_id: e.organizationId,
    description: e.description,
    category: e.category,
    amount: e.amount,
    due_date: e.dueDate,
    status: e.status,
    effective_status: effectiveStatus(e.status, e.dueDate),
    paid_at: e.paidAt,
    payee: e.payee,
    notes: e.notes,
    is_recurring: e.isRecurring,
    recurrence_interval: e.recurrenceInterval,
    recurrence_day: e.recurrenceDay,
    recurrence_end_date: e.recurrenceEndDate,
    parent_expense_id: e.parentExpenseId,
    created_at: e.createdAt,
    updated_at: e.updatedAt,
  }
}

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    await ensureRecurringInstallments(auth.organizationId)

    const params = req.nextUrl.searchParams
    const status = params.get('status')
    const category = params.get('category')
    const isRecurring = params.get('is_recurring')
    const from = params.get('from')
    const to = params.get('to')
    const limit = Math.min(Number(params.get('limit') || 200), 500)
    const offset = Number(params.get('offset') || 0)

    const conditions: any[] = [eq(expenses.organizationId, auth.organizationId), isNull(expenses.deletedAt)]
    if (status) conditions.push(eq(expenses.status, status))
    if (category) conditions.push(eq(expenses.category, category))
    if (isRecurring !== null) conditions.push(eq(expenses.isRecurring, isRecurring === 'true'))
    if (from) conditions.push(gte(expenses.dueDate, new Date(from)))
    if (to) conditions.push(lte(expenses.dueDate, new Date(to)))

    const rows = await db
      .select()
      .from(expenses)
      .where(and(...conditions))
      .orderBy(asc(expenses.dueDate))
      .limit(limit)
      .offset(offset)

    return Response.json({ data: rows.map(toSnake) })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    if (!body.description || !String(body.description).trim()) {
      return apiError(400, 'Descrição é obrigatória.')
    }
    const amount = Number(body.amount)
    if (isNaN(amount) || amount <= 0) {
      return apiError(400, 'Valor inválido.')
    }
    const dueDate = body.due_date ? new Date(body.due_date) : null
    if (!dueDate || isNaN(dueDate.getTime())) {
      return apiError(400, 'Data de vencimento inválida.')
    }
    const isRecurring = !!body.is_recurring
    if (isRecurring && !RECURRENCE_INTERVALS.has(body.recurrence_interval)) {
      return apiError(400, 'Intervalo de recorrência inválido. Use weekly, monthly ou yearly.')
    }
    // Permite registrar um gasto que já foi pago no momento da criação (ex: compra pontual do dia),
    // sem precisar do passo separado de "marcar como pago". paid_at nunca vem do client.
    const alreadyPaid = body.status === 'paid'

    const [expense] = await db
      .insert(expenses)
      .values({
        organizationId: auth.organizationId,
        description: String(body.description).trim(),
        category: body.category ? String(body.category).trim() : 'outros',
        amount: String(amount),
        dueDate,
        status: alreadyPaid ? 'paid' : 'pending',
        paidAt: alreadyPaid ? new Date() : null,
        payee: body.payee?.trim() || null,
        notes: body.notes?.trim() || null,
        isRecurring,
        recurrenceInterval: isRecurring ? body.recurrence_interval : null,
        recurrenceDay: isRecurring ? (body.recurrence_day ?? dueDate.getDate()) : null,
        recurrenceEndDate: isRecurring && body.recurrence_end_date ? new Date(body.recurrence_end_date) : null,
        createdByMemberId: auth.memberId,
      })
      .returning()

    return Response.json({ data: toSnake(expense) }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
