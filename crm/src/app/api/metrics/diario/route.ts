/**
 * GET /api/metrics/diario — o relatório do dia, para o time de atendimento.
 *
 * Responde "como foi hoje": quantos leads entraram, quantos foram abordados pela
 * primeira vez, quantos responderam e quantos andaram no funil. É a leitura que
 * alguém faz de manhã ou no fim do turno, então cada número é de UM dia, não
 * acumulado — misturar os dois é o jeito mais fácil de um relatório diário
 * mentir sem ninguém perceber.
 *
 * `?data=YYYY-MM-DD` escolhe o dia (padrão: hoje).
 *
 * Fuso fixo em America/Sao_Paulo, e não o do servidor: a Vercel roda em UTC, e
 * sem isto "hoje" começaria às 21h de ontem — o relatório da manhã traria a noite
 * anterior junto e o das 22h já teria virado o dia seguinte.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { LEAD_SOURCES, isLeadSourceKey } from '@/lib/leadSources'

const FUSO = 'America/Sao_Paulo'
const DATA_RE = /^\d{4}-\d{2}-\d{2}$/

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const org = auth.organizationId

    const pedida = req.nextUrl.searchParams.get('data')
    const dia = pedida && DATA_RE.test(pedida) ? pedida : hojeEmSP()

    // Início e fim do dia no fuso de São Paulo, convertidos para instantes UTC —
    // é assim que as colunas timestamptz precisam ser comparadas.
    //
    // `::timestamp` e NÃO `::date`: com `date`, o Postgres entende a expressão na
    // direção contrária (trata o valor como timestamptz e converte PARA o fuso),
    // devolvendo `timestamp without time zone` — medido no banco, `'2026-09-10'::date
    // AT TIME ZONE 'America/Sao_Paulo'` dá 00:00Z, que é 21h do dia ANTERIOR em São
    // Paulo. O dia viraria uma janela de 27 horas engolindo a noite passada, e o
    // relatório erraria todo santo dia sem nunca parecer quebrado.
    const inicio = sql`(${dia}::timestamp AT TIME ZONE ${FUSO})`
    const fim = sql`((${dia}::timestamp + interval '1 day') AT TIME ZONE ${FUSO})`

    const [
      novos,
      porFonte,
      abordagens,
      responderam,
      avancaram,
      porEtapa,
      mensagens,
      aguardando,
    ] = await Promise.all([
      // Leads que nasceram no dia — de qualquer origem (Agenda, site, indicação,
      // mensagem nova no WhatsApp).
      //
      // Conversa importada do WhatsApp fica de fora: ela não é lead, é contato
      // antigo do aparelho (ver /api/integrations/zapi/chats). Contá-la daria um
      // "374 leads novos" num dia em que ninguém entrou de verdade — o relatório
      // perderia a credibilidade logo no primeiro uso.
      db.execute(sql`
        SELECT count(*)::int AS total
        FROM leads
        WHERE organization_id = ${org} AND deleted_at IS NULL
          AND coalesce(custom_attributes->>'origem', '') <> 'conversa_whatsapp'
          AND created_at >= ${inicio} AND created_at < ${fim}
      `),

      db.execute(sql`
        SELECT coalesce(custom_attributes->>'lead_source', 'outros') AS fonte, count(*)::int AS total
        FROM leads
        WHERE organization_id = ${org} AND deleted_at IS NULL
          AND coalesce(custom_attributes->>'origem', '') <> 'conversa_whatsapp'
          AND created_at >= ${inicio} AND created_at < ${fim}
        GROUP BY 1 ORDER BY 2 DESC
      `),

      // Abordagem INICIAL: a primeira mensagem que saiu para aquele lead caiu
      // neste dia. Contar toda mensagem enviada responderia outra pergunta
      // ("quanto o time falou"), não "quantas pessoas novas foram abordadas".
      db.execute(sql`
        SELECT count(*)::int AS total FROM (
          SELECT lead_id, min(created_at) AS primeira
          FROM lead_activities
          WHERE organization_id = ${org}
            AND type = 'whatsapp'
            AND metadata->>'direction' = 'outbound'
          GROUP BY lead_id
        ) t
        WHERE t.primeira >= ${inicio} AND t.primeira < ${fim}
      `),

      // Quem respondeu no dia — pessoas distintas, não mensagens: dez mensagens
      // da mesma pessoa continuam sendo uma pessoa que respondeu.
      db.execute(sql`
        SELECT count(DISTINCT lead_id)::int AS total
        FROM lead_activities
        WHERE organization_id = ${org}
          AND type = 'whatsapp'
          AND metadata->>'direction' = 'inbound'
          AND created_at >= ${inicio} AND created_at < ${fim}
      `),

      db.execute(sql`
        SELECT count(DISTINCT lead_id)::int AS total
        FROM lead_stage_history
        WHERE organization_id = ${org}
          AND to_stage_id IS NOT NULL
          AND moved_at >= ${inicio} AND moved_at < ${fim}
      `),

      // Para onde foram — o "avançaram" sozinho não diz se foi pra "Em
      // atendimento" ou pra "Perdido".
      db.execute(sql`
        SELECT s.name AS etapa, count(DISTINCT h.lead_id)::int AS total
        FROM lead_stage_history h
        JOIN pipeline_stages s ON s.id = h.to_stage_id
        WHERE h.organization_id = ${org}
          AND h.moved_at >= ${inicio} AND h.moved_at < ${fim}
        GROUP BY s.name, s.rank ORDER BY s.rank
      `),

      db.execute(sql`
        SELECT
          count(*) FILTER (WHERE metadata->>'direction' = 'outbound')::int AS enviadas,
          count(*) FILTER (WHERE metadata->>'direction' = 'inbound')::int AS recebidas,
          count(*) FILTER (WHERE metadata->>'direction' = 'outbound'
                             AND metadata->>'automated' = 'true')::int AS automaticas
        FROM lead_activities
        WHERE organization_id = ${org}
          AND type = 'whatsapp'
          AND created_at >= ${inicio} AND created_at < ${fim}
      `),

      // Fila de trabalho, não do dia: leads abordados que nunca responderam.
      // É o número que diz se o time está deixando gente para trás.
      db.execute(sql`
        SELECT count(*)::int AS total FROM (
          SELECT lead_id,
                 count(*) FILTER (WHERE metadata->>'direction' = 'outbound') AS saiu,
                 count(*) FILTER (WHERE metadata->>'direction' = 'inbound') AS entrou
          FROM lead_activities
          WHERE organization_id = ${org} AND type = 'whatsapp'
          GROUP BY lead_id
        ) t
        WHERE t.saiu > 0 AND t.entrou = 0
      `),
    ])

    const linhas = (r: any) => (Array.isArray(r) ? r : r?.rows ?? [])
    const um = (r: any, campo = 'total') => Number(linhas(r)[0]?.[campo] ?? 0)

    const totalNovos = um(novos)
    const totalAbordagens = um(abordagens)
    const totalResponderam = um(responderam)
    const msg = linhas(mensagens)[0] ?? {}

    return Response.json({
      data: {
        dia,
        novos_leads: totalNovos,
        abordagens_iniciais: totalAbordagens,
        responderam: totalResponderam,
        // Taxa sobre as abordagens do dia. Não é uma coorte perfeita (quem
        // respondeu hoje pode ter sido abordado ontem), e por isso a tela chama
        // de "no dia" em vez de "taxa de resposta" — o número honesto é a razão
        // entre o que aconteceu hoje dos dois lados.
        taxa_resposta: totalAbordagens > 0 ? Math.round((totalResponderam / totalAbordagens) * 100) : 0,
        avancaram: um(avancaram),
        mensagens_enviadas: Number(msg.enviadas ?? 0),
        mensagens_recebidas: Number(msg.recebidas ?? 0),
        mensagens_automaticas: Number(msg.automaticas ?? 0),
        aguardando_resposta: um(aguardando),
        por_fonte: linhas(porFonte).map((l: any) => {
          const chave = String(l.fonte)
          return {
            chave,
            rotulo: isLeadSourceKey(chave) ? LEAD_SOURCES[chave].label : rotuloDeFonte(chave),
            total: Number(l.total),
          }
        }),
        por_etapa: linhas(porEtapa).map((l: any) => ({ etapa: l.etapa, total: Number(l.total) })),
      },
    })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Erro interno.')
  }
}

/** Data de hoje no fuso de São Paulo, como YYYY-MM-DD. */
function hojeEmSP(): string {
  // en-CA porque esse locale formata como YYYY-MM-DD, que é exatamente o que o
  // Postgres espera em `::date`.
  return new Date().toLocaleDateString('en-CA', { timeZone: FUSO })
}

/** Fontes que não estão no registro (lead que entrou pelo WhatsApp, importação). */
function rotuloDeFonte(chave: string): string {
  if (chave === 'zapi_import') return 'Conversa importada do WhatsApp'
  if (chave === 'outros') return 'Direto no WhatsApp / manual'
  return chave
}
