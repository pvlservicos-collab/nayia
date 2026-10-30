/**
 * BUSCA OLX MANUAL (Pedro, 29/10/2026): os anúncios da OLX do banco de scrap, em quadradinhos, com filtros.
 *
 *   GET                    -> { total, ultima_coleta, bairros: [{ bairro, n }] }   (crm_olx_scrap_opcoes)
 *   GET ?filtros=<json>    -> { total, pagina, por, itens: [...] }                  (crm_olx_scrap_busca)
 *
 * Só leitura: o papel do CRM (nay_disparo) executa as funções do banco da Nay e não toca a tabela.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const bruto = req.nextUrl.searchParams.get('filtros')
    if (bruto === null) {
      const r = await naydb().query('SELECT crm_olx_scrap_opcoes() AS o')
      return Response.json(r.rows[0]?.o ?? {})
    }
    let filtros: Record<string, unknown> = {}
    try { filtros = JSON.parse(bruto.slice(0, 4000)) } catch { return apiError(400, 'Filtros inválidos.') }
    const r = await naydb().query('SELECT crm_olx_scrap_busca($1::jsonb) AS b', [JSON.stringify(filtros)])
    return Response.json(r.rows[0]?.b ?? { total: 0, itens: [] })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os anúncios.')
  }
}
