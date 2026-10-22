/**
 * AS BUSCAS DOS CLIENTES (475, Pedro 22/10/2026: "que tenha lá na lista de buscas ... cada pedido com uma marcação tipo
 * uma linha a ser preenchida de até onde ele já foi ... eu podendo acompanhar cada etapa na aba buscas da OLX").
 *
 *   GET  ?dias=14            -> { buscas: [...] }  crm_busca_cliente_lista (o perfil, os grupos, a OLX, os corretores, os passos)
 *   POST { id, acao }        -> { ok } | { erro }   acao = ativar | pausar | encerrar (crm_busca_cliente_acao)
 *
 * Quem anda é o serviço nay-olx (olx/buscas.py); o banco é o da Nay, pelo papel do CRM (nay_disparo), que só executa.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { eq } from 'drizzle-orm'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const dias = Math.min(Math.max(Number(req.nextUrl.searchParams.get('dias') || 14), 1), 90)
    const r = await naydb().query('SELECT crm_busca_cliente_lista($1) AS b', [dias])
    return Response.json({ buscas: r.rows[0]?.b ?? [] })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as buscas.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({}))
    const id = Number(corpo?.id)
    const acao = String(corpo?.acao || '')
    if (!id || !['ativar', 'pausar', 'encerrar'].includes(acao)) return apiError(400, 'Diga a busca e a ação.')
    let quem = 'CRM'
    if (auth.userId) {
      const [p] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
      if (p?.nome) quem = p.nome
    }
    const r = await naydb().query('SELECT crm_busca_cliente_acao($1, $2, $3) AS r', [id, acao, quem])
    const res = r.rows[0]?.r ?? { erro: 'sem resposta do banco' }
    return Response.json(res, { status: res.ok ? 200 : 400 })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui mudar a busca.')
  }
}
