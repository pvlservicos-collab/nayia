/**
 * BUSCAR IMÓVEL OLX (Pedro, 19/10/2026: "constrói uma função para buscar esse imóvel fora lá no menu do CRM ... vai ter
 * uns campos a preencher com os dados do lead, põe lá e ele segue o mesmo caminho").
 *
 *   GET  ?dias=7  -> { buscas: [...] }  as ordens dos últimos dias (crm_olx_buscas_parceiro, 422)
 *   POST { nome, telefone, finalidade, tipo, teto, bairros[], qualquer_bairro, quartos, aceita_menos_quartos, mobilia,
 *          precisa_elevador, financiamento, observacao } -> { ok, id } ou { erro }
 *
 * A ordem é a mesma que a Nay do WhatsApp abre quando o catálogo não tem (privado.olx_busca_parceiro): o serviço nay-olx
 * busca na OLX pelo Chrome do Agente OLX, pergunta ao anunciante que já conhecemos ou cria o pré-cadastro e avisa o
 * grupo; quando o imóvel fica Disponível, a Nay manda ao cliente pelo 8595.
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
    const dias = Math.min(Math.max(Number(req.nextUrl.searchParams.get('dias') || 7), 1), 90)
    const r = await naydb().query('SELECT crm_olx_buscas_parceiro($1) AS b', [dias])
    return Response.json({ buscas: r.rows[0]?.b ?? [] })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as buscas.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({}))
    let quem = 'CRM'
    if (auth.userId) {
      const [p] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
      if (p?.nome) quem = p.nome
    }
    const r = await naydb().query('SELECT crm_olx_busca_parceiro_abrir($1::jsonb, $2) AS r', [JSON.stringify(corpo || {}), quem])
    const res = r.rows[0]?.r ?? { erro: 'sem resposta do banco' }
    return Response.json(res, { status: res.erro ? 400 : 200 })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui abrir a busca.')
  }
}
