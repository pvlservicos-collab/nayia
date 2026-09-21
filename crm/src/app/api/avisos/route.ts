/**
 * GET /api/avisos?desde=<ISO> — o que aconteceu desde a última checagem.
 *
 * Alimenta os sons do CRM (SomNovoLead). Eles eram disparados por evento do
 * Pusher, mas o app do Pusher configurado não existe mais: nenhum som tocou
 * nunca em produção. Agora o navegador pergunta a cada poucos segundos.
 *
 * Duas decisões que evitam perder aviso:
 *
 *   - `agora` volta do SERVIDOR e é ele que o navegador usa como próximo
 *     cursor. O relógio da máquina de quem usa pode estar errado (medido: uma
 *     delas estava 3 minutos atrasada), e cursor pelo relógio local pularia ou
 *     repetiria janelas.
 *   - a janela é por `updated_at` (quando a linha ENTROU no banco) com um minuto
 *     de folga, e não por `created_at`: a mensagem da Z-API é gravada com o
 *     horário original do WhatsApp, alguns segundos no passado, e cairia antes
 *     do cursor. A folga pode devolver o mesmo item duas vezes — quem chama
 *     descarta repetidos pelo id.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const org = auth.organizationId

    const [{ agora }] = (await db.execute(sql`SELECT now() AS agora`)).rows as { agora: string }[]
    const desdeTexto = req.nextUrl.searchParams.get('desde')
    const desde = desdeTexto ? new Date(desdeTexto) : null

    // Primeira chamada: só marca o ponto de partida. Tocar som pelo que já
    // aconteceu antes de a tela abrir seria um alarme falso a cada recarga.
    if (!desde || Number.isNaN(desde.getTime())) {
      return Response.json({ agora, novos_leads: [], respostas_automacao: [] })
    }
    const inicio = desde.toISOString()

    const [novos, respostas] = await Promise.all([
      // Lead de AQUISIÇÃO (Agenda, site, indicação). Conversa que chega pelo
      // WhatsApp não é lead e não toca o "plin" — é a mesma separação do funil.
      db.execute(sql`
        SELECT id, title FROM leads
        WHERE organization_id = ${org} AND deleted_at IS NULL
          AND custom_attributes->>'lead_source' IS NOT NULL
          AND created_at > (${inicio}::timestamptz - interval '1 minute')
        ORDER BY created_at DESC LIMIT 20
      `),
      // Mensagem que entrou e cuja mensagem ANTERIOR, na mesma conversa, foi da
      // automação: é a pessoa respondendo o funil.
      db.execute(sql`
        SELECT a.id, a.lead_id, l.title
        FROM lead_activities a
        JOIN leads l ON l.id = a.lead_id
        WHERE a.organization_id = ${org}
          AND a.metadata->>'direction' = 'inbound'
          AND a.updated_at > (${inicio}::timestamptz - interval '1 minute')
          AND (
            SELECT p.metadata->>'automated'
            FROM lead_activities p
            WHERE p.lead_id = a.lead_id AND p.created_at < a.created_at
            ORDER BY p.created_at DESC LIMIT 1
          ) = 'true'
        ORDER BY a.updated_at DESC LIMIT 20
      `),
    ])

    return Response.json({
      agora,
      novos_leads: novos.rows,
      respostas_automacao: respostas.rows,
    })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Erro interno.')
  }
}
