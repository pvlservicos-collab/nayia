/**
 * Os bairros já cadastrados nos imóveis (os da API do site), com a contagem -- a lista de escolha do Bairro na barra
 * Cadastrar imóvel (Pedro, 30/10/2026: "lista de seleções, ele digita e acha o bairro já cadastrado, pra não ter erros
 * de digitação").
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { listarBairros } from '@/lib/imoveisNay'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    return Response.json(await listarBairros())
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui ler os bairros.')
  }
}
