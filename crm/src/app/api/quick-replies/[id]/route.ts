import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { quickReplies, quickReplySteps } from '@/lib/schema'
import { eq, and, isNull, asc } from 'drizzle-orm'
import { canManageSharedQuickReplies } from '../permissions'

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

type Params = { params: Promise<{ id: string }> }

async function loadOwned(id: string, organizationId: string) {
  const [existing] = await db
    .select()
    .from(quickReplies)
    .where(and(eq(quickReplies.id, id), eq(quickReplies.organizationId, organizationId), isNull(quickReplies.deletedAt)))
    .limit(1)
  return existing
}

async function assertCanMutate(existing: { scope: string; createdByMemberId: string | null }, auth: { memberId: string | null; roleId: string | null }) {
  if (existing.scope === 'shared') {
    const canManage = await canManageSharedQuickReplies(auth.roleId)
    if (!canManage) throw { status: 403, message: 'Você não tem permissão para gerenciar a biblioteca compartilhada.' }
  } else if (existing.createdByMemberId !== auth.memberId) {
    throw { status: 403, message: 'Você só pode editar seus próprios atalhos.' }
  }
}

/**
 * PATCH /api/quick-replies/[id]
 * scope é imutável após a criação — só o conteúdo, atalho, categoria e mídia podem mudar.
 */
export async function PATCH(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const existing = await loadOwned(id, auth.organizationId)
    if (!existing) return apiError(404, 'Resposta rápida não encontrada.')
    await assertCanMutate(existing, auth)

    const updates: any = { updatedAt: new Date() }
    if (body.shortcut !== undefined) {
      const shortcut = String(body.shortcut).trim().replace(/^\/+/, '')
      if (!shortcut) return apiError(400, 'Informe um atalho.')
      if (/\s/.test(shortcut)) return apiError(400, 'O atalho não pode conter espaços.')
      updates.shortcut = shortcut
    }
    if (body.category !== undefined) updates.category = body.category?.trim() || null
    if (body.content !== undefined) updates.content = body.content
    if (body.mediaUrl !== undefined) updates.mediaUrl = body.mediaUrl || null
    if (body.mediaType !== undefined) updates.mediaType = body.mediaType || null
    if (body.mediaMimetype !== undefined) updates.mediaMimetype = body.mediaMimetype || null
    if (body.mediaFilename !== undefined) updates.mediaFilename = body.mediaFilename || null

    // 'steps' presente no body (mesmo vazio) substitui a sequência inteira — vazio
    // significa "voltar a ser resposta única", usando content/mediaUrl do próprio pai.
    const hasStepsField = 'steps' in body
    const rawSteps: any[] = hasStepsField && Array.isArray(body.steps) ? body.steps : []

    if (hasStepsField && rawSteps.length > 0) {
      const stepsError = validateSteps(rawSteps)
      if (stepsError) return apiError(400, stepsError)
    } else if (updates.content !== undefined || updates.mediaUrl !== undefined || (hasStepsField && rawSteps.length === 0)) {
      const nextContent = updates.content !== undefined ? updates.content : existing.content
      const nextMediaUrl = updates.mediaUrl !== undefined ? updates.mediaUrl : existing.mediaUrl
      if (!String(nextContent || '').trim() && !nextMediaUrl) {
        return apiError(400, 'Informe um texto ou anexe uma mídia.')
      }
    }

    try {
      const [updated] = await db
        .update(quickReplies)
        .set(updates)
        .where(eq(quickReplies.id, id))
        .returning()

      // Sem transaction (driver neon-http não suporta) — substitui a sequência inteira:
      // apaga os passos antigos e reinsere a lista nova, um de cada vez, na ordem certa.
      if (hasStepsField) {
        await db.delete(quickReplySteps).where(eq(quickReplySteps.quickReplyId, id))
        for (let i = 0; i < rawSteps.length; i++) {
          const step = rawSteps[i]
          await db.insert(quickReplySteps).values({
            quickReplyId: id,
            position: i,
            content: typeof step.content === 'string' ? step.content : '',
            mediaUrl: step.mediaUrl || null,
            mediaType: step.mediaType || null,
            mediaMimetype: step.mediaMimetype || null,
            mediaFilename: step.mediaFilename || null,
            delaySeconds: Number(step.delaySeconds) || 0,
          })
        }
      }

      const currentSteps = await db
        .select()
        .from(quickReplySteps)
        .where(eq(quickReplySteps.quickReplyId, id))
        .orderBy(asc(quickReplySteps.position))

      return Response.json({ data: { ...updated, steps: currentSteps } })
    } catch (err: any) {
      if (err?.code === '23505') return apiError(409, `Já existe um atalho "/${updates.shortcut}".`)
      throw err
    }
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * DELETE /api/quick-replies/[id] — soft delete via deletedAt.
 */
export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const existing = await loadOwned(id, auth.organizationId)
    if (!existing) return apiError(404, 'Resposta rápida não encontrada.')
    await assertCanMutate(existing, auth)

    await db.update(quickReplies).set({ deletedAt: new Date() }).where(eq(quickReplies.id, id))
    return Response.json({ success: true })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
