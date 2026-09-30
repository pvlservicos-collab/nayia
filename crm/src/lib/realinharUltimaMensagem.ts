/**
 * REALINHAR A "ÚLTIMA MENSAGEM" (Tel, 30/09/2026: "revise a barra de respostas
 * lá do CRM que conta respostas não respondidas, porque quando eu respondo
 * alguém pelo telefone ele não diminui lá, precisa diminuir").
 *
 * A barra conta quem espera resposta lendo `leads.last_message_sender_type`.
 * Esse campo é um RESUMO: quem grava é a entrada da mensagem, e basta uma
 * mensagem não cair no lead certo para o resumo ficar mentindo -- e ninguém
 * descobre, porque nada dá erro.
 *
 * Medido em 30/09: a resposta dada pelo celular chega ao banco da Nay com o
 * destinatário em `@lid`, não em telefone (2.490 em 3 dias, 124 pessoas). O CRM
 * traduz isso por três caminhos e acerta 74 dos 80 LIDs -- o que escapa vira
 * exatamente esse resumo errado.
 *
 * Em vez de caçar cada caminho, esta conferência olha o que de fato está na
 * conversa (`lead_activities`) e conserta o resumo quando ele discorda. Vale
 * para qualquer causa, inclusive as que ainda não apareceram.
 *
 * NÃO MEXE em `last_activity_at`: a ordem da lista é do jeito que está, e
 * remexer nela por causa de um resumo moveria conversa debaixo da mão de quem
 * está lendo. Só troca quem falou por último e a prévia.
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'

export async function realinharUltimaMensagem(orgId: string, dias = 3): Promise<number> {
  const r: any = await db.execute(sql`
    WITH ultima AS (
      SELECT DISTINCT ON (a.lead_id)
             a.lead_id,
             a.content,
             CASE WHEN a.metadata->>'direction' = 'outbound' THEN 'human' ELSE 'lead' END AS quem
        FROM lead_activities a
        JOIN leads l ON l.id = a.lead_id
       WHERE l.organization_id = ${orgId}
         AND l.deleted_at IS NULL
         AND a.type = 'whatsapp'
         AND a.created_at > now() - (${dias}::int * interval '1 day')
       ORDER BY a.lead_id, a.created_at DESC, a.id DESC
    )
    UPDATE leads l
       SET last_message_sender_type = u.quem,
           last_message_content = coalesce(nullif(u.content, ''), l.last_message_content)
      FROM ultima u
     WHERE l.id = u.lead_id
       AND l.last_message_sender_type IS DISTINCT FROM u.quem`)
  return r?.rowCount ?? r?.count ?? 0
}
