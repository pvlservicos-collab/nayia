/**
 * OS DONOS DO CADASTRO NA CAPTAÇÃO (Pedro, 16/10/2026: "no CRM número captação pôr a aba proprietário também").
 *
 *   GET /api/captacao/donos-do-cadastro -> { fins: string[] }   (os 8 últimos dígitos de quem é dono de imóvel)
 *
 * A aba Proprietários da Captação passa a valer como a da Parceria: além dos donos da campanha e do cliente da OLX que
 * a equipe pôs ali, entra quem está no cadastro como proprietário (crm_donos_do_cadastro, migração 397). O CRM manda
 * os telefones dos contatos da linha de captação; guardado 2 min.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const guardado = new Map<string, { em: number; fins: string[] }>()

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const ja = guardado.get(auth.organizationId)
    if (ja && Date.now() - ja.em < 2 * 60_000) return Response.json({ fins: ja.fins })
    const r = await db.execute(sql`
      SELECT DISTINCT right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) AS fim8
        FROM leads l JOIN integrations i ON i.id = l.integration_id
       WHERE l.organization_id = ${auth.organizationId} AND l.deleted_at IS NULL AND i.type = 'whatsapp_zapi_captacao'
         AND l.phone IS NOT NULL`)
    const deles = (r.rows as Array<{ fim8: string }>).map((x) => x.fim8).filter((f) => /^\d{8}$/.test(f))
    let fins: string[] = []
    if (deles.length) {
      const d = await naydb().query('SELECT fim8 FROM crm_donos_do_cadastro($1::text[])', [deles])
      fins = (d.rows as Array<{ fim8: string }>).map((x) => x.fim8)
    }
    guardado.set(auth.organizationId, { em: Date.now(), fins })
    return Response.json({ fins })
  } catch (err: any) {
    console.error('[captacao/donos-do-cadastro]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os donos do cadastro.')
  }
}
