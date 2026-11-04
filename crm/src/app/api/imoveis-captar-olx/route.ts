/**
 * IMÓVEIS CAPTAR OLX (Pedro, 03/11/2026): "só imóveis com alta probabilidade de serem de proprietários e não de corretores,
 * tire dessa lista os proprietários que já conhecemos, os corretores que já conhecemos, todos que já falamos e quem tem
 * creci, ou imobiliária, ou quem tem muitos imóveis, e separa uma lista de contatos com um botão chamar no WhatsApp e outro
 * chamar na OLX".
 *
 * GET  a lista do banco da Nay (crm_olx_captar, 585: os anúncios de particular da OLX já separados, sem quem a Nay conhece)
 *      menos quem já tem conversa em qualquer linha do CRM. Devolve também quantos saíram por cada motivo.
 * POST { olx_id, como: 'whatsapp' | 'olx' } anota quem clicou em "Chamar" (o primeiro clique fica).
 */
import { NextRequest } from 'next/server'
import { sql, eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const so8 = (t: string | null) => (t || '').replace(/\D/g, '').slice(-8)

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const r = await naydb().query('SELECT crm_olx_captar() AS j')
    const j = r.rows[0]?.j || { itens: [], fora: {} }
    const itens = (j.itens || []) as any[]

    // quem já tem conversa no CRM (qualquer linha) também sai
    const fones = Array.from(new Set(itens.flatMap((i) => (i.telefones || []).map(so8)).filter((f: string) => f.length === 8)))
    const noCrm = new Set<string>()
    if (fones.length) {
      const l = await db.execute(sql`
        SELECT DISTINCT right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 8) AS f8 FROM leads
         WHERE organization_id = ${auth.organizationId}::uuid AND deleted_at IS NULL
           AND right(regexp_replace(coalesce(phone, ''), '\D', '', 'g'), 8) IN (${sql.join(fones.map((f) => sql`${f}`), sql`, `)})`)
      for (const x of l.rows as any[]) noCrm.add(x.f8)
    }
    const fora: Record<string, number> = { ...(j.fora || {}) }
    const livres = itens.filter((i) => {
      const conhecido = (i.telefones || []).some((t: string) => noCrm.has(so8(t)))
      if (conhecido) fora['já tem conversa no CRM'] = (fora['já tem conversa no CRM'] || 0) + 1
      return !conhecido
    })
    return Response.json({ itens: livres, fora, carregadoEm: j.carregado_em, analisados: j.analisados })
  } catch (err: any) {
    console.error('[imoveis-captar-olx]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui montar a lista de imóveis para captar.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const b = await req.json().catch(() => ({}))
    const olxId = Number(b.olx_id)
    const como = b.como === 'olx' ? 'olx' : b.como === 'whatsapp' ? 'whatsapp' : null
    if (!olxId || !como) return apiError(400, 'Diga o anúncio e como chamou.')
    let quem = 'CRM'
    if (auth.userId) {
      const [p] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
      quem = p?.nome || 'CRM ' + auth.userId.slice(0, 8)
    }
    const r = await naydb().query('SELECT crm_olx_captar_chamado($1::bigint, $2, $3) AS ok', [olxId, como, quem])
    return Response.json({ ok: !!r.rows[0]?.ok, quem })
  } catch (err: any) {
    console.error('[imoveis-captar-olx POST]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui anotar.')
  }
}
