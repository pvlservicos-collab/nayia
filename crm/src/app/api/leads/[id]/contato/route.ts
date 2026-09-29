/**
 * PATCH /api/leads/{id}/contato -- o que a equipe anota no card do contato
 * (Pedro, 29/09/2026): "quero poder alterar o nome do contato por lá, colocar
 * um apelido" e "embaixo das tags um quadradinho de observação".
 *
 *   { apelido: "Lily (corretora da Ponta Negra)" }  troca o nome que a lista mostra
 *   { observacao: "..." }                           guarda em custom_attributes.observacao
 *
 * A observação SOMA ao custom_attributes (jsonb ||): a rota geral do lead troca
 * o objeto inteiro e apagaria o chat_lid e a etapa do funil guardados ali.
 * O apelido fica: a entrada da Z-API só troca o título quando ele ainda é o
 * número.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { publishEvent, channels, events } from '@/lib/realtime'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const corpo = await req.json().catch(() => ({}))
    const [lead] = await db.select({ id: leads.id }).from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt))).limit(1)
    if (!lead) return apiError(404, 'Contato não encontrado.')

    if (typeof corpo.apelido === 'string') {
      const apelido = corpo.apelido.trim().slice(0, 120)
      if (!apelido) return apiError(400, 'O nome não pode ficar vazio.')
      await db.update(leads).set({ title: apelido, updatedAt: new Date() }).where(eq(leads.id, id))
    }
    if (typeof corpo.observacao === 'string') {
      const observacao = corpo.observacao.slice(0, 4000)
      await db.execute(sql`
        UPDATE leads
           SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                 || jsonb_build_object('observacao', ${observacao}::text, 'observacao_em', now()::text),
               updated_at = now()
         WHERE id = ${id}`)
    }
    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id })
    return Response.json({ ok: true })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui salvar.')
  }
}
