/**
 * GET /api/audit-log — registro de eventos do app, para compliance.
 *
 * Não existe uma tabela de auditoria: o histórico já está espalhado nas tabelas
 * que registram cada coisa (mensagens em `lead_activities`, leads recebidos em
 * `lead_source_submissions`, movimentação de card em `lead_stage_history`,
 * disparos em `funnel_executions`). Esta rota UNIFICA essas fontes numa linha do
 * tempo só, em vez de duplicar tudo numa tabela nova.
 *
 * A escolha é deliberada: uma tabela de auditoria paralela precisaria ser
 * alimentada em cada ponto de escrita do sistema, e bastaria um lugar esquecido
 * pro registro ficar com buraco — justamente o que compliance não tolera. Lendo
 * das tabelas de origem, o log reflete o que de fato aconteceu, sem depender de
 * ninguém lembrar de registrar.
 *
 * Filtros: `tipo` (mensagem_recebida, mensagem_enviada, lead_recebido,
 * lead_movido, funil_iniciado), `q` (busca no lead), `dias`, `limit`, `offset`.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'

const LIMITE_PADRAO = 100
const LIMITE_MAX = 500

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const org = auth.organizationId

    const url = req.nextUrl
    const limit = Math.min(Number(url.searchParams.get('limit')) || LIMITE_PADRAO, LIMITE_MAX)
    const offset = Math.max(Number(url.searchParams.get('offset')) || 0, 0)
    const dias = Math.min(Math.max(Number(url.searchParams.get('dias')) || 30, 1), 365)
    const tipo = url.searchParams.get('tipo')?.trim() || null
    const q = url.searchParams.get('q')?.trim() || null

    const desde = new Date(Date.now() - dias * 24 * 60 * 60 * 1000)
    const busca = q ? `%${q}%` : null

    // UNION ALL das fontes. Cada bloco entrega o mesmo shape (tipo, quando,
    // titulo, detalhe, lead) pra virar uma linha do tempo única.
    const eventos = await db.execute(sql`
      WITH eventos AS (
        -- Mensagens trocadas
        SELECT
          CASE WHEN a.metadata->>'direction' = 'inbound' THEN 'mensagem_recebida'
               ELSE 'mensagem_enviada' END       AS tipo,
          a.created_at                            AS quando,
          l.title                                 AS lead_nome,
          l.phone                                 AS lead_telefone,
          l.id                                    AS lead_id,
          left(coalesce(a.content, ''), 220)      AS detalhe,
          coalesce(a.metadata->>'source', a.type::text) AS origem,
          a.metadata->>'send_status'              AS status
        FROM lead_activities a
        LEFT JOIN leads l ON l.id = a.lead_id
        WHERE a.organization_id = ${org} AND a.created_at >= ${desde}

        UNION ALL

        -- Leads recebidos das fontes externas
        SELECT
          'lead_recebido',
          s.received_at,
          s.name,
          s.phone,
          s.lead_id,
          'Fonte: ' || s.source,
          s.source,
          NULL
        FROM lead_source_submissions s
        WHERE s.organization_id = ${org} AND s.received_at >= ${desde}

        UNION ALL

        -- Movimentação de card no pipeline
        SELECT
          'lead_movido',
          h.moved_at,
          l.title,
          l.phone,
          l.id,
          coalesce(de.name, 'Entrada') || ' -> ' || coalesce(para.name, '?'),
          'pipeline',
          NULL
        FROM lead_stage_history h
        LEFT JOIN leads l ON l.id = h.lead_id
        LEFT JOIN pipeline_stages de ON de.id = h.from_stage_id
        LEFT JOIN pipeline_stages para ON para.id = h.to_stage_id
        WHERE h.organization_id = ${org} AND h.moved_at >= ${desde}

        UNION ALL

        -- Execuções de funil iniciadas
        SELECT
          'funil_iniciado',
          e.started_at,
          l.title,
          l.phone,
          l.id,
          f.name,
          'funil',
          e.status::text
        FROM funnel_executions e
        LEFT JOIN leads l ON l.id = e.lead_id
        LEFT JOIN message_funnels f ON f.id = e.funnel_id
        WHERE e.organization_id = ${org} AND e.started_at >= ${desde}
      )
      SELECT * FROM eventos
      WHERE (${tipo}::text IS NULL OR tipo = ${tipo})
        AND (${busca}::text IS NULL OR lead_nome ILIKE ${busca} OR lead_telefone ILIKE ${busca})
      ORDER BY quando DESC
      LIMIT ${limit} OFFSET ${offset}
    `)

    // Contagem por tipo no período — alimenta os chips de filtro da tela.
    const resumo = await db.execute(sql`
      SELECT tipo, count(*)::int AS total FROM (
        SELECT CASE WHEN a.metadata->>'direction' = 'inbound' THEN 'mensagem_recebida'
                    ELSE 'mensagem_enviada' END AS tipo
        FROM lead_activities a
        WHERE a.organization_id = ${org} AND a.created_at >= ${desde}
        UNION ALL
        SELECT 'lead_recebido' FROM lead_source_submissions
        WHERE organization_id = ${org} AND received_at >= ${desde}
        UNION ALL
        SELECT 'lead_movido' FROM lead_stage_history
        WHERE organization_id = ${org} AND moved_at >= ${desde}
        UNION ALL
        SELECT 'funil_iniciado' FROM funnel_executions
        WHERE organization_id = ${org} AND started_at >= ${desde}
      ) t GROUP BY tipo
    `)

    return Response.json({
      data: eventos.rows,
      resumo: Object.fromEntries(resumo.rows.map((r: any) => [r.tipo, r.total])),
      periodo_dias: dias,
      limit,
      offset,
    })
  } catch (err: any) {
    if (err?.status) return apiError(err.status, err.message)
    console.error('[audit-log] falhou:', err)
    return apiError(500, 'Erro ao carregar o log.')
  }
}
