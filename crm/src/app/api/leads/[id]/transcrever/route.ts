/**
 * POST /api/leads/{id}/transcrever -- transcreve os áudios desta conversa que
 * ainda não têm texto (29/09/2026; as três linhas desde a tarde).
 * Com `{ atividade }` no corpo, refaz aquele áudio (o "Tentar de novo" da tela).
 *
 * O áudio novo já é transcrito quando entra; esta rota cobre o que chegou
 * antes, e é chamada pela tela quando a conversa abre. Responde na hora e
 * trabalha depois, um áudio de cada vez (o servidor é dividido com a Nay); a
 * tela recebe cada transcrição pelo Pusher ('activity.updated').
 */
import { after, NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations, leads } from '@/lib/schema'
import { sql } from 'drizzle-orm'
import { audiosSemTranscricao, linhaTemTranscricao, transcreverAtividade, transcricaoLigada } from '@/lib/transcricao'

export const runtime = 'nodejs'

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [lead] = await db
      .select({ id: leads.id, tipo: integrations.type })
      .from(leads)
      .leftJoin(integrations, eq(integrations.id, leads.integrationId))
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    if (!transcricaoLigada() || !linhaTemTranscricao(lead.tipo)) return Response.json({ ligado: false, pendentes: 0 })

    const corpo = await req.json().catch(() => ({} as any))
    if (typeof corpo?.atividade === 'string') {
      const deste = await db.execute(sql`SELECT 1 FROM lead_activities WHERE id = ${corpo.atividade}::uuid AND lead_id = ${lead.id}`)
      if (!deste.rows.length) return apiError(404, 'Áudio não encontrado nesta conversa.')
      const atividade = corpo.atividade as string
      after(() => transcreverAtividade(atividade, { refazer: true }).then(() => undefined)
        .catch((e) => console.error('[transcricao]', atividade, e?.message || e)))
      return Response.json({ ligado: true, pendentes: 1 })
    }

    const pendentes = await audiosSemTranscricao(lead.id, 20)
    if (pendentes.length) {
      after(async () => {
        for (const atividade of pendentes) {
          await transcreverAtividade(atividade).catch((e) => console.error('[transcricao]', atividade, e?.message || e))
        }
      })
    }
    return Response.json({ ligado: true, pendentes: pendentes.length })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Erro ao transcrever.')
  }
}
