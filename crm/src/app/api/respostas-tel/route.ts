/**
 * RESPOSTAS TEL (Pedro, 29/10/2026; nayia 527): "pega todas as dúvidas que ainda falta o Tel responder de conversas, e faz
 * um painel Respostas Tel ... só com as dúvidas da Nay, a pergunta do cliente e um campo para o Tel responder, igual
 * Tinder, passando para o lado".
 *
 *   GET  /api/respostas-tel                                    { duvidas: [...] }  (?n=1: só { n })
 *   POST /api/respostas-tel  { fonte, id, acao, texto }        acao: responder | descartar
 *
 * As dúvidas moram no banco da Nay (pergunta_fila e privado.duvida); quem decide como a resposta chega ao cliente é
 * crm_tel_responder (a da Leads a Nay Leads entrega; a da Parceria sai pela caixa da Nay, como o DEVOLVER).
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    let duvidas: any[] = []
    try {
      const r = await naydb().query('SELECT crm_tel_duvidas() AS j')
      duvidas = r.rows[0]?.j || []
    } catch (e: any) {
      if (e?.code !== '42883') throw e
      return Response.json({ duvidas: [], n: 0, semMigracao: true })   // antes da 527 no banco
    }
    if (req.nextUrl.searchParams.get('n')) return Response.json({ n: duvidas.length })
    return Response.json({ duvidas, n: duvidas.length })
  } catch (err: any) {
    console.error('[respostas-tel]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as dúvidas.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM responde dúvida.')
    const corpo = await req.json().catch(() => null)
    const fonte = corpo?.fonte === 'duvida' ? 'duvida' : corpo?.fonte === 'fila' ? 'fila' : null
    const id = Number(corpo?.id)
    const acao = corpo?.acao === 'descartar' ? 'descartar' : corpo?.acao === 'responder' ? 'responder' : null
    if (!fonte || !Number.isInteger(id) || id <= 0 || !acao) return apiError(400, 'Dúvida ou ação inválida.')
    const texto = String(corpo?.texto ?? '').slice(0, 2000)
    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const r = await naydb().query('SELECT crm_tel_responder($1, $2::bigint, $3, $4, $5) AS j',
      [fonte, id, acao, texto, perfil?.nome?.trim() || 'alguém no CRM'])
    const j = r.rows[0]?.j || { ok: false, mensagem: 'Não consegui.' }
    return Response.json(j, { status: j.ok ? 200 : 409 })
  } catch (err: any) {
    if (err?.code === '42883') return apiError(503, 'O banco da Nay ainda não tem o Respostas Tel (migração 527).')
    console.error('[respostas-tel] POST', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui mandar a resposta.')
  }
}
