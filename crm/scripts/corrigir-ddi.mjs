// Uso pontual: acerta no banco os telefones que entraram antes de a ingestão
// passar a acrescentar o DDI (ver `normalizePhone` em src/lib/leadSources.ts) e
// apaga os leads "Checagem *" usados pra testar a integração ponta a ponta.
//
// Roda uma vez e pode ser removido. Idempotente: só toca em número de 10 ou 11
// dígitos que ainda não começa com 55.
import { config } from 'dotenv'
import pg from 'pg'
import { fileURLToPath } from 'node:url'

config({ path: fileURLToPath(new URL('../.env.local', import.meta.url)), quiet: true })
const client = new pg.Client({ connectionString: process.env.DATABASE_URL })
await client.connect()

const REGRA = `length(regexp_replace(phone, '\\D', '', 'g')) in (10, 11)
               and regexp_replace(phone, '\\D', '', 'g') not like '55%'`

try {
  // 1) Leads de teste. A submissão sai primeiro: é ela que aponta pro lead.
  const t1 = await client.query(`DELETE FROM lead_source_submissions WHERE name LIKE 'Checagem %' RETURNING name`)
  const t2 = await client.query(`DELETE FROM lead_activities WHERE lead_id IN (SELECT id FROM leads WHERE title LIKE 'Checagem %')`)
  const t3 = await client.query(`DELETE FROM lead_stage_history WHERE lead_id IN (SELECT id FROM leads WHERE title LIKE 'Checagem %')`)
  const t4 = await client.query(`DELETE FROM leads WHERE title LIKE 'Checagem %' RETURNING title`)
  console.log(`teste removido: ${t4.rowCount} lead(s), ${t1.rowCount} submissão(ões), ${t2.rowCount} atividade(s), ${t3.rowCount} histórico(s)`)

  // 2) Leads do CRM sem DDI.
  const l = await client.query(
    `UPDATE leads SET phone = '55' || regexp_replace(phone, '\\D', '', 'g')
      WHERE phone IS NOT NULL AND deleted_at IS NULL AND ${REGRA}
      RETURNING title, phone`
  )
  for (const r of l.rows) console.log(`  lead   ${r.title} -> ${r.phone}`)

  // 3) Linhas do log de fontes. No site_evento o telefone também é a chave de
  //    dedupe (external_id), então os dois têm que andar juntos — senão o mesmo
  //    formulário reenviado viraria linha nova em vez de atualizar a existente.
  const s = await client.query(
    `UPDATE lead_source_submissions
        SET external_id = CASE WHEN source = 'site_evento' AND external_id = regexp_replace(phone, '\\D', '', 'g')
                               THEN '55' || regexp_replace(phone, '\\D', '', 'g') ELSE external_id END,
            phone = '55' || regexp_replace(phone, '\\D', '', 'g')
      WHERE phone IS NOT NULL AND ${REGRA}
      RETURNING name, source, phone, external_id`
  )
  for (const r of s.rows) console.log(`  fonte  ${r.source} | ${r.name} -> ${r.phone} (chave ${r.external_id})`)

  const { rows: sobrou } = await client.query(
    `SELECT count(*)::int AS n FROM leads WHERE phone IS NOT NULL AND deleted_at IS NULL AND ${REGRA}`
  )
  console.log(`\nleads ainda sem DDI: ${sobrou[0].n}`)
} finally {
  await client.end()
}
