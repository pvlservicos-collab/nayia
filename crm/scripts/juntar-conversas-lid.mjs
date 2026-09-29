/**
 * JUNTA A CONVERSA DO @LID COM A DO TELEFONE (29/09/2026).
 *
 * Pedro: "as conversas da parceria eu preciso que fique exatamente como está
 * no meu whatsapp aqui ... tem mensagem que não aparece".
 *
 * Até 29/09 o eco da NOSSA mensagem para um contato com @lid chegava com o LID
 * no lugar do telefone. Com 15 dígitos o CRM jogava fora; com 12 a 14 criava
 * uma conversa à parte, com o LID como telefone -- a mesma pessoa em duas
 * conversas: as mensagens dela numa, as nossas na outra (33 conversas assim na
 * Parceria). A entrada foi consertada (zapiInbound.ts); este script arruma o
 * que ficou:
 *   - LID com telefone conhecido (a Nay aprende em identidade_lid) e conversa
 *     desse telefone na mesma linha: tudo vai para a conversa do telefone, e a
 *     do LID é desativada (deleted_at, nada é apagado);
 *   - LID com telefone conhecido e sem conversa do telefone: a conversa passa
 *     a ter o telefone de verdade;
 *   - LID sem telefone conhecido: fica como está.
 *
 * Roda DENTRO do container (banco do CRM e da Nay):
 *   docker cp scripts/juntar-conversas-lid.mjs crm-imobeasy:/app/scripts/
 *   docker exec crm-imobeasy node scripts/juntar-conversas-lid.mjs            (só conta)
 *   docker exec crm-imobeasy node scripts/juntar-conversas-lid.mjs --gravar
 */
import pg from 'pg'

const GRAVAR = process.argv.includes('--gravar')
const crm = new pg.Client({ connectionString: process.env.DATABASE_URL })
const nay = new pg.Client({ connectionString: process.env.NAY_DISPARO_DATABASE_URL })
await crm.connect()
await nay.connect()

/** as duas formas do mesmo celular brasileiro (com e sem o nono dígito); a primeira é a que o CRM grava */
function variantes(fone) {
  let d = String(fone || '').replace(/\D/g, '')
  if (d.length === 10 || d.length === 11) d = '55' + d
  if (!d.startsWith('55')) return [d]
  const ddd = d.slice(2, 4)
  const num = d.slice(4)
  if (num.length === 9 && num.startsWith('9')) return [d, `55${ddd}${num.slice(1)}`]
  if (num.length === 8 && /^[6-9]/.test(num)) return [`55${ddd}9${num}`, d]
  return [d]
}

const { rows: lids } = await crm.query(`
  SELECT l.id, l.organization_id, l.phone, l.title, l.integration_id, l.last_activity_at,
         l.last_message_content, l.last_message_sender_type, l.last_activity_type
    FROM leads l JOIN integrations i ON i.id = l.integration_id
   WHERE i.type = 'whatsapp_zapi' AND l.deleted_at IS NULL AND NOT coalesce(l.is_group, false)
     AND l.phone ~ '^[0-9]{12,20}$' AND l.phone !~ '^55'`)

const cont = { lids: lids.length, semTelefone: 0, juntar: 0, trocarTelefone: 0, mensagensMovidas: 0 }
for (const L of lids) {
  const r = await nay.query('SELECT crm_telefone_do_lid($1) AS fone', [L.phone])
  const fone = r.rows[0]?.fone
  if (!fone) { cont.semTelefone++; continue }
  const formas = variantes(fone)
  const { rows: [Q] } = await crm.query(`
    SELECT id, last_activity_at FROM leads
     WHERE organization_id = $1 AND integration_id = $2 AND deleted_at IS NULL AND phone = ANY($3::text[]) AND id <> $4
     LIMIT 1`, [L.organization_id, L.integration_id, formas, L.id])
  const { rows: [{ n }] } = await crm.query('SELECT count(*)::int AS n FROM lead_activities WHERE lead_id = $1', [L.id])

  if (Q) {
    cont.juntar++
    cont.mensagensMovidas += n
    if (!GRAVAR) continue
    await crm.query('BEGIN')
    try {
      await crm.query('UPDATE lead_activities SET lead_id = $1 WHERE lead_id = $2', [Q.id, L.id])
      await crm.query('UPDATE pinned_messages SET lead_id = $1 WHERE lead_id = $2', [Q.id, L.id])
      await crm.query('UPDATE lead_stage_history SET lead_id = $1 WHERE lead_id = $2', [Q.id, L.id])
      await crm.query('UPDATE orders SET lead_id = $1 WHERE lead_id = $2', [Q.id, L.id])
      await crm.query('UPDATE funnel_executions SET lead_id = $1 WHERE lead_id = $2', [Q.id, L.id])
      await crm.query(`INSERT INTO lead_tags (lead_id, tag_id, organization_id)
                       SELECT $1, t.tag_id, t.organization_id FROM lead_tags t
                        WHERE t.lead_id = $2 AND NOT EXISTS (SELECT 1 FROM lead_tags x WHERE x.lead_id = $1 AND x.tag_id = t.tag_id)`, [Q.id, L.id])
      await crm.query('DELETE FROM lead_tags WHERE lead_id = $1', [L.id])
      // a prévia da lista: fica a mais nova das duas conversas
      await crm.query(`
        UPDATE leads q
           SET last_message_content = l.last_message_content,
               last_message_sender_type = l.last_message_sender_type,
               last_activity_at = l.last_activity_at,
               last_activity_type = l.last_activity_type
          FROM leads l
         WHERE q.id = $1 AND l.id = $2 AND l.last_activity_at IS NOT NULL
           AND (q.last_activity_at IS NULL OR q.last_activity_at < l.last_activity_at)`, [Q.id, L.id])
      await crm.query(`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('chat_lid', $2::text)
                        WHERE id = $1`, [Q.id, L.phone])
      await crm.query(`UPDATE leads SET deleted_at = now(),
                              custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('juntada_em', $2::text, 'juntada_quando', now()::text)
                        WHERE id = $1`, [L.id, Q.id])
      await crm.query('COMMIT')
    } catch (e) {
      await crm.query('ROLLBACK')
      console.error('não juntei', L.id, e.message)
    }
  } else {
    cont.trocarTelefone++
    if (!GRAVAR) continue
    try {
      await crm.query(`
        UPDATE leads
           SET phone = $2,
               title = CASE WHEN title = phone OR title IS NULL OR title = '' THEN $2 ELSE title END,
               custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('chat_lid', phone)
         WHERE id = $1`, [L.id, formas[0]])
    } catch (e) {
      console.error('não troquei o telefone', L.id, e.message)
    }
  }
}
console.log(JSON.stringify({ ...cont, gravado: GRAVAR }))
await crm.end()
await nay.end()
