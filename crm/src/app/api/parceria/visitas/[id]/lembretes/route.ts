/**
 * OS LEMBRETES DE UMA VISITA (Pedro, 20/10/2026: "ao criar uma visita quero uma opção excluir lembrete").
 *
 *   GET    -> { lembretes: [{ id, para, telefone, enviar_em, estado, mensagem }] }
 *   DELETE ?lembrete=<id>  -> cancela aquele lembrete que ainda não saiu; sem ?lembrete, todos os da visita
 *
 * O lembrete é um follow-up agendado preso à visita (drizzle 0132). Cancelar não mexe na visita: ela continua na agenda.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

function numero(id: string) {
  const n = Number(id)
  return Number.isInteger(n) && n > 0 ? n : null
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const n = numero((await params).id)
    if (!n) return apiError(400, 'Visita inválida.')
    const r = await db.execute(sql`
      SELECT f.id::text AS id, coalesce(nullif(btrim(l.title), ''), l.phone) AS para, l.phone AS telefone,
             f.enviar_em, f.estado, f.mensagem
        FROM followups_agendados f JOIN leads l ON l.id = f.lead_id
       WHERE f.visita_id = ${n} AND f.organization_id = ${auth.organizationId}
       ORDER BY f.enviar_em`)
    return Response.json({ lembretes: r.rows })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os lembretes.')
  }
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const n = numero((await params).id)
    if (!n) return apiError(400, 'Visita inválida.')
    const um = req.nextUrl.searchParams.get('lembrete')
    if (um && !/^[0-9a-f-]{36}$/i.test(um)) return apiError(400, 'Lembrete inválido.')
    const r = um
      ? await db.execute(sql`
          UPDATE followups_agendados SET estado = 'cancelado'
           WHERE id = ${um}::uuid AND visita_id = ${n} AND organization_id = ${auth.organizationId} AND estado = 'agendado'
          RETURNING id`)
      : await db.execute(sql`
          UPDATE followups_agendados SET estado = 'cancelado'
           WHERE visita_id = ${n} AND organization_id = ${auth.organizationId} AND estado = 'agendado'
          RETURNING id`)
    return Response.json({ ok: true, cancelados: r.rows.length })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui excluir o lembrete.')
  }
}
