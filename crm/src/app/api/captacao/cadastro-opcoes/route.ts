/**
 * GET /api/captacao/cadastro-opcoes -- o que o popup de cadastro do card da
 * captação oferece (Pedro, 01/10/2026): "quero uma lista de condomínios
 * detalhada com os endereços dos condomínios para selecionar... na aba de
 * cadastrar imóvel do corretor posso puxar da lista dos que estão em pré
 * cadastro na OLX".
 *
 * Tudo numa chamada (migração 246): condomínios com endereço, características
 * já em uso no catálogo, tipos, bairros e o pré-cadastro (Rascunho). Guardado
 * por 5 minutos no servidor -- o popup não espera o banco de novo a cada vez.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { opcoesDoCadastro } from '@/lib/nayLeitura'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    return Response.json(await opcoesDoCadastro())
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as opções do cadastro.')
  }
}
