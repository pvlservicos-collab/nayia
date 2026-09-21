import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { notifications } from '@/lib/schema'
import { eq, and, desc, inArray } from 'drizzle-orm'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.memberId) return apiError(403, 'Necessário sessão de usuário.')
    const rows = await db.select().from(notifications)
      .where(and(
        eq(notifications.organizationId, auth.organizationId),
        eq(notifications.recipientMemberId, auth.memberId),
        eq(notifications.isRead, false)
      ))
      .orderBy(desc(notifications.createdAt))
      .limit(50)

    const data = rows.map(n => ({
      id: n.id,
      organization_id: n.organizationId,
      recipient_member_id: n.recipientMemberId,
      type: n.type,
      title: n.title,
      content: n.body,
      link_url: (n.metadata as any)?.linkUrl || null,
      is_read: n.isRead,
      created_at: n.createdAt,
    }))

    return Response.json({ data })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.memberId) return apiError(403, 'Necessário sessão de usuário.')
    const body = await req.json()
    const [notif] = await db.insert(notifications).values({
      organizationId: auth.organizationId,
      recipientMemberId: body.recipient_member_id || auth.memberId,
      type: body.type || 'info',
      title: body.title || '',
      body: body.body || '',
      metadata: body.metadata || {},
      isRead: false,
    }).returning()
    return Response.json({ data: notif }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function PATCH(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.memberId) return apiError(403, 'Necessário sessão de usuário.')
    const body = await req.json()
    if (body.markAllAsRead) {
      await db.update(notifications).set({ isRead: true })
        .where(and(eq(notifications.organizationId, auth.organizationId), eq(notifications.recipientMemberId, auth.memberId)))
    } else if (Array.isArray(body.ids) && body.ids.length > 0) {
      await db.update(notifications).set({ isRead: true })
        .where(inArray(notifications.id, body.ids))
    }
    return Response.json({ success: true })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
