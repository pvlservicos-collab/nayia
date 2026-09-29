/**
 * JUNTA A CONVERSA DO @LID COM A DO TELEFONE, AGORA PELO ID DA MENSAGEM
 * (29/09/2026). Pedro: "vê um bug no WhatsApp captação, tá puxando id e não
 * número".
 *
 * O eco do disparo da captação para um dono endereçado por LID chegava só com
 * o LID, e ninguém conhecia esse LID (o dono nunca respondeu): o CRM abria uma
 * conversa com o LID no lugar do telefone e do nome -- uma a cada disparo com
 * LID novo (12 conversas de 4 pessoas). A entrada foi consertada (zapiInbound:
 * pergunta à Nay quem recebeu aquela mensagem, migração 171). Este script
 * arruma o que ficou, nas duas linhas da Z-API (Parceria e captação), como o
 * juntar-conversas-lid.mjs:
 *   - acha o telefone pelo LID (crm_telefone_do_lid) ou, se não, pelo id das
 *     mensagens da conversa (crm_contato_da_mensagem);
 *   - se já há conversa desse telefone na mesma linha, tudo vai para ela e a
 *     do LID é desativada (deleted_at, nada é apagado);
 *   - se não há, a conversa passa a ter o telefone (e o nome do dono, se o
 *     título era o LID).
 *
 * Roda DENTRO do container (banco do CRM e da Nay):
 *   docker cp scripts/juntar-lid-pela-mensagem.mjs crm-imobeasy:/app/scripts/
 *   docker exec crm-imobeasy node scripts/juntar-lid-pela-mensagem.mjs            (só conta)
 *   docker exec crm-imobeasy node scripts/juntar-lid-pela-mensagem.mjs --gravar
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

async function destinoDoLid(lead) {
  const r = await nay.query('SELECT crm_telefone_do_lid($1) AS fone', [lead.phone])
  if (r.rows[0]?.fone) return { fone: r.rows[0].fone, nome: null }
  const { rows: ids } = await crm.query(
    `SELECT DISTINCT metadata->>'zapi_message_id' AS id FROM lead_activities
      WHERE lead_id = $1 AND metadata->>'zapi_message_id' IS NOT NULL`, [lead.id])
  for (const { id } of ids) {
    const m = await nay.query('SELECT * FROM crm_contato_da_mensagem($1)', [id])
    if (m.rows[0]?.telefone) return { fone: m.rows[0].telefone, nome: m.rows[0].nome || null }
  }
  return null
}

const { rows: lids } = await crm.query(`
  SELECT l.id, l.organization_id, l.phone, l.title, l.integration_id, i.type AS linha
    FROM leads l JOIN integrations i ON i.id = l.integration_id
   WHERE i.type IN ('whatsapp_zapi', 'whatsapp_zapi_captacao') AND l.deleted_at IS NULL AND NOT coalesce(l.is_group, false)
     AND l.phone ~ '^[0-9]{12,20}$' AND l.phone !~ '^55'
   ORDER BY l.created_at`)

const cont = { lids: lids.length, semTelefone: 0, juntar: 0, trocarTelefone: 0, mensagensMovidas: 0, porLinha: {} }
for (const L of lids) {
  cont.porLinha[L.linha] = (cont.porLinha[L.linha] ?? 0) + 1
  const destino = await destinoDoLid(L)
  if (!destino) { cont.semTelefone++; continue }
  const formas = variantes(destino.fone)
  const { rows: [Q] } = await crm.query(`
    SELECT id FROM leads
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
      // o título era o LID (ou vazio): vira o nome do dono, ou o telefone
      await crm.query(`
        UPDATE leads
           SET phone = $2,
               title = CASE WHEN title = phone OR title IS NULL OR title = '' OR title ~ '^[0-9@lid ]+$' THEN coalesce($3, $2) ELSE title END,
               custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('chat_lid', phone)
         WHERE id = $1`, [L.id, formas[0], destino.nome])
    } catch (e) {
      console.error('não troquei o telefone', L.id, e.message)
    }
  }
}
console.log(JSON.stringify({ ...cont, gravado: GRAVAR }))
await crm.end()
await nay.end()
