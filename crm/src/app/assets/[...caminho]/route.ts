/**
 * /assets/... -- os scripts, estilos e imagens do site, para a página de
 * imóveis servida em /admin/imoveis.html achar tudo nos mesmos caminhos
 * relativos de sempre (ver src/lib/painelDoSite.ts). Só leitura.
 */
import { NextRequest } from 'next/server'
import { arquivoDoSite, caminhoLimpo } from '@/lib/painelDoSite'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest, { params }: { params: Promise<{ caminho: string[] }> }) {
  const caminho = caminhoLimpo((await params).caminho)
  if (!caminho) return new Response('Não encontrado.', { status: 404 })
  try {
    return await arquivoDoSite(`assets/${caminho}`, req.nextUrl.search, req.headers)
  } catch (err: any) {
    console.error('[painel do site] /assets', err?.message || err)
    return new Response('O site não respondeu.', { status: 502 })
  }
}
