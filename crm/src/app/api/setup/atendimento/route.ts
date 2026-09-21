/**
 * POST /api/setup/atendimento — cria a configuração padrão de atendimento:
 * o pipeline com as quatro colunas e os dois funis de mensagem das fontes.
 *
 * Idempotente: reexecutar não duplica nada. Etapa e funil são procurados por
 * nome/gatilho antes de criar, então rodar de novo depois de acrescentar uma
 * fonte cria só o que falta. O que já existe NÃO é sobrescrito — se alguém
 * editou a mensagem de follow-up na tela, um segundo POST não desfaz isso.
 *
 * O conteúdo (nomes das colunas, textos, os 15 minutos) vem de
 * src/lib/defaultAtendimento.ts, que é a mesma fonte usada pelos dados demo.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import {
  pipelines, pipelineStages, messageFunnels, funnelBlocks, funnelConnections,
} from '@/lib/schema'
import {
  DEFAULT_FUNNELS, DEFAULT_PIPELINE_NAME, DEFAULT_STAGES, type StageKey,
} from '@/lib/defaultAtendimento'

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const organizationId = auth.organizationId
    const criados: string[] = []

    // ── Pipeline ──
    let [pipeline] = await db
      .select({ id: pipelines.id })
      .from(pipelines)
      .where(and(
        eq(pipelines.organizationId, organizationId),
        eq(pipelines.name, DEFAULT_PIPELINE_NAME),
        isNull(pipelines.deletedAt)
      ))
      .limit(1)

    if (!pipeline) {
      ;[pipeline] = await db.insert(pipelines).values({
        organizationId,
        name: DEFAULT_PIPELINE_NAME,
      }).returning({ id: pipelines.id })
      criados.push(`pipeline "${DEFAULT_PIPELINE_NAME}"`)
    }

    // ── Etapas ──
    const stageIdByKey = {} as Record<StageKey, string>
    for (const stage of DEFAULT_STAGES) {
      const [existing] = await db
        .select({ id: pipelineStages.id })
        .from(pipelineStages)
        .where(and(
          eq(pipelineStages.pipelineId, pipeline.id),
          eq(pipelineStages.name, stage.name),
          isNull(pipelineStages.deletedAt)
        ))
        .limit(1)

      if (existing) {
        stageIdByKey[stage.key] = existing.id
        continue
      }

      const [created] = await db.insert(pipelineStages).values({
        organizationId,
        pipelineId: pipeline.id,
        name: stage.name,
        color: stage.color,
        rank: String(stage.rank),
      }).returning({ id: pipelineStages.id })
      stageIdByKey[stage.key] = created.id
      criados.push(`etapa "${stage.name}"`)
    }

    // ── Funis ──
    for (const funnel of DEFAULT_FUNNELS) {
      const [existing] = await db
        .select({ id: messageFunnels.id })
        .from(messageFunnels)
        .where(and(
          eq(messageFunnels.organizationId, organizationId),
          eq(messageFunnels.trigger, funnel.trigger as any),
          isNull(messageFunnels.deletedAt)
        ))
        .limit(1)

      // Já existe funil pra esse gatilho: não mexe. Reexecutar o setup não pode
      // desfazer edição feita na tela.
      if (existing) continue

      const [created] = await db.insert(messageFunnels).values({
        organizationId,
        name: funnel.name,
        trigger: funnel.trigger as any,
        // Nasce desligado de propósito: ativar dispara mensagem pra cliente de
        // verdade. Quem liga é uma pessoa, na tela, depois de ler os textos.
        isActive: false,
      }).returning({ id: messageFunnels.id })

      const blockIdByKey: Record<string, string> = {}
      for (const block of funnel.blocks) {
        const config: Record<string, unknown> = { ...(block.config ?? {}) }
        if (block.stage) {
          config.stageId = stageIdByKey[block.stage]
          config.stageName = DEFAULT_STAGES.find((s) => s.key === block.stage)?.name ?? ''
        }
        if (block.type === 'trigger') config.trigger = funnel.trigger

        const [insertedBlock] = await db.insert(funnelBlocks).values({
          funnelId: created.id,
          type: block.type as any,
          config,
          positionX: String(block.x),
          positionY: String(block.y),
        }).returning({ id: funnelBlocks.id })
        blockIdByKey[block.key] = insertedBlock.id
      }

      for (const conn of funnel.connections) {
        await db.insert(funnelConnections).values({
          funnelId: created.id,
          sourceBlockId: blockIdByKey[conn.from],
          targetBlockId: blockIdByKey[conn.to],
          branch: conn.branch,
        })
      }

      criados.push(`funil "${funnel.name}" (desligado)`)
    }

    return Response.json({
      data: {
        pipeline_id: pipeline.id,
        stages: stageIdByKey,
        criados,
        ja_existiam: criados.length === 0,
      },
    })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[setup/atendimento] falhou:', err)
    return apiError(500, 'Erro ao criar a configuração de atendimento.')
  }
}
