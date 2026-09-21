import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { messageFunnels, funnelExecutions, funnelClickEvents, funnelResponseEvents, leadActivities } from '@/lib/schema'
import { eq, and, isNull, sql } from 'drizzle-orm'

/**
 * GET /api/funnels/[id]/metrics
 * Métricas por bloco: quanto saiu, quanto entregou, cliques e respostas.
 *
 * `enviado` sai de `lead_activities`, que é onde o disparo do funil grava cada
 * mensagem com o `block_id` dentro do metadata — não existe tabela de envio
 * separada, e nem precisa: a mensagem enviada JÁ é uma atividade do lead.
 *
 * Não existe "aberto"/"visualizado" aqui de propósito. Ninguém registra recibo
 * de leitura no CRM ainda, e uma coluna dessas com número inventado é pior que
 * coluna nenhuma — quem olha toma decisão em cima dela.
 *
 * `variantes` é o teste A/B/C: quantos receberam cada versão do texto e quantos
 * RESPONDERAM.
 *
 * Resposta é atribuída à mensagem que veio logo antes dela: a primeira entrada
 * do lead depois do disparo, em até 7 dias, sem nenhuma mensagem NOSSA no meio.
 * "Qualquer entrada depois" seria mais simples e estaria errado — quem já
 * conversava com a gente responderia "sempre", e toda versão marcaria 100%.
 */
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params

    const [funnel] = await db.select({ id: messageFunnels.id }).from(messageFunnels)
      .where(and(eq(messageFunnels.id, id), eq(messageFunnels.organizationId, auth.organizationId), isNull(messageFunnels.deletedAt)))
      .limit(1)
    if (!funnel) return apiError(404, 'Funil não encontrado.')

    // Quanto cada bloco disparou, e quanto disso a operadora aceitou.
    const envios = await db.select({
      blockId: sql<string>`${leadActivities.metadata}->>'block_id'`,
      enviado: sql<number>`count(*)::int`,
      entregue: sql<number>`count(*) filter (where ${leadActivities.metadata}->>'send_status' = 'sent')::int`,
      falhou: sql<number>`count(*) filter (where ${leadActivities.metadata}->>'send_status' = 'failed')::int`,
    }).from(leadActivities)
      .where(and(
        eq(leadActivities.organizationId, auth.organizationId),
        sql`${leadActivities.metadata}->>'funnel_id' = ${id}`,
        sql`${leadActivities.metadata}->>'block_id' IS NOT NULL`
      ))
      .groupBy(sql`${leadActivities.metadata}->>'block_id'`)

    /*
     * Teste A/B/C, por variante: envios e respostas.
     *
     * A resposta é procurada por lead e por horário: existe alguma mensagem
     * ENTRANDO daquele lead depois do disparo? Contar por conversa inteira
     * daria número inflado (quem já conversava responderia "sempre"), e contar
     * só a mensagem seguinte perderia quem respondeu duas horas depois.
     */
    const variantes = await db.execute(sql`
      WITH disparos AS (
        SELECT
          a.metadata->>'block_id' AS block_id,
          a.metadata->>'variante' AS variante,
          a.lead_id,
          a.created_at,
          a.metadata->>'send_status' AS send_status
        FROM lead_activities a
        WHERE a.organization_id = ${auth.organizationId}
          AND a.metadata->>'funnel_id' = ${id}
          AND a.metadata->>'variante' IS NOT NULL
      )
      SELECT
        d.block_id,
        d.variante,
        count(*)::int AS enviado,
        count(*) FILTER (WHERE d.send_status = 'sent')::int AS entregue,
        count(*) FILTER (WHERE EXISTS (
          SELECT 1 FROM lead_activities r
          WHERE r.lead_id = d.lead_id
            AND r.metadata->>'direction' = 'inbound'
            AND r.created_at > d.created_at
            AND r.created_at < d.created_at + interval '7 days'
            -- Nada NOSSO no meio: se outra mensagem saiu antes da resposta, a
            -- resposta é daquela, não desta. Sem este recorte, quem já
            -- conversava com a gente contava como "respondeu" em toda versão
            -- que recebesse, e o teste marcava 100% em tudo.
            AND NOT EXISTS (
              SELECT 1 FROM lead_activities m
              WHERE m.lead_id = d.lead_id
                AND m.metadata->>'direction' = 'outbound'
                AND m.created_at > d.created_at
                AND m.created_at < r.created_at
            )
        ))::int AS responderam
      FROM disparos d
      GROUP BY d.block_id, d.variante
      ORDER BY d.variante
    `)

    const clicks = await db.select({
      blockId: funnelClickEvents.blockId,
      total: sql<number>`count(*)::int`,
      clicados: sql<number>`count(*) filter (where ${funnelClickEvents.clicked})::int`,
    }).from(funnelClickEvents)
      .innerJoin(funnelExecutions, eq(funnelExecutions.id, funnelClickEvents.executionId))
      .where(eq(funnelExecutions.funnelId, id))
      .groupBy(funnelClickEvents.blockId)

    const responses = await db.select({
      blockId: funnelResponseEvents.blockId,
      branch: funnelResponseEvents.branch,
      total: sql<number>`count(*)::int`,
    }).from(funnelResponseEvents)
      .innerJoin(funnelExecutions, eq(funnelExecutions.id, funnelResponseEvents.executionId))
      .where(eq(funnelExecutions.funnelId, id))
      .groupBy(funnelResponseEvents.blockId, funnelResponseEvents.branch)

    const responsesByBlock: Record<string, { yes: number; no: number }> = {}
    for (const r of responses) {
      if (!responsesByBlock[r.blockId]) responsesByBlock[r.blockId] = { yes: 0, no: 0 }
      if (r.branch === 'yes') responsesByBlock[r.blockId].yes = r.total
      if (r.branch === 'no') responsesByBlock[r.blockId].no = r.total
    }

    return Response.json({
      data: {
        envios: envios.map((e) => ({
          block_id: e.blockId,
          enviado: e.enviado,
          entregue: e.entregue,
          falhou: e.falhou,
          taxa_entrega: e.enviado > 0 ? e.entregue / e.enviado : 0,
        })),
        variantes: (variantes.rows as {
          block_id: string; variante: string; enviado: number; entregue: number; responderam: number
        }[]).map((v) => ({
          block_id: v.block_id,
          variante: v.variante,
          enviado: v.enviado,
          entregue: v.entregue,
          responderam: v.responderam,
          taxa_resposta: v.entregue > 0 ? v.responderam / v.entregue : 0,
        })),
        clicks: clicks.map(c => ({ block_id: c.blockId, total: c.total, clicados: c.clicados, taxa: c.total > 0 ? c.clicados / c.total : 0 })),
        responses: Object.entries(responsesByBlock).map(([blockId, v]) => ({
          block_id: blockId,
          sim: v.yes,
          nao: v.no,
          taxa_resposta: (v.yes + v.no) > 0 ? v.yes / (v.yes + v.no) : 0,
        })),
      },
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
