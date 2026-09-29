/** O card + as fotos de um imóvel, para a tela mostrar e para o envio. */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { cardDoImovel } from '@/lib/imoveisNay'

export async function GET(req: NextRequest, { params }: { params: Promise<{ codigo: string }> }) {
  try {
    await authenticateRequest(req)
    const { codigo } = await params
    const n = Number(String(codigo).replace(/\D/g, ''))
    if (!n) return apiError(400, 'Código inválido.')
    return Response.json(await cardDoImovel(n))
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui ler o imóvel.')
  }
}
