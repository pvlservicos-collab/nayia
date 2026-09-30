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
import { mkdir, rename, stat, unlink } from 'node:fs/promises'
import { dirname, join } from 'node:path'
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

  // MINIATURA (?w=160, aba Fechamento, 30/09): a lista de documentos não baixa
  // cada foto em tamanho cheio. Feita uma vez e guardada em _miniaturas/ (pasta
  // que esta rota nunca serve direto: começa com "_").
  const w = Number(req.nextUrl.searchParams.get('w'))
  const tipo = tipoDaExtensao(rel)
  if (Number.isInteger(w) && w >= 32 && w <= 640 && tipo.startsWith('image/')) {
    const mini = join(PASTA_DO_ARMAZEM, '_miniaturas', `w${w}`, rel + '.jpg')
    try {
      await stat(mini)
    } catch {
      // grava num temporário e troca de nome: outra requisição nunca pega a
      // miniatura pela metade (e ela ficaria presa no cache do navegador)
      const tmp = `${mini}.${process.pid}.${Date.now()}.tmp`
      try {
        const sharp = (await import('sharp')).default
        await mkdir(dirname(mini), { recursive: true })
        await sharp(join(PASTA_DO_ARMAZEM, rel)).rotate().resize({ width: w, withoutEnlargement: true })
          .jpeg({ quality: 70 }).toFile(tmp)
        await rename(tmp, mini)
      } catch (err) {
        await unlink(tmp).catch(() => {})
        console.error('[midia] miniatura', rel, (err as Error)?.message)
        return servirArquivo(join(PASTA_DO_ARMAZEM, rel), tipo, req)
      }
    }
    return servirArquivo(mini, 'image/jpeg', req)
  }

  return servirArquivo(join(PASTA_DO_ARMAZEM, rel), tipo, req)
}
