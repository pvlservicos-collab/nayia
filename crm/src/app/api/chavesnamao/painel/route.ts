/**
 * GET /api/chavesnamao/painel -- as abas Anúncios e Informações do Chat Chaves na Mão (459): o que está no XML que
 * o portal lê, o que ficou de fora e por quê, os endereços da integração e o estado dos leads. Nenhum segredo sai
 * daqui (da senha dos leads só vem se ela está guardada).
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT crm_cnm_painel() AS p')
    return Response.json(r.rows[0]?.p ?? {})
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os anúncios do Chaves na Mão.')
  }
}
