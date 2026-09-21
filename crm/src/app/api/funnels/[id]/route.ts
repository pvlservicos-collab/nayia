import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { messageFunnels, funnelBlocks, funnelConnections } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'

const VALID_TRIGGERS = ['novo_pago', 'novo_recuperacao']
const VALID_BLOCK_TYPES = ['trigger', 'message', 'wait', 'condition', 'end']
const VALID_BRANCHES = ['default', 'yes', 'no']

/**
 * GET /api/funnels/[id]
 * Retorna o funil com seus blocos e conexões.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [funnel] = await db.select().from(messageFunnels)
      .where(and(eq(messageFunnels.id, id), eq(messageFunnels.organizationId, auth.organizationId), isNull(messageFunnels.deletedAt)))
      .limit(1)
    if (!funnel) return apiError(404, 'Funil não encontrado.')

    const blocks = await db.select().from(funnelBlocks).where(eq(funnelBlocks.funnelId, id))
    const connections = await db.select().from(funnelConnections).where(eq(funnelConnections.funnelId, id))

    return Response.json({ data: { ...funnel, blocks, connections } })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * PATCH /api/funnels/[id]
 * Atualiza nome, status ativo e/ou a estrutura (blocos + conexões) do funil.
 * Ao enviar `blocks`/`connections`, a estrutura anterior é substituída por completo.
 */
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()

    const [funnel] = await db.select({ id: messageFunnels.id, trigger: messageFunnels.trigger }).from(messageFunnels)
      .where(and(eq(messageFunnels.id, id), eq(messageFunnels.organizationId, auth.organizationId), isNull(messageFunnels.deletedAt)))
      .limit(1)
    if (!funnel) return apiError(404, 'Funil não encontrado.')

    const updates: Record<string, any> = { updatedAt: new Date() }
    if (body.name !== undefined) updates.name = body.name
    if (body.isActive !== undefined) {
      updates.isActive = !!body.isActive
    }
    if (body.trigger !== undefined) {
      if (!VALID_TRIGGERS.includes(body.trigger)) return apiError(400, `Gatilho inválido. Valores aceitos: ${VALID_TRIGGERS.join(', ')}`)
      updates.trigger = body.trigger
    }

    if (Array.isArray(body.blocks)) {
      for (const b of body.blocks) {
        if (!VALID_BLOCK_TYPES.includes(b.type)) return apiError(400, `Tipo de bloco inválido: "${b.type}"`)
      }
      if (Array.isArray(body.connections)) {
        for (const c of body.connections) {
          if (c.branch && !VALID_BRANCHES.includes(c.branch)) return apiError(400, `Ramo inválido: "${c.branch}"`)
        }
      }

      const existingBlocks = await db.select({ id: funnelBlocks.id }).from(funnelBlocks).where(eq(funnelBlocks.funnelId, id))
      const existingIds = new Set(existingBlocks.map((b) => b.id))

      // Atualiza blocos existentes (preservando o id) e insere os novos
      const idMap = new Map<string, string>()
      const keptIds = new Set<string>()
      for (const b of body.blocks) {
        const blockId = String(b.id)
        if (existingIds.has(blockId)) {
          await db.update(funnelBlocks).set({
            type: b.type,
            config: b.config || {},
            positionX: String(b.position?.x ?? 0),
            positionY: String(b.position?.y ?? 0),
          }).where(eq(funnelBlocks.id, blockId))
          idMap.set(blockId, blockId)
          keptIds.add(blockId)
        } else {
          const [inserted] = await db.insert(funnelBlocks).values({
            funnelId: id,
            type: b.type,
            config: b.config || {},
            positionX: String(b.position?.x ?? 0),
            positionY: String(b.position?.y ?? 0),
          }).returning({ id: funnelBlocks.id })
          idMap.set(blockId, inserted.id)
          keptIds.add(inserted.id)
        }
      }

      // Remove blocos que não existem mais (cascade remove conexões antigas)
      for (const existingId of existingIds) {
        if (!keptIds.has(existingId)) {
          await db.delete(funnelBlocks).where(eq(funnelBlocks.id, existingId))
        }
      }

      // Substitui conexões pela lista atual
      await db.delete(funnelConnections).where(eq(funnelConnections.funnelId, id))

      if (Array.isArray(body.connections) && body.connections.length > 0) {
        const rows = body.connections
          .map((c: any) => ({
            funnelId: id,
            sourceBlockId: idMap.get(String(c.source)),
            targetBlockId: idMap.get(String(c.target)),
            branch: c.branch || 'default',
          }))
          .filter((c: any) => c.sourceBlockId && c.targetBlockId)

        if (rows.length > 0) await db.insert(funnelConnections).values(rows)
      }
    }

    await db.update(messageFunnels).set(updates).where(eq(messageFunnels.id, id))

    return Response.json({ status: 'ok' })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}

/**
 * DELETE /api/funnels/[id]
 * Remove (soft delete) o funil.
 */
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [funnel] = await db.select({ id: messageFunnels.id, trigger: messageFunnels.trigger }).from(messageFunnels)
      .where(and(eq(messageFunnels.id, id), eq(messageFunnels.organizationId, auth.organizationId), isNull(messageFunnels.deletedAt)))
      .limit(1)
    if (!funnel) return apiError(404, 'Funil não encontrado.')

    await db.update(messageFunnels).set({ deletedAt: new Date(), isActive: false }).where(eq(messageFunnels.id, id))

    return Response.json({ status: 'ok' })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
