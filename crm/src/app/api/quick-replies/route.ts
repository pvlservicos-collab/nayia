import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { quickReplies, quickReplySteps } from '@/lib/schema'
import { eq, and, or, isNull, asc, inArray } from 'drizzle-orm'
import { canManageSharedQuickReplies } from './permissions'

/**
 * GET /api/quick-replies
 * Lista a biblioteca compartilhada da organização + os atalhos pessoais do membro autenticado.
 */
export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)

    const rows = await db
      .select()
      .from(quickReplies)
      .where(
        and(
          eq(quickReplies.organizationId, auth.organizationId),
          isNull(quickReplies.deletedAt),
          or(
            eq(quickReplies.scope, 'shared'),
            and(eq(quickReplies.scope, 'personal'), eq(quickReplies.createdByMemberId, auth.memberId || ''))
          )
        )
      )
      .orderBy(asc(quickReplies.category), asc(quickReplies.shortcut))

    // Resposta sem nenhuma linha em quick_reply_steps é uma sequência implícita de 1
    // passo (o próprio content/media_url dela) — só quem tem steps de verdade os usa.
    const ids = rows.map((r) => r.id)
    const stepRows = ids.length
      ? await db.select().from(quickReplySteps).where(inArray(quickReplySteps.quickReplyId, ids)).orderBy(asc(quickReplySteps.position))
      : []
    const stepsByParent = new Map<string, typeof stepRows>()
    for (const s of stepRows) {
      if (!stepsByParent.has(s.quickReplyId)) stepsByParent.set(s.quickReplyId, [])
      stepsByParent.get(s.quickReplyId)!.push(s)
    }
    const withSteps = rows.map((r) => ({ ...r, steps: stepsByParent.get(r.id) || [] }))

    return Response.json({
      data: {
        shared: withSteps.filter((r) => r.scope === 'shared'),
        personal: withSteps.filter((r) => r.scope === 'personal'),
      },
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

function normalizeShortcut(raw: string): string {
  return raw.trim().replace(/^\/+/, '')
}

/** Cada passo precisa de texto ou mídia, igual a regra de uma resposta única. */
function validateSteps(rawSteps: any[]): string | null {
  for (let i = 0; i < rawSteps.length; i++) {
    const step = rawSteps[i]
    const stepContent = typeof step?.content === 'string' ? step.content : ''
    if (!stepContent.trim() && !step?.mediaUrl) {
      return `Passo ${i + 1}: informe um texto ou anexe uma mídia.`
    }
  }
  return null
}

/**
 * POST /api/quick-replies
 * Cria uma resposta rápida. scope='shared' exige permissão manage_quick_replies;
 * scope='personal' é sempre gravado como dono o próprio membro autenticado.
 */
export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const body = await req.json()

    const scope = body.scope === 'shared' ? 'shared' : 'personal'
    const shortcut = normalizeShortcut(String(body.shortcut || ''))
    const content = typeof body.content === 'string' ? body.content : ''
    const mediaUrl = body.mediaUrl || null
    const rawSteps: any[] = Array.isArray(body.steps) ? body.steps : []
    const hasSteps = rawSteps.length > 0

    if (!shortcut) return apiError(400, 'Informe um atalho (ex: promo-fim-de-ano).')
    if (/\s/.test(shortcut)) return apiError(400, 'O atalho não pode conter espaços.')
    if (hasSteps) {
      const stepsError = validateSteps(rawSteps)
      if (stepsError) return apiError(400, stepsError)
    } else if (!content.trim() && !mediaUrl) {
      return apiError(400, 'Informe um texto ou anexe uma mídia.')
    }

    if (scope === 'shared') {
      const canManage = await canManageSharedQuickReplies(auth.roleId)
      if (!canManage) return apiError(403, 'Você não tem permissão para gerenciar a biblioteca compartilhada.')
    } else if (!auth.memberId) {
      return apiError(400, 'Atalhos pessoais exigem um membro autenticado.')
    }

    try {
      const [created] = await db
        .insert(quickReplies)
        .values({
          organizationId: auth.organizationId,
          scope,
          createdByMemberId: scope === 'personal' ? auth.memberId : (auth.memberId || null),
          shortcut,
          category: body.category?.trim() || null,
          content,
          mediaUrl,
          mediaType: body.mediaType || null,
          mediaMimetype: body.mediaMimetype || null,
          mediaFilename: body.mediaFilename || null,
        })
        .returning()

      // Sem transaction (driver neon-http não suporta) — insere um passo de cada vez.
      const insertedSteps = []
      for (let i = 0; i < rawSteps.length; i++) {
        const step = rawSteps[i]
        const [row] = await db
          .insert(quickReplySteps)
          .values({
            quickReplyId: created.id,
            position: i,
            content: typeof step.content === 'string' ? step.content : '',
            mediaUrl: step.mediaUrl || null,
            mediaType: step.mediaType || null,
            mediaMimetype: step.mediaMimetype || null,
            mediaFilename: step.mediaFilename || null,
            delaySeconds: Number(step.delaySeconds) || 0,
          })
          .returning()
        insertedSteps.push(row)
      }

      return Response.json({ data: { ...created, steps: insertedSteps } }, { status: 201 })
    } catch (err: any) {
      if (err?.code === '23505') return apiError(409, `Já existe um atalho "/${shortcut}".`)
      throw err
    }
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
