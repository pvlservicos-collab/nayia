/**
 * GET /api/metrics/pessoas-por-linha — quantas PESSOAS falaram com a gente em cada número, por dia/semana/mês.
 *
 * É a parte do painel de métricas do Início do admin do site (Pedro, 16/10/2026: "pessoas que falamos por dia ...
 * e por telefone") que só existe aqui: o CRM é o único lugar onde as três linhas (Parceria, Captação Z-API e a
 * oficial da Meta) estão juntas, mensagem por mensagem e com a direção. A API do site chama esta rota com o token
 * e junta com o resto (visitas, imóveis enviados, disparos), que vem do naydb.
 *
 * `?de=AAAA-MM-DD&ate=AAAA-MM-DD&grao=dia|semana|mes&excluir=94453618,...` (os 8 últimos dígitos de quem é de
 * casa: nossas linhas, equipe, Tel e testes — a lista vem do naydb, site_painel_internos).
 *
 * Por período e linha (e "todas", a mesma pessoa em duas linhas conta uma vez):
 *   conversaram  escreveu para nós OU recebeu mensagem que não é modelo (a conversa de verdade)
 *   escreveram   mandou ao menos uma mensagem (reação não conta)
 *   alcancados   recebeu qualquer coisa nossa, modelo incluído
 *   modelos      recebeu modelo da Meta (disparo da oficial)
 *   novas        a primeira mensagem que a pessoa nos mandou naquela linha caiu neste período
 * O período sem `p` é o total do intervalo (pessoa distinta, não a soma dos dias). Fuso: Manaus.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'

const FUSO = 'America/Manaus'
const DATA_RE = /^\d{4}-\d{2}-\d{2}$/
const GRAOS: Record<string, string> = { dia: 'day', semana: 'week', mes: 'month' }

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const org = auth.organizationId
    const q = req.nextUrl.searchParams

    const hoje = new Date().toLocaleDateString('en-CA', { timeZone: FUSO })
    const ate = DATA_RE.test(q.get('ate') || '') ? q.get('ate')! : hoje
    const de = DATA_RE.test(q.get('de') || '') ? q.get('de')! : ate
    const grao = GRAOS[q.get('grao') || 'dia'] || 'day'
    const excluir = (q.get('excluir') || '').split(',').map((x) => x.replace(/\D/g, '').slice(-8))
      .filter((x) => x.length === 8).join(',')

    // `::timestamp AT TIME ZONE` (e não `::date`): ver a nota em /api/metrics/diario
    const resultado = await db.execute(sql`
      WITH base AS (
        SELECT CASE i.type WHEN 'whatsapp_zapi' THEN 'parceria'
                           WHEN 'whatsapp_zapi_captacao' THEN 'captacao'
                           WHEN 'whatsapp_cloud_official' THEN 'oficial' END AS linha,
               coalesce(nullif(right(regexp_replace(coalesce(l.phone, ''), '\\D', '', 'g'), 8), ''), l.id::text) AS pessoa,
               a.created_at,
               a.metadata->>'direction' AS dir,
               a.metadata ? 'template' AS modelo,
               coalesce(a.metadata->>'is_reaction', 'false') = 'true' AS reacao
          FROM lead_activities a
          JOIN leads l ON l.id = a.lead_id
          JOIN integrations i ON i.id = l.integration_id
         WHERE a.organization_id = ${org} AND a.type = 'whatsapp'
           AND l.deleted_at IS NULL AND NOT coalesce(l.is_group, false)
           AND i.type IN ('whatsapp_zapi', 'whatsapp_zapi_captacao', 'whatsapp_cloud_official')
           AND a.created_at < ((${ate}::timestamp + interval '1 day') AT TIME ZONE ${FUSO})
           AND NOT (right(regexp_replace(coalesce(l.phone, ''), '\\D', '', 'g'), 8) = ANY (string_to_array(${excluir}, ',')))
      ), primeira AS (
        SELECT linha, pessoa, min(created_at) AS em FROM base
         WHERE dir = 'inbound' AND NOT reacao GROUP BY 1, 2
      ), primeira_geral AS (
        SELECT pessoa, min(em) AS em FROM primeira GROUP BY 1
      ), r AS (
        SELECT b.*, date_trunc(${grao}, b.created_at AT TIME ZONE ${FUSO})::date AS p,
               date_trunc(${grao}, pl.em AT TIME ZONE ${FUSO})::date = date_trunc(${grao}, b.created_at AT TIME ZONE ${FUSO})::date
                 AS nova_linha,
               date_trunc(${grao}, pg.em AT TIME ZONE ${FUSO})::date = date_trunc(${grao}, b.created_at AT TIME ZONE ${FUSO})::date
                 AS nova_geral
          FROM base b
          LEFT JOIN primeira pl ON pl.linha = b.linha AND pl.pessoa = b.pessoa
          LEFT JOIN primeira_geral pg ON pg.pessoa = b.pessoa
         WHERE b.created_at >= (date_trunc(${grao}, ${de}::timestamp) AT TIME ZONE ${FUSO})
      )
      SELECT to_char(p, 'YYYY-MM-DD') AS p, linha,
             count(DISTINCT pessoa) FILTER (WHERE (dir = 'inbound' AND NOT reacao) OR (dir = 'outbound' AND NOT modelo))::int AS conversaram,
             count(DISTINCT pessoa) FILTER (WHERE dir = 'inbound' AND NOT reacao)::int AS escreveram,
             count(DISTINCT pessoa) FILTER (WHERE dir = 'outbound')::int AS alcancados,
             count(DISTINCT pessoa) FILTER (WHERE dir = 'outbound' AND modelo)::int AS modelos,
             CASE WHEN GROUPING(linha) = 1
                  THEN count(DISTINCT pessoa) FILTER (WHERE dir = 'inbound' AND NOT reacao AND nova_geral)
                  ELSE count(DISTINCT pessoa) FILTER (WHERE dir = 'inbound' AND NOT reacao AND nova_linha) END::int AS novas
        FROM r
       GROUP BY GROUPING SETS ((p, linha), (p), (linha), ())
    `)

    const linhas: any[] = (resultado as any).rows ?? (resultado as any)
    const serie = linhas.map((l) => ({
      p: l.p ?? null,
      linha: l.linha ?? 'todas',
      conversaram: Number(l.conversaram), escreveram: Number(l.escreveram), alcancados: Number(l.alcancados),
      modelos: Number(l.modelos), novas: Number(l.novas),
    }))
    return Response.json({
      de, ate, grao: q.get('grao') || 'dia',
      linhas: [
        { chave: 'parceria', rotulo: 'Parceria', numero: '92 9445-3618' },
        { chave: 'captacao', rotulo: 'Captação', numero: '92 8595-6408' },
        { chave: 'oficial', rotulo: 'Oficial (Meta)', numero: '92 8456-0874' },
      ],
      serie: serie.filter((s) => s.p),
      totais: serie.filter((s) => !s.p),
    })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Erro interno.')
  }
}
