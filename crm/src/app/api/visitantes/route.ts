/**
 * VISITANTES (Pedro, 20/10/2026: "cria uma aba lá no CRM VISITANTES: um registro de todos os clientes e corretores que já
 * visitaram com a gente, por dia, mês, trimestre e total; filtrar pelos corretores ou pelos leads e criar uma lista").
 *
 *   GET ?de=AAAA-MM-DD&ate=AAAA-MM-DD  -> { visitas: [...] }  (sem datas = todas)
 *
 * As visitas que aconteceram (crm_visitantes, migração 427): as da Parceria encerradas/realizadas e as do cliente da OLX
 * confirmadas que já passaram, com o corretor, o cliente e o imóvel. A tela agrupa por pessoa.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const DIA = /^\d{4}-\d{2}-\d{2}$/

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const de = req.nextUrl.searchParams.get('de') || ''
    const ate = req.nextUrl.searchParams.get('ate') || ''
    const r = await naydb().query('SELECT crm_visitantes($1::date, $2::date) AS v', [DIA.test(de) ? de : null, DIA.test(ate) ? ate : null])
    return Response.json({ visitas: r.rows[0]?.v ?? [] })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as visitas.')
  }
}
