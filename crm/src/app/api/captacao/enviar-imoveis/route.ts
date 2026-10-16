/**
 * ENVIAR IMÓVEL PELO NÚMERO DE CAPTAÇÃO (Pedro, 16/10/2026: "coloca esse campo [Enviar imóvel: um a um / por faixa]
 * nos cards dos leads também do de captação"; migração 396).
 *
 *   POST /api/captacao/enviar-imoveis  { telefone, codigos: number[] }  -> { id }
 *   GET  /api/captacao/enviar-imoveis?id=<id>                          -> { estado, codigos, enviados, resultado }
 *
 * O CRM só faz o pedido (crm_captacao_enviar_imoveis, no banco da Nay); quem manda é a Nay do WhatsApp (serviço
 * nay-olx), pelo 8595-6408: card + fotos, um imóvel por vez. Parceria e fora do ar não saem (ficam no resultado).
 */
import { NextRequest } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { organizationMembers, profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

async function quemPediu(memberId: string | null): Promise<string> {
  if (!memberId) return 'CRM'
  const [m] = await db.select({ nome: profiles.fullName }).from(organizationMembers)
    .leftJoin(profiles, eq(profiles.id, organizationMembers.userId))
    .where(eq(organizationMembers.id, memberId)).limit(1)
  return `CRM: ${m?.nome || 'equipe'}`
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const corpo = await req.json().catch(() => ({} as any))
    const telefone = String(corpo?.telefone || '').replace(/\D/g, '')
    const codigos = (Array.isArray(corpo?.codigos) ? corpo.codigos : []).map((c: unknown) => Number(c)).filter((c: number) => c > 0)
    if (telefone.length < 10) return apiError(400, 'Este contato não tem telefone.')
    if (!codigos.length) return apiError(400, 'Escolha ao menos um imóvel.')
    const r = await naydb().query('SELECT crm_captacao_enviar_imoveis($1, $2::int[], $3) AS id',
      [telefone, codigos, await quemPediu(auth.memberId)])
    return Response.json({ ok: true, id: Number(r.rows[0]?.id) })
  } catch (err: any) {
    const msg = String(err?.message || '')
    // a recusa do banco (já tem envio saindo, mais de 10...) vai para a tela como veio
    if (err?.code === 'P0001') return apiError(400, msg)
    console.error('[captacao/enviar-imoveis]', msg)
    return apiError(err?.status || 500, msg || 'Não consegui pedir o envio.')
  }
}

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const id = Number(req.nextUrl.searchParams.get('id'))
    if (!id) return apiError(400, 'Diga o pedido.')
    const r = await naydb().query('SELECT crm_captacao_envio_estado($1) AS e', [id])
    const e = r.rows[0]?.e
    return e ? Response.json(e) : apiError(404, 'Pedido não encontrado.')
  } catch (err: any) {
    console.error('[captacao/enviar-imoveis] estado', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler o envio.')
  }
}
