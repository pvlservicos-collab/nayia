/**
 * POST /api/cron/followups -- envia os follow-ups agendados que venceram
 * (Pedro, 30/09/2026; migração 0131). Chamada a cada minuto pelo cron do servidor
 * (/etc/cron.d/crm-followups), com `x-cron-segredo` = CRON_SEGREDO. Sem ele, 401.
 *
 * Cada agendamento sai UMA vez: a linha passa de 'agendado' para 'enviando' na
 * mesma instrução que a reserva (FOR UPDATE SKIP LOCKED), e só depois vai ao
 * WhatsApp, pela linha da própria conversa. Falhou: fica 'falhou' com o erro, e
 * não tenta de novo sozinho (mandar duas vezes é pior do que não mandar).
 */
import { NextRequest } from 'next/server'
import { timingSafeEqual } from 'node:crypto'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations, leadActivities, leads } from '@/lib/schema'
import { getChannelAdapter } from '@/lib/channels/registry'
import { publishEvent, channels, events } from '@/lib/realtime'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'
export const maxDuration = 120

function segredoConfere(veio: string | null): boolean {
  const certo = process.env.CRON_SEGREDO || ''
  if (!certo || !veio) return false
  const a = Buffer.from(certo)
  const b = Buffer.from(veio)
  return a.length === b.length && timingSafeEqual(a, b)
}

export async function POST(req: NextRequest) {
  if (!segredoConfere(req.headers.get('x-cron-segredo'))) return new Response('não autorizado', { status: 401 })
  const reservados = await db.execute(sql`
    UPDATE followups_agendados f SET estado = 'enviando'
     WHERE f.id IN (SELECT id FROM followups_agendados
                     WHERE estado = 'agendado' AND enviar_em <= now()
                     ORDER BY enviar_em LIMIT 20 FOR UPDATE SKIP LOCKED)
    RETURNING f.id::text AS id, f.organization_id::text AS org, f.lead_id::text AS lead, f.mensagem, f.criado_por_nome`)
  let enviados = 0, falhas = 0
  for (const f of reservados.rows as Array<{ id: string; org: string; lead: string; mensagem: string; criado_por_nome: string | null }>) {
    try {
      const [lead] = await db
        .select({ id: leads.id, phone: leads.phone, isGroup: leads.isGroup, externalId: leads.externalId, integrationId: leads.integrationId })
        .from(leads).where(and(eq(leads.id, f.lead), isNull(leads.deletedAt))).limit(1)
      if (!lead) throw new Error('a conversa não existe mais')
      let tipo = 'whatsapp_zapi'
      if (lead.integrationId) {
        const [integ] = await db.select({ type: integrations.type }).from(integrations)
          .where(and(eq(integrations.id, lead.integrationId), isNull(integrations.deletedAt))).limit(1)
        if (integ?.type) tipo = integ.type
      }
      const adapter = getChannelAdapter(tipo)
      const destino = tipo === 'instagram_direct' ? (lead.externalId || '') : (lead.phone || '')
      if (!destino) throw new Error('a conversa não tem telefone')
      const r = await adapter.sendText(f.org, lead.integrationId, destino, f.mensagem, lead.isGroup ?? false)
      const metadata: Record<string, any> = {
        source: 'followup_agendado', direction: 'outbound', send_status: 'sent', channel: tipo,
        followup_id: f.id, sender_name: f.criado_por_nome || undefined,
      }
      if (r.externalId) metadata[adapter.metadataIdKey] = r.externalId
      const [atividade] = await db.insert(leadActivities)
        .values({ organizationId: f.org, leadId: f.lead, type: 'whatsapp', content: f.mensagem, metadata })
        .returning({ id: leadActivities.id })
      await db.update(leads).set({
        lastMessageContent: f.mensagem, lastMessageSenderType: 'followup_agendado',
        lastActivityAt: new Date(), lastActivityType: 'whatsapp',
      } as any).where(eq(leads.id, f.lead))
      await db.execute(sql`UPDATE followups_agendados SET estado = 'enviado', enviado_em = now(), erro = NULL WHERE id = ${f.id}::uuid`)
      await publishEvent(channels.leadActivities(f.lead), events.ACTIVITY_CREATED, { id: atividade.id }).catch(() => undefined)
      await publishEvent(channels.orgLeads(f.org), events.LEAD_UPDATED, { id: f.lead }).catch(() => undefined)
      enviados++
    } catch (err: any) {
      falhas++
      const erro = String(err?.message || err).slice(0, 500)
      console.error('[followup agendado]', f.id, erro)
      await db.execute(sql`UPDATE followups_agendados SET estado = 'falhou', erro = ${erro} WHERE id = ${f.id}::uuid`).catch(() => undefined)
    }
  }
  if (enviados || falhas) console.log('[followups]', JSON.stringify({ enviados, falhas }))
  return Response.json({ enviados, falhas })
}
