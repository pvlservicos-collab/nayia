/**
 * A ENTREGA DE CADA MENSAGEM QUE SAIU (Pedro, 14/10/2026: "as mensagens enviadas pelo crm em alguns números não
 * estão chegando ... preciso que em cima de cada mensagem tenha 2 barrinhas que vão enchendo, a primeira é enviando,
 * e a segunda é entregue, e que o sistema saiba exatamente se ela foi mesmo entregue").
 *
 * POR QUE O CRM NÃO SABIA. As duas linhas avisam a situação de cada mensagem, e as duas eram jogadas fora:
 *   - Z-API (Parceria e Captação): o aviso "MessageStatusCallback" (SENT, RECEIVED, READ, PLAYED) nem estava
 *     configurado na instância (messageStatusCallbackUrl vazio), e o webhook do CRM o descartava;
 *   - API oficial (Meta): o `statuses[]` (sent, delivered, read, failed) chegava e voltava "ignored: no message".
 * O "id da mensagem" que a Z-API devolve no envio só prova que ELA aceitou o pedido, não que o celular da pessoa
 * recebeu.
 *
 * O QUE FICA GRAVADO em `lead_activities.metadata`, achado pelo id da mensagem na linha:
 *   whatsapp_status        sent · delivered · read · failed   (o que a tela usa)
 *   whatsapp_enviada_em, whatsapp_entregue_em, whatsapp_lida_em, whatsapp_falhou_em
 *   send_status/send_error = failed/motivo, quando a Meta diz que falhou
 * Só anda para a frente: um "enviada" atrasado não desfaz um "entregue"; "falhou" não vale depois de entregue.
 */
import { after } from 'next/server'
import { sql } from 'drizzle-orm'
import { db } from './db'
import { channels, events, publishEvent } from './realtime'

export type SituacaoDaEntrega = 'sent' | 'delivered' | 'read' | 'failed'
type CampoDoId = 'zapi_message_id' | 'whatsapp_message_id'

const CARIMBO: Record<SituacaoDaEntrega, string> = {
  sent: 'whatsapp_enviada_em', delivered: 'whatsapp_entregue_em', read: 'whatsapp_lida_em', failed: 'whatsapp_falhou_em',
}

/** O que a Z-API diz -> a nossa situação. READ_BY_ME é "nós lemos a mensagem dela": não é entrega de nada nosso. */
export function situacaoDaZapi(status: unknown): SituacaoDaEntrega | null {
  const s = String(status || '').toUpperCase()
  if (s === 'SENT') return 'sent'
  if (s === 'RECEIVED' || s === 'DELIVERED') return 'delivered'
  if (s === 'READ' || s === 'PLAYED') return 'read'
  if (s === 'FAILED' || s === 'ERROR') return 'failed'
  return null
}

/** O que a Meta diz -> a nossa situação. */
export function situacaoDaMeta(status: unknown): SituacaoDaEntrega | null {
  const s = String(status || '').toLowerCase()
  return s === 'sent' || s === 'delivered' || s === 'read' || s === 'failed' ? s : null
}

/** Grava a situação nas mensagens com esses ids. Devolve quantas mudaram. */
export async function marcarEntrega(
  organizationId: string, campo: CampoDoId, ids: string[], situacao: SituacaoDaEntrega, quando: Date, erro?: string | null,
): Promise<number> {
  const lista = ids.map(String).filter(Boolean).slice(0, 200)
  if (!lista.length) return 0
  const em = (Number.isFinite(quando.getTime()) ? quando : new Date()).toISOString()
  const r = await db.execute(sql`
    UPDATE lead_activities a
       SET metadata = a.metadata
             || jsonb_build_object('whatsapp_status', ${situacao}::text, ${CARIMBO[situacao]}::text, ${em}::text)
             -- lida sem o "entregue" antes (o aviso pode chegar fora de ordem): lida também é entregue
             || CASE WHEN ${situacao}::text = 'read' AND NOT (a.metadata ? 'whatsapp_entregue_em')
                     THEN jsonb_build_object('whatsapp_entregue_em', ${em}::text) ELSE '{}'::jsonb END
             || CASE WHEN ${situacao}::text = 'failed'
                     THEN jsonb_build_object('send_status', 'failed', 'send_error', ${erro || 'O WhatsApp não entregou a mensagem.'}::text)
                     ELSE '{}'::jsonb END
     WHERE a.organization_id = ${organizationId}
       AND (a.metadata ->> ${campo}) = ANY(${sql.raw(`ARRAY[${lista.map((x) => `'${x.replace(/'/g, "''")}'`).join(',')}]::text[]`)})
       AND (CASE ${situacao}::text WHEN 'sent' THEN 1 WHEN 'delivered' THEN 2 WHEN 'read' THEN 3 ELSE 0 END
              > CASE coalesce(a.metadata ->> 'whatsapp_status', '') WHEN 'sent' THEN 1 WHEN 'delivered' THEN 2 WHEN 'read' THEN 3 ELSE 0 END
            OR (${situacao}::text = 'failed' AND coalesce(a.metadata ->> 'whatsapp_status', '') NOT IN ('delivered', 'read', 'failed')))
    RETURNING a.id, a.lead_id`)
  const linhas = r.rows as Array<{ id: string; lead_id: string }>
  for (const l of linhas) {
    await publishEvent(channels.leadActivities(l.lead_id), events.ACTIVITY_UPDATED, { id: l.id }).catch(() => undefined)
  }
  return linhas.length
}

/**
 * Grava e, se a mensagem ainda não estiver no CRM, tenta de novo daqui a pouco: o aviso da Z-API pode chegar ANTES
 * de o CRM terminar de gravar o que acabou de mandar (o envio e o aviso correm juntos).
 */
export async function marcarEntregaComRepeticao(
  organizationId: string, campo: CampoDoId, ids: string[], situacao: SituacaoDaEntrega, quando: Date, erro?: string | null,
): Promise<number> {
  const n = await marcarEntrega(organizationId, campo, ids, situacao, quando, erro)
  if (n === 0 && situacao !== 'sent') {
    after(async () => {
      await new Promise((ok) => setTimeout(ok, 5000))
      await marcarEntrega(organizationId, campo, ids, situacao, quando, erro).catch((e) =>
        console.error('[entrega] segunda tentativa', situacao, e?.message || e))
    })
  }
  return n
}
