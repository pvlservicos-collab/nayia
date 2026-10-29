/**
 * A TAG "ORGÂNICO" (Pedro, 16/10/2026; migração 390): "quando chega lead novo a Nay deve atender normal, e perguntar se
 * ele quer imóvel, esse vem com a tag orgânico". Quem escreveu direto no número de captação (92 8595-6408) e a Nay do
 * WhatsApp atende (nay-olx/olx/whatsapp.py) está no banco da Nay com origem 'organico' (crm_olx_clientes_etapas); aqui
 * a conversa da linha da captação, casada pelos 8 últimos dígitos, ganha a tag. Roda na rodada de minuto do espelho.
 *
 * 29/10 (Pedro: "trocar a tag orgânico por Locação ou Venda"): a tag passou a ser a FINALIDADE do pedido que a Nay
 * entendeu (crm_olx_clientes_etapas.finalidade, 520): "Locação" ou "Venda", e troca sozinha se o pedido mudar. Sem
 * finalidade ainda, nenhuma das duas. A "Orgânico" sai das conversas da captação.
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'
import { fim8 } from '@/lib/olxClientes'

const TAGS = { locacao: { nome: 'Locação', cor: '#0891b2' }, venda: { nome: 'Venda', cor: '#d97706' } } as const

async function tagDe(organizacao: string, nome: string, cor: string): Promise<string> {
  const achou = (await db.execute(sql`
    SELECT id::text AS id FROM tags
     WHERE organization_id = ${organizacao}
       AND (lower(name) = lower(${nome}) OR lower(coalesce(nome_original, '')) = lower(${nome}))
     ORDER BY created_at LIMIT 1`)).rows as Array<{ id: string }>
  if (achou[0]) return achou[0].id
  const [nova] = (await db.execute(sql`
    INSERT INTO tags (organization_id, name, color) VALUES (${organizacao}, ${nome}, ${cor})
    RETURNING id::text AS id`)).rows as Array<{ id: string }>
  return nova.id
}

const lista = (fins: string[]) => sql.raw(`ARRAY[${fins.map((f) => `'${f}'`).join(',')}]::text[]`)

export async function marcarOrganicos(organizacao: string): Promise<number> {
  const r = await naydb().query(`SELECT telefone, finalidade FROM crm_olx_clientes_etapas() WHERE origem = 'organico'`)
  const por: Record<'locacao' | 'venda', string[]> = { locacao: [], venda: [] }
  for (const l of r.rows as Array<{ telefone: string; finalidade: string | null }>) {
    const f = fim8(l.telefone)
    // só dígitos, 8 de cada: vão direto no ARRAY
    if (/^\d{8}$/.test(f) && (l.finalidade === 'locacao' || l.finalidade === 'venda')) por[l.finalidade].push(f)
  }
  const naCaptacao = sql`l.organization_id = ${organizacao} AND l.deleted_at IS NULL AND i.type = 'whatsapp_zapi_captacao'`
  let n = 0

  // a "Orgânico" sai das conversas da captação (a tag continua existindo, para quem usa em outro lugar)
  const organico = (await db.execute(sql`
    SELECT id::text AS id FROM tags WHERE organization_id = ${organizacao}
       AND (lower(name) IN ('orgânico', 'organico') OR lower(coalesce(nome_original, '')) IN ('orgânico', 'organico'))`)).rows as Array<{ id: string }>
  if (organico.length) {
    const tirou = await db.execute(sql`
      DELETE FROM lead_tags lt USING leads l, integrations i
       WHERE lt.lead_id = l.id AND i.id = l.integration_id AND ${naCaptacao}
         AND lt.tag_id = ANY(${sql.raw(`ARRAY[${organico.map((t) => `'${t.id}'`).join(',')}]::uuid[]`)})`)
    n += tirou.rowCount ?? 0
  }

  const ids = { locacao: await tagDe(organizacao, TAGS.locacao.nome, TAGS.locacao.cor),
                venda: await tagDe(organizacao, TAGS.venda.nome, TAGS.venda.cor) }
  for (const k of ['locacao', 'venda'] as const) {
    const outra = k === 'locacao' ? 'venda' : 'locacao'
    if (!por[k].length) continue
    const poe = await db.execute(sql`
      INSERT INTO lead_tags (lead_id, tag_id, organization_id)
      SELECT l.id, ${ids[k]}::uuid, ${organizacao}::uuid
        FROM leads l JOIN integrations i ON i.id = l.integration_id
       WHERE ${naCaptacao} AND right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) = ANY(${lista(por[k])})
      ON CONFLICT DO NOTHING`)
    // o pedido mudou de finalidade: a outra sai
    const tira = await db.execute(sql`
      DELETE FROM lead_tags lt USING leads l, integrations i
       WHERE lt.lead_id = l.id AND i.id = l.integration_id AND ${naCaptacao} AND lt.tag_id = ${ids[outra]}::uuid
         AND right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) = ANY(${lista(por[k])})`)
    n += (poe.rowCount ?? 0) + (tira.rowCount ?? 0)
  }
  return n
}
