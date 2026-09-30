/**
 * FOLLOW-UP AGENDADO do card do contato (Pedro, 30/09/2026; migração 0131).
 *
 * GET    /api/leads/{id}/followups          os agendamentos desta conversa (os que faltam e os últimos)
 * POST   /api/leads/{id}/followups          { mensagem, enviar_em (ISO) } -- salva
 * DELETE /api/leads/{id}/followups?fid=...  cancela um que ainda não saiu
 *
 * Quem envia na hora é /api/cron/followups, pela linha da própria conversa.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, profiles } from '@/lib/schema'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

async function leadDaOrg(organizationId: string, id: string) {
  const [l] = await db.select({ id: leads.id }).from(leads)
    .where(and(eq(leads.id, id), eq(leads.organizationId, organizationId), isNull(leads.deletedAt))).limit(1)
  return l
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    if (!(await leadDaOrg(auth.organizationId, id))) return apiError(404, 'Conversa não encontrada.')
    const r = await db.execute(sql`
      SELECT id::text, mensagem, enviar_em, estado, criado_por_nome, enviado_em, erro
        FROM followups_agendados
       WHERE lead_id = ${id}::uuid AND organization_id = ${auth.organizationId}::uuid AND estado <> 'cancelado'
       ORDER BY (estado = 'agendado') DESC, enviar_em DESC
       LIMIT 20`)
    return Response.json({ followups: r.rows })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os agendamentos.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM agenda follow-up.')
    const { id } = await params
    if (!(await leadDaOrg(auth.organizationId, id))) return apiError(404, 'Conversa não encontrada.')
    const corpo = await req.json().catch(() => ({}))
    const mensagem = String(corpo?.mensagem || '').trim().slice(0, 4000)
    const quando = new Date(String(corpo?.enviar_em || ''))
    if (!mensagem) return apiError(400, 'Escreva a mensagem do follow-up.')
    if (Number.isNaN(quando.getTime())) return apiError(400, 'Escolha o dia e a hora.')
    if (quando.getTime() < Date.now() + 60_000) return apiError(400, 'Escolha um horário no futuro.')
    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const r = await db.execute(sql`
      INSERT INTO followups_agendados (organization_id, lead_id, mensagem, enviar_em, criado_por, criado_por_nome)
      VALUES (${auth.organizationId}::uuid, ${id}::uuid, ${mensagem}, ${quando.toISOString()}::timestamptz,
              ${auth.userId}::uuid, ${perfil?.nome?.trim() || null})
      RETURNING id::text, mensagem, enviar_em, estado`)
    return Response.json({ ok: true, followup: r.rows[0] }, { status: 201 })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui salvar o agendamento.')
  }
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const fid = String(new URL(req.url).searchParams.get('fid') || '')
    if (!/^[0-9a-f-]{36}$/i.test(fid)) return apiError(400, 'Agendamento inválido.')
    const r = await db.execute(sql`
      UPDATE followups_agendados SET estado = 'cancelado'
       WHERE id = ${fid}::uuid AND lead_id = ${id}::uuid AND organization_id = ${auth.organizationId}::uuid
         AND estado = 'agendado'
      RETURNING id`)
    if (!r.rows.length) return apiError(409, 'Esse agendamento já saiu ou já foi cancelado.')
    return Response.json({ ok: true })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui cancelar.')
  }
}
