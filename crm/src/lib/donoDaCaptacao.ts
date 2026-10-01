/**
 * O dono da captação por trás de uma conversa do CRM (linha da captação): pelo
 * telefone (8 últimos dígitos) ou pelo @lid, como na lista (/api/captacao/donos).
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { donosDaCaptacao, type DonoDaCaptacao } from '@/lib/nayLeitura'

export async function donoDaConversa(organizacao: string, leadId: string): Promise<DonoDaCaptacao | null> {
  const r = await db.execute(sql`
    SELECT right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) AS fim8,
           coalesce(l.custom_attributes->>'chat_lid', '') AS lid
      FROM leads l JOIN integrations i ON i.id = l.integration_id
     WHERE l.id = ${leadId}::uuid AND l.organization_id = ${organizacao} AND l.deleted_at IS NULL
       AND i.type = 'whatsapp_zapi_captacao'`)
  const c = r.rows[0] as { fim8: string; lid: string } | undefined
  if (!c) return null
  const donos = await donosDaCaptacao()
  return donos.find((d) => c.fim8.length === 8 && d.telefone.slice(-8) === c.fim8)
    || (c.lid ? donos.find((d) => d.lid === c.lid) : undefined)
    || null
}

/** As fotos que a pessoa mandou na conversa (as mais novas primeiro). */
export async function fotosDaConversa(leadId: string, limite = 80): Promise<Array<{ id: string; url: string; em: string }>> {
  const r = await db.execute(sql`
    SELECT id::text AS id, metadata->>'media_url' AS url, created_at
      FROM lead_activities
     WHERE lead_id = ${leadId}::uuid
       AND metadata->>'direction' = 'inbound'
       AND metadata->>'media_type' = 'image'
       AND coalesce(metadata->>'media_url', '') <> ''
     ORDER BY created_at DESC
     LIMIT ${limite}`)
  return (r.rows as Array<{ id: string; url: string; created_at: string | Date }>)
    .map((x) => ({ id: x.id, url: x.url, em: new Date(x.created_at).toISOString() }))
}

/**
 * O que a pessoa escreveu nesta conversa, juntado num texto só (246): é daqui
 * que sai o "preencher automático" do condomínio -- o corretor já disse o nome
 * em algum momento, e não queremos que alguém digite de novo.
 */
export async function textoDaConversa(leadId: string, limite = 60): Promise<string> {
  const r = await db.execute(sql`
    SELECT content FROM lead_activities
     WHERE lead_id = ${leadId}::uuid
       AND metadata->>'direction' = 'inbound'
       AND coalesce(content, '') <> ''
     ORDER BY created_at DESC
     LIMIT ${limite}`)
  return (r.rows as Array<{ content: string }>).map((x) => x.content).join(' \n ').slice(0, 4000)
}
