/**
 * GET /api/parceria/grupos -> { grupos, meuNumero }
 * Os grupos do número da Parceria, do mais recente para o mais antigo, com quantos participantes, se o
 * número é admin e o que a casa sabe de cada um (disparo, grupo de corretores, mensagens guardadas).
 * Ver src/lib/gruposParceria.ts.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { listarGrupos } from '@/lib/gruposParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    return Response.json(await listarGrupos(auth.organizationId))
  } catch (err: any) {
    console.error('[grupos] lista', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui listar os grupos.')
  }
}
