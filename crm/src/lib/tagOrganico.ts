/**
 * A TAG "ORGÂNICO" (Pedro, 16/10/2026; migração 390): "quando chega lead novo a Nay deve atender normal, e perguntar se
 * ele quer imóvel, esse vem com a tag orgânico". Quem escreveu direto no número de captação (92 8595-6408) e a Nay do
 * WhatsApp atende (nay-olx/olx/whatsapp.py) está no banco da Nay com origem 'organico' (crm_olx_clientes_etapas); aqui
 * a conversa da linha da captação, casada pelos 8 últimos dígitos, ganha a tag. Roda na rodada de minuto do espelho.
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'
import { fim8 } from '@/lib/olxClientes'

const NOME = 'Orgânico'
const COR = '#16a34a'

export async function marcarOrganicos(organizacao: string): Promise<number> {
  const r = await naydb().query(`SELECT telefone FROM crm_olx_clientes_etapas() WHERE origem = 'organico'`)
  // só dígitos, 8 de cada: vão direto no ARRAY
  const fins = [...new Set((r.rows as Array<{ telefone: string }>).map((l) => fim8(l.telefone)))]
    .filter((f) => /^\d{8}$/.test(f))
  if (!fins.length) return 0

  let [tag] = (await db.execute(sql`
    SELECT id::text AS id FROM tags
     WHERE organization_id = ${organizacao}
       AND (lower(name) IN ('orgânico', 'organico') OR lower(coalesce(nome_original, '')) IN ('orgânico', 'organico'))
     ORDER BY created_at LIMIT 1`)).rows as Array<{ id: string }>
  if (!tag) {
    [tag] = (await db.execute(sql`
      INSERT INTO tags (organization_id, name, color) VALUES (${organizacao}, ${NOME}, ${COR})
      RETURNING id::text AS id`)).rows as Array<{ id: string }>
  }

  const feito = await db.execute(sql`
    INSERT INTO lead_tags (lead_id, tag_id, organization_id)
    SELECT l.id, ${tag.id}::uuid, ${organizacao}::uuid
      FROM leads l JOIN integrations i ON i.id = l.integration_id
     WHERE l.organization_id = ${organizacao} AND l.deleted_at IS NULL AND i.type = 'whatsapp_zapi_captacao'
       AND right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8)
           = ANY(${sql.raw(`ARRAY[${fins.map((f) => `'${f}'`).join(',')}]::text[]`)})
    ON CONFLICT DO NOTHING`)
  return feito.rowCount ?? 0
}
