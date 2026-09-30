/**
 * /admin/... -- as telas de imóveis do site e a API de imóveis do admin,
 * servidas por dentro do CRM (ver src/lib/painelDoSite.ts).
 *
 *   /admin/imoveis.html, /admin/imovel-editar.html   a página do site, como é
 *   /admin/api/imoveis/...                           a parte privada (dono do imóvel, salvar)
 *
 * Qualquer outro caminho do admin devolve 404 de propósito.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest } from '@/lib/api-auth'
import { PAGINAS_DO_PAINEL, apiDoAdmin, caminhoLimpo, paginaDoSite } from '@/lib/painelDoSite'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

async function atender(req: NextRequest, partes: string[]): Promise<Response> {
  try {
    await authenticateRequest(req)
  } catch {
    return new Response('Entre no CRM para ver esta página.', { status: 401 })
  }
  const caminho = caminhoLimpo(partes)
  if (!caminho) return new Response('Não encontrado.', { status: 404 })
  try {
    if (partes[0] === 'api') {
      if (partes[1] !== 'imoveis') return new Response('Não encontrado.', { status: 404 })
      const corpo = req.method === 'GET' || req.method === 'HEAD' ? null : await req.arrayBuffer()
      return await apiDoAdmin(caminho, req.nextUrl.search, req.method, corpo, req.headers.get('content-type'))
    }
    if (req.method !== 'GET' || partes.length !== 1 || !PAGINAS_DO_PAINEL.has(partes[0])) {
      return new Response('Esta parte do painel do site não abre pelo CRM.', { status: 404 })
    }
    return await paginaDoSite(partes[0], req.nextUrl.search)
  } catch (err: any) {
    console.error('[painel do site] /admin', err?.message || err)
    return new Response('O site não respondeu.', { status: 502 })
  }
}

type Ctx = { params: Promise<{ caminho: string[] }> }
export async function GET(req: NextRequest, { params }: Ctx) { return atender(req, (await params).caminho) }
export async function POST(req: NextRequest, { params }: Ctx) { return atender(req, (await params).caminho) }
export async function PUT(req: NextRequest, { params }: Ctx) { return atender(req, (await params).caminho) }
export async function DELETE(req: NextRequest, { params }: Ctx) { return atender(req, (await params).caminho) }
