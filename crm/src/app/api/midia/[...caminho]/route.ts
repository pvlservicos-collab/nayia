/**
 * GET /api/midia/<caminho> -- a mídia do armazém do CRM (29/09/2026).
 *
 * Quem pode abrir:
 *   - quem está logado no CRM (a sessão é conferida aqui; o middleware deixa
 *     /api/midia passar justamente por causa do segundo caso);
 *   - quem traz o endereço ASSINADO (`?exp=&sig=`, ver `enderecoParaFora`): é
 *     assim que a Z-API e a Meta baixam o que nós mandamos, sem sessão;
 *   - as pastas públicas (logo da organização, que aparece no login).
 */
import { join } from 'node:path'
import { NextRequest } from 'next/server'
import { auth } from '@/lib/auth'
import { PASTA_DO_ARMAZEM, PASTAS_PUBLICAS, assinaturaValida, caminhoSeguro, tipoDaExtensao } from '@/lib/armazem'
import { servirArquivo } from '@/lib/servirArquivo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ caminho: string[] }> }) {
  const { caminho } = await params
  let rel: string | null = null
  try {
    rel = caminhoSeguro((caminho || []).map((p) => decodeURIComponent(p)).join('/'))
  } catch { rel = null }
  if (!rel || rel.startsWith('_')) return new Response('não encontrado', { status: 404 })

  const exp = Number(req.nextUrl.searchParams.get('exp'))
  const sig = req.nextUrl.searchParams.get('sig') || ''
  let pode = PASTAS_PUBLICAS.some((p) => rel!.startsWith(p)) || (sig !== '' && assinaturaValida(rel, exp, sig))
  if (!pode) {
    const sessao = await auth()
    pode = !!sessao?.user
  }
  if (!pode) return new Response('não autenticado', { status: 401 })

  return servirArquivo(join(PASTA_DO_ARMAZEM, rel), tipoDaExtensao(rel), req)
}
