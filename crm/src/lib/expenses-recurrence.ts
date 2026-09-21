import { and, desc, eq, gte, isNull, or, sql } from 'drizzle-orm'
import { addMonths, addWeeks, addYears, endOfMonth, getDaysInMonth, setDate } from 'date-fns'
import { db } from './db'
import { expenses } from './schema'

function addInterval(date: Date, interval: string): Date {
  switch (interval) {
    case 'weekly': return addWeeks(date, 1)
    case 'yearly': return addYears(date, 1)
    case 'monthly':
    default: return addMonths(date, 1)
  }
}

function clampToRecurrenceDay(date: Date, recurrenceDay: number | null): Date {
  if (!recurrenceDay) return date
  const day = Math.min(recurrenceDay, getDaysInMonth(date))
  return setDate(date, day)
}

/**
 * Gera, sob demanda, as parcelas de despesas recorrentes que ainda faltam até o fim do mês
 * corrente. Idempotente: parcelas duplicadas caem no índice único parcial (parent_expense_id, due_date)
 * e são ignoradas via ON CONFLICT DO NOTHING.
 */
export async function ensureRecurringInstallments(organizationId: string): Promise<void> {
  const now = new Date()
  const horizon = endOfMonth(now)

  const roots = await db
    .select()
    .from(expenses)
    .where(and(
      eq(expenses.organizationId, organizationId),
      eq(expenses.isRecurring, true),
      isNull(expenses.deletedAt),
      or(isNull(expenses.recurrenceEndDate), gte(expenses.recurrenceEndDate, now)),
    ))

  for (const root of roots) {
    if (!root.recurrenceInterval) continue

    const [lastChild] = await db
      .select({ dueDate: expenses.dueDate })
      .from(expenses)
      .where(and(eq(expenses.parentExpenseId, root.id), isNull(expenses.deletedAt)))
      .orderBy(desc(expenses.dueDate))
      .limit(1)

    let cursor = lastChild?.dueDate ?? root.dueDate
    const newRows: (typeof expenses.$inferInsert)[] = []
    let next = clampToRecurrenceDay(addInterval(cursor, root.recurrenceInterval), root.recurrenceDay)

    while (next <= horizon && (!root.recurrenceEndDate || next <= root.recurrenceEndDate)) {
      newRows.push({
        organizationId,
        description: root.description,
        category: root.category,
        amount: root.amount,
        dueDate: next,
        status: 'pending',
        payee: root.payee,
        notes: root.notes,
        isRecurring: false,
        parentExpenseId: root.id,
      })
      cursor = next
      next = clampToRecurrenceDay(addInterval(cursor, root.recurrenceInterval), root.recurrenceDay)
    }

    if (newRows.length > 0) {
      await db.insert(expenses).values(newRows).onConflictDoNothing({
        target: [expenses.parentExpenseId, expenses.dueDate],
        where: sql`${expenses.parentExpenseId} is not null and ${expenses.deletedAt} is null`,
      })
    }
  }
}
