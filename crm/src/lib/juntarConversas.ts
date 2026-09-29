/**
 * Junta duas conversas da MESMA pessoa na mesma linha (29/09/2026).
 *
 * Caso de uso: a conversa que nasceu só com o @lid (nossas mensagens para quem
 * o WhatsApp esconde o número) e a do telefone, que aparece quando a pessoa
 * responde -- a resposta traz o telefone E o chatLid, e é o próprio WhatsApp
 * dizendo que as duas são a mesma pessoa. Tudo vai para `para`; a conversa
 * `de` é desativada (deleted_at, nada é apagado), com a marca de para onde foi.
 * Mesma receita de scripts/juntar-conversas-lid.mjs.
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'

export async function juntarConversaNaOutra(de: string, para: string): Promise<void> {
  if (!de || !para || de === para) return
  await db.transaction(async (tx) => {
    await tx.execute(sql`UPDATE lead_activities SET lead_id = ${para} WHERE lead_id = ${de}`)
    await tx.execute(sql`UPDATE pinned_messages SET lead_id = ${para} WHERE lead_id = ${de}`)
    await tx.execute(sql`UPDATE lead_stage_history SET lead_id = ${para} WHERE lead_id = ${de}`)
    await tx.execute(sql`UPDATE orders SET lead_id = ${para} WHERE lead_id = ${de}`)
    await tx.execute(sql`UPDATE funnel_executions SET lead_id = ${para} WHERE lead_id = ${de}`)
    await tx.execute(sql`
      INSERT INTO lead_tags (lead_id, tag_id, organization_id)
      SELECT ${para}, t.tag_id, t.organization_id FROM lead_tags t
       WHERE t.lead_id = ${de} AND NOT EXISTS (SELECT 1 FROM lead_tags x WHERE x.lead_id = ${para} AND x.tag_id = t.tag_id)`)
    await tx.execute(sql`DELETE FROM lead_tags WHERE lead_id = ${de}`)
    // a prévia da lista: fica a mais nova das duas conversas
    await tx.execute(sql`
      UPDATE leads q
         SET last_message_content = l.last_message_content,
             last_message_sender_type = l.last_message_sender_type,
             last_activity_at = l.last_activity_at,
             last_activity_type = l.last_activity_type
        FROM leads l
       WHERE q.id = ${para} AND l.id = ${de} AND l.last_activity_at IS NOT NULL
         AND (q.last_activity_at IS NULL OR q.last_activity_at < l.last_activity_at)`)
    await tx.execute(sql`
      UPDATE leads SET deleted_at = now(),
             custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
               || jsonb_build_object('juntada_em', ${para}::text, 'juntada_quando', now()::text)
       WHERE id = ${de}`)
  })
}
