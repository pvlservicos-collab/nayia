/**
 * A lista de imóveis para a aba Imóveis do CRM.
 *
 * Proxy da API do site: mesma fonte que a Nay lê, mesmos filtros da tela de
 * Imóveis de lá. Ver `src/lib/imoveisNay.ts` para o porquê de não copiar o
 * banco para cá.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { listarImoveis } from '@/lib/imoveisNay'

/** Só os parâmetros que a tela usa. Lista fechada para não virar proxy aberto. */
const PERMITIDOS = new Set([
  'q', 'status', 'grupo', 'tipo', 'bairro', 'condo_ids', 'finalidade', 'vmin', 'vmax',
  'quartos', 'vagas', 'parceiro', 'sem_dono', 'com_dono', 'anunciado', 'com_foto',
  'confirmar', 'financia', 'data_campo', 'data_per', 'data_meses', 'ordem', 'page', 'per',
])

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const entrada = req.nextUrl.searchParams
    const saida = new URLSearchParams()
    for (const [k, v] of entrada.entries()) {
      if (PERMITIDOS.has(k) && String(v).trim() !== '') saida.set(k, String(v).slice(0, 120))
    }
    if (!saida.has('per')) saida.set('per', '30')
    const d = await listarImoveis(saida)
    return Response.json(d)
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui ler os imóveis.')
  }
}
