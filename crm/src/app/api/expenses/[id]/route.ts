import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { expenses } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

function effectiveStatus(status: string, dueDate: Date): string {
  if (status === 'pending' && new Date(dueDate) < new Date()) return 'overdue'
  return status
}

function toSnake(e: typeof expenses.$inferSelect) {
  return {
    id: e.id,
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

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const updates: Record<string, any> = { updatedAt: new Date() }
    if (body.description !== undefined) updates.description = String(body.description).trim()
    if (body.category !== undefined) updates.category = String(body.category).trim() || 'outros'
    if (body.amount !== undefined) updates.amount = String(Number(body.amount))
    if (body.due_date !== undefined) updates.dueDate = new Date(body.due_date)
    if (body.payee !== undefined) updates.payee = body.payee?.trim() || null
    if (body.notes !== undefined) updates.notes = body.notes?.trim() || null
    if (body.recurrence_end_date !== undefined) {
      updates.recurrenceEndDate = body.recurrence_end_date ? new Date(body.recurrence_end_date) : null
    }
    if (body.status !== undefined) {
      updates.status = body.status
      // paid_at é controlado pelo backend, nunca aceito do client
      updates.paidAt = body.status === 'paid' ? new Date() : null
    }

    const [expense] = await db
      .update(expenses)
      .set(updates)
      .where(and(eq(expenses.id, id), eq(expenses.organizationId, auth.organizationId), isNull(expenses.deletedAt)))
      .returning()

    if (!expense) return apiError(404, 'Despesa não encontrada.')
    return Response.json({ data: toSnake(expense) })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    await db
      .update(expenses)
      .set({ deletedAt: new Date() })
      .where(and(eq(expenses.id, id), eq(expenses.organizationId, auth.organizationId)))

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
