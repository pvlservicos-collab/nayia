/**
 * POST /api/parceria/fechamento/midias/classificar
 * { activityId, documento: chave|null, papel }  -> { ok, item }
 * A Rayssa diz qual documento é a mídia (a lista suspensa da aba Fechamento).
 * documento null desfaz a escolha: volta a valer o que a Nay identificou.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { documentoDaChave, type Papel } from '@/lib/fechamentoDocumentos'
import { atividadesDoLead, fechamentoNaNay, itensDoFechamento, leadDoFechamento } from '@/lib/fechamentoServidor'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const PAPEIS: Papel[] = ['inquilino', 'comprador', 'vendedor', 'corretor']

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({} as any))
    const activityId = String(corpo?.activityId || '')
    if (!/^[0-9a-f-]{36}$/i.test(activityId)) return apiError(400, 'Mídia inválida.')
    const r = await db.execute(sql`SELECT lead_id FROM lead_activities
                                     WHERE id = ${activityId} AND organization_id = ${auth.organizationId}`)
    const leadId = (r.rows[0] as any)?.lead_id
    if (!leadId) return apiError(404, 'Mídia não encontrada.')

    const documento = corpo?.documento == null ? null : String(corpo.documento)
    if (documento !== null && !documentoDaChave(documento)) return apiError(400, 'Documento desconhecido: ' + documento)
    const papel = PAPEIS.includes(corpo?.papel) ? (corpo.papel as Papel) : null

    if (documento === null) {
      await db.execute(sql`DELETE FROM fechamento_documentos WHERE activity_id = ${activityId}`)
    } else {
      await db.execute(sql`
        INSERT INTO fechamento_documentos (activity_id, organization_id, lead_id, documento, papel, definido_por)
        VALUES (${activityId}, ${auth.organizationId}, ${leadId}, ${documento}, ${papel}, ${auth.memberId ?? null})
        ON CONFLICT (activity_id) DO UPDATE SET documento = EXCLUDED.documento, papel = EXCLUDED.papel,
          definido_por = EXCLUDED.definido_por, definido_em = now()`)
    }

    const lead = await leadDoFechamento(auth.organizationId, leadId)
    const naNay = await fechamentoNaNay(lead?.telefone ?? null)
    const itens = await itensDoFechamento(await atividadesDoLead(auth.organizationId, leadId), leadId, naNay.tipo)
    return Response.json({ ok: true, item: itens.find((i) => i.activityId === activityId) ?? null })
  } catch (err: any) {
    console.error('[fechamento classificar]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui guardar a escolha.')
  }
}
