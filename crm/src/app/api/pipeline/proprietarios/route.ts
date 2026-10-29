/**
 * OS PROPRIETÁRIOS FORA DOS PIPELINES (Pedro, 29/10/2026; nayia 525): "retirar os proprietários de todas as pipelines e
 * deixar um quadrado que quando eu marco eles aparecem na guia deles de proprietário, e não misturado com as outras".
 *
 *   GET /api/pipeline/proprietarios   { fins: ['92345678', ...] }   (8 últimos dígitos)
 *
 * A lista é a que a Nay respeita (nay_proprietario_bloqueio: cadastro, admin antigo, captação, dono de visita), lida
 * pelo papel do CRM (crm_proprietarios_fone8). O PipelineBoard esconde esses cards e a caixinha mostra só eles.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT f FROM crm_proprietarios_fone8() f')
    return Response.json({ fins: (r.rows as Array<{ f: string }>).map((x) => x.f) })
  } catch (err: any) {
    console.error('[pipeline/proprietarios]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os proprietários.')
  }
}
