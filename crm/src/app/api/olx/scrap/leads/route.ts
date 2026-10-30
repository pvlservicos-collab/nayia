/**
 * BUSCA POR LEAD, na Busca OLX manual (Pedro, 29/10/2026): digita o nome (ou o número) do lead e a tela já preenche os
 * filtros com o que ele pediu.
 *
 *   GET ?q=ana  -> { leads: [{ lead, nome, telefone, filtros, ... }] }
 *
 * O nome quase sempre está no CRM (leads.title), não na tabela da Nay: acha o telefone lá e o pedido (filtros) no banco da Nay.
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import { db } from '@/lib/db'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const { organizationId } = await authenticateRequest(req)
    const q = (req.nextUrl.searchParams.get('q') || '').trim().slice(0, 60)
    if (q.length < 2) return Response.json({ leads: [] })
    const achados = (await db.execute(sql`
      SELECT right(regexp_replace(phone, '[^0-9]', '', 'g'), 8) AS fone8, title AS nome
        FROM leads
       WHERE organization_id = ${organizationId} AND deleted_at IS NULL AND is_group IS NOT TRUE
         AND coalesce(phone, '') <> '' AND title ILIKE ${'%' + q + '%'}
       ORDER BY updated_at DESC LIMIT 20`)).rows as Array<{ fone8: string; nome: string | null }>
    const fones = [...new Set(achados.map((a) => a.fone8).filter((f) => f.length === 8))]
    const r = await naydb().query('SELECT crm_olx_scrap_leads($1, $2::text[]) AS l', [q, fones])
    const nomes = new Map(achados.map((a) => [a.fone8, a.nome]))
    const leads = ((r.rows[0]?.l ?? []) as Array<{ nome: string | null; telefone: string }>).map((l) => ({
      ...l, nome: l.nome || nomes.get(String(l.telefone || '').replace(/\D/g, '').slice(-8)) || null,
    }))
    return Response.json({ leads })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui buscar o lead.')
  }
}
