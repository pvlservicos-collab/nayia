/**
 * GET /api/metrics/dashboard — os números da tela Início.
 *
 * Substitui os dados de demonstração que a tela usava (src/components/Dashboard/
 * mockData.ts). Tudo aqui sai de contagem no banco; onde não há dado ainda, o
 * número é 0 — nunca um valor inventado, porque um dashboard que mostra número
 * plausível e falso é pior que um zerado: ninguém percebe que está errado.
 *
 * `?dias=` recorta o período (padrão 30). Só afeta as séries e os totais do
 * período; o total de leads por fonte é histórico e ignora o recorte.
 */
import { NextRequest } from 'next/server'
import { and, eq, gte, inArray, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import {
  leadSourceSubmissions, leads, orders, orderItems, leadActivities,
  funnelExecutions, funnelResponseEvents, messageFunnels,
} from '@/lib/schema'
import { LEAD_SOURCES, ACQUISITION_SOURCE_ORDER } from '@/lib/leadSources'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const org = auth.organizationId

    const dias = Math.min(Math.max(Number(req.nextUrl.searchParams.get('dias')) || 30, 1), 365)
    const desde = new Date(Date.now() - dias * 24 * 60 * 60 * 1000)

    const [
      porFonte,
      porDia,
      totaisLead,
      compras,
      produtos,
      atividades,
      execucoes,
      respostas,
      topMensagens,
    ] = await Promise.all([
      // Total histórico por fonte — alimenta os cards de "canais de aquisição".
      db.select({
        source: leadSourceSubmissions.source,
        total: sql<number>`count(*)::int`,
      })
        .from(leadSourceSubmissions)
        .where(and(
          eq(leadSourceSubmissions.organizationId, org),
          inArray(leadSourceSubmissions.source, ACQUISITION_SOURCE_ORDER)
        ))
        .groupBy(leadSourceSubmissions.source),

      // Série diária por fonte, dentro do período.
      db.select({
        dia: sql<string>`to_char(${leadSourceSubmissions.receivedAt}, 'YYYY-MM-DD')`,
        source: leadSourceSubmissions.source,
        total: sql<number>`count(*)::int`,
      })
        .from(leadSourceSubmissions)
        .where(and(
          eq(leadSourceSubmissions.organizationId, org),
          inArray(leadSourceSubmissions.source, ACQUISITION_SOURCE_ORDER),
          gte(leadSourceSubmissions.receivedAt, desde)
        ))
        .groupBy(sql`1`, leadSourceSubmissions.source)
        .orderBy(sql`1`),

      // Leads do CRM: total e quantos entraram no período.
      db.select({
        total: sql<number>`count(*)::int`,
        noPeriodo: sql<number>`count(*) filter (where ${leads.createdAt} >= ${desde})::int`,
      })
        .from(leads)
        .where(and(eq(leads.organizationId, org), isNull(leads.deletedAt))),

      // Só pedido PAGO conta como venda — pedido pendente é intenção, não receita.
      db.select({
        vendas: sql<number>`count(*)::int`,
        valor: sql<string>`coalesce(sum(${orders.totalValue}), 0)::text`,
      })
        .from(orders)
        .where(and(
          eq(orders.organizationId, org),
          eq(orders.paymentStatus, 'paid'),
          isNull(orders.deletedAt),
          gte(orders.createdAt, desde)
        )),

      db.select({ itens: sql<number>`coalesce(sum(${orderItems.quantity}), 0)::int` })
        .from(orderItems)
        .innerJoin(orders, eq(orders.id, orderItems.orderId))
        .where(and(
          eq(orders.organizationId, org),
          eq(orders.paymentStatus, 'paid'),
          isNull(orders.deletedAt),
          gte(orders.createdAt, desde)
        )),

      // Mensagens trocadas no período, separadas por quem mandou.
      db.select({
        recebidas: sql<number>`count(*) filter (where ${leadActivities.metadata}->>'direction' = 'inbound')::int`,
        enviadas: sql<number>`count(*) filter (where ${leadActivities.metadata}->>'direction' = 'outbound')::int`,
        automaticas: sql<number>`count(*) filter (where ${leadActivities.metadata}->>'source' = 'funnel')::int`,
        leadsQueResponderam: sql<number>`count(distinct ${leadActivities.leadId}) filter (where ${leadActivities.metadata}->>'direction' = 'inbound')::int`,
      })
        .from(leadActivities)
        .where(and(
          eq(leadActivities.organizationId, org),
          gte(leadActivities.createdAt, desde)
        )),

      db.select({ total: sql<number>`count(*)::int` })
        .from(funnelExecutions)
        .where(and(
          eq(funnelExecutions.organizationId, org),
          gte(funnelExecutions.startedAt, desde)
        )),

      // Ramo "sim" da condição = o lead respondeu dentro da janela do funil.
      db.select({
        responderam: sql<number>`count(*) filter (where ${funnelResponseEvents.branch} = 'yes')::int`,
        naoResponderam: sql<number>`count(*) filter (where ${funnelResponseEvents.branch} = 'no')::int`,
      })
        .from(funnelResponseEvents)
        .innerJoin(funnelExecutions, eq(funnelExecutions.id, funnelResponseEvents.executionId))
        .where(eq(funnelExecutions.organizationId, org)),

      // Mensagens de funil que mais renderam resposta.
      db.select({
        funil: messageFunnels.name,
        enviadas: sql<number>`count(*)::int`,
      })
        .from(leadActivities)
        .innerJoin(messageFunnels, sql`${messageFunnels.id}::text = ${leadActivities.metadata}->>'funnel_id'`)
        .where(and(
          eq(leadActivities.organizationId, org),
          gte(leadActivities.createdAt, desde)
        ))
        .groupBy(messageFunnels.name)
        .orderBy(sql`2 desc`)
        .limit(5),
    ])

    const totalPorFonte = new Map(porFonte.map((r) => [r.source, r.total]))

    // Série no formato que o gráfico espera: um ponto por dia com uma chave por
    // fonte. Dias sem lead precisam existir, senão a linha "pula" o vazio e dá a
    // impressão de continuidade onde não houve nada.
    const serie: Record<string, Record<string, number | string>> = {}
    for (let i = dias - 1; i >= 0; i--) {
      const d = new Date(Date.now() - i * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
      serie[d] = { date: d }
      for (const key of ACQUISITION_SOURCE_ORDER) serie[d][key] = 0
    }
    for (const linha of porDia) {
      if (serie[linha.dia]) serie[linha.dia][linha.source] = linha.total
    }

    const msgs = atividades[0] ?? { recebidas: 0, enviadas: 0, automaticas: 0, leadsQueResponderam: 0 }
    const resp = respostas[0] ?? { responderam: 0, naoResponderam: 0 }

    return Response.json({
      data: {
        periodo_dias: dias,
        fontes: ACQUISITION_SOURCE_ORDER.map((key) => ({
          channel: key,
          label: LEAD_SOURCES[key].label,
          newCustomers: totalPorFonte.get(key) ?? 0,
        })),
        serie_diaria: Object.values(serie),
        leads: {
          total: totaisLead[0]?.total ?? 0,
          no_periodo: totaisLead[0]?.noPeriodo ?? 0,
        },
        compras: {
          salesCount: compras[0]?.vendas ?? 0,
          productsSold: produtos[0]?.itens ?? 0,
          totalValue: Number(compras[0]?.valor ?? 0),
        },
        mensagens: {
          recebidas: msgs.recebidas,
          enviadas: msgs.enviadas,
          automaticas: msgs.automaticas,
        },
        follow_up: {
          initialRepliesCount: msgs.leadsQueResponderam,
          followUpsSentCount: msgs.automaticas,
          followUpRepliesCount: resp.responderam,
          semResposta: resp.naoResponderam,
          execucoes: execucoes[0]?.total ?? 0,
        },
        top_funis: topMensagens.map((t) => ({ name: t.funil, sentCount: t.enviadas })),
      },
    })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[metrics/dashboard] falhou:', err)
    return apiError(500, 'Erro ao calcular as métricas.')
  }
}
