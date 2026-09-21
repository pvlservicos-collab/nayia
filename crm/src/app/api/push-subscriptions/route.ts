import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { pushSubscriptions } from '@/lib/schema'
import { eq, and } from 'drizzle-orm'

/**
 * POST /api/push-subscriptions
 * Registra (ou atualiza, se o endpoint já existir) a inscrição de push do
 * navegador/aparelho atual. Upsert por endpoint — não por membro, porque um mesmo
 * aparelho compartilhado pode trocar de dono ao longo do tempo.
 */
export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.memberId) return apiError(403, 'Necessário sessão de usuário.')
    const body = await req.json()

    const endpoint = body.endpoint
    const p256dh = body.keys?.p256dh
    const authKey = body.keys?.auth
    if (!endpoint || !p256dh || !authKey) return apiError(400, 'Inscrição de push inválida.')

    await db
      .insert(pushSubscriptions)
      .values({
        organizationId: auth.organizationId,
        memberId: auth.memberId,
        endpoint,
        p256dh,
        auth: authKey,
        userAgent: body.userAgent || null,
      })
      .onConflictDoUpdate({
        target: pushSubscriptions.endpoint,
        set: {
          organizationId: auth.organizationId,
          memberId: auth.memberId,
          p256dh,
          auth: authKey,
          userAgent: body.userAgent || null,
          lastSeenAt: new Date(),
        },
      })

    return Response.json({ success: true }, { status: 201 })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * DELETE /api/push-subscriptions?endpoint=...
 * Remove a inscrição de push do aparelho atual (usuário desativou nas configurações).
 */
export async function DELETE(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.memberId) return apiError(403, 'Necessário sessão de usuário.')
    const endpoint = req.nextUrl.searchParams.get('endpoint')
    if (!endpoint) return apiError(400, 'Informe o endpoint da inscrição.')

    await db.delete(pushSubscriptions).where(and(eq(pushSubscriptions.endpoint, endpoint), eq(pushSubscriptions.memberId, auth.memberId)))

    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
