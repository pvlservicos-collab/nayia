/**
 * A mensagem que o contato MARCOU ao responder (Pedro, 09/10/2026: "quando o cara marca a msg a
 * Nay sabe, mas para a gente fica 'não encontrei essa mensagem aqui'; preciso que apareça lá a
 * mensagem à qual o cara está se referindo, para o nosso controle interno").
 *
 * A Z-API manda só o ID do que foi marcado, nunca o texto. O texto se acha em dois lugares:
 *
 *   1. nas mensagens do próprio CRM (`zapi_message_id`);
 *   2. no banco da Nay (`crm_mensagem_citada`, migração 335): o card e a lista que o publicador
 *      postou no grupo, a foto do post, o que a Nay mandou no privado. É o caso mais comum -- o
 *      corretor toca em "responder em particular" no card do grupo, e esse card nunca passou
 *      pelo CRM. Medido em 09/10: 37 das 50 citações sem conteúdo da semana estavam lá.
 *
 * Usado na chegada da mensagem (zapiInbound) e ao abrir a conversa (GET /messages), que conserta
 * as antigas e as que chegaram antes da citada.
 */
import { and, eq, inArray, sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { leadActivities } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'

export type Citada = { texto: string; quem?: string }

/** Os campos que a barra da citação lê (ActivityTimeline › QuotedMessageBar). */
export function camposDaCitada(c: Citada): Record<string, string> {
  return { quoted_text: c.texto, ...(c.quem ? { quoted_sender: c.quem } : {}) }
}

/** A mensagem citada ainda está sem conteúdo? (tem o ID, não tem texto nem mídia) */
export function citadaSemConteudo(metadata: any): boolean {
  return !!metadata?.quoted_message_id && !metadata.quoted_text && !metadata.quoted_media_type
}

/** Procura o conteúdo de cada ID. Nunca levanta erro: sem achar, o ID fica de fora do mapa. */
export async function acharCitadas(orgId: string, ids: string[]): Promise<Map<string, Citada>> {
  const achadas = new Map<string, Citada>()
  const unicos = [...new Set(ids.map(i => String(i || '').trim()).filter(Boolean))].slice(0, 300)
  if (!unicos.length) return achadas

  try {
    const doCrm = await db
      .select({
        id: sql<string>`${leadActivities.metadata}->>'zapi_message_id'`,
        content: leadActivities.content,
        metadata: leadActivities.metadata,
      })
      .from(leadActivities)
      .where(and(
        eq(leadActivities.organizationId, orgId),
        inArray(sql`${leadActivities.metadata}->>'zapi_message_id'`, unicos)))
    for (const linha of doCrm) {
      const m: any = linha.metadata || {}
      if (!linha.id) continue
      // apagada no CRM: o conteúdo não volta por aqui, nem pelo banco da Nay
      const texto = m.deleted ? '[mensagem apagada]' : (linha.content || (m.media_type ? `[${m.media_type}]` : ''))
      if (!texto) continue
      achadas.set(String(linha.id), { texto, ...(m.sender_name && !m.deleted ? { quem: String(m.sender_name) } : {}) })
    }
  } catch {
    // segue para o banco da Nay
  }

  const faltam = unicos.filter(id => !achadas.has(id))
  if (!faltam.length) return achadas
  try {
    const daNay = await naydb().query('SELECT message_id, quem, texto FROM crm_mensagem_citada($1::text[])', [faltam])
    for (const linha of daNay.rows) {
      if (!linha.texto) continue
      achadas.set(String(linha.message_id), { texto: String(linha.texto), ...(linha.quem ? { quem: String(linha.quem) } : {}) })
    }
  } catch {
    // o banco da Nay fora do ar não derruba o chat: a barra só fica sem o conteúdo
  }
  return achadas
}
