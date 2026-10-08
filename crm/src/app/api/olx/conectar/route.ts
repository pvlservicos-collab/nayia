/**
 * LIGAR UMA CONTA DA OLX AO CRM (Pedro, 08/10/2026).
 *
 *   GET  /api/olx/conectar?conta=proprietarios|corretores
 *        Só para quem está logado no CRM. Leva o navegador à página da OLX em que o dono da conta
 *        autoriza o nosso aplicativo (escopo `chat`). A OLX devolve o navegador em /api/olx/oauth.
 *        ATENÇÃO: vale a conta em que o navegador estiver LOGADO NA OLX nessa hora.
 *
 *   POST /api/olx/conectar  { conta }
 *        Liga de novo o webhook do chat de uma conta já autorizada (se a ativação falhou, ou se o
 *        endereço mudou).
 *
 * O `state` leva a conta e um número sorteado, que também fica num cookie deste navegador: a volta
 * só vale se os dois baterem (ninguém consegue empurrar um código de outra conta para cá).
 */
import { NextRequest, NextResponse } from 'next/server'
import { randomBytes } from 'node:crypto'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { ehContaOlx, enderecoNoCrm, ligarWebhookOlx, segredoDaContaOlx, urlDeAutorizacaoOlx } from '@/lib/olxChat'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const COOKIE_DO_ESTADO_OLX = 'olx_oauth_estado'   // o mesmo nome em /api/olx/oauth

function voltar(conta: string, aviso: string) {
  const u = enderecoNoCrm('/chat/olx')
  u.searchParams.set('conta', conta)
  u.searchParams.set('aviso', aviso)
  return NextResponse.redirect(u)
}

export async function GET(req: NextRequest) {
  const conta = req.nextUrl.searchParams.get('conta') || ''
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM conecta uma conta.')
    if (!ehContaOlx(conta)) return apiError(400, 'Diga a conta: proprietarios ou corretores.')
    await segredoDaContaOlx(conta)   // a linha da conta nasce aqui, com o segredo do webhook
    const sorteado = randomBytes(16).toString('hex')
    const resposta = NextResponse.redirect(urlDeAutorizacaoOlx(`${conta}.${sorteado}`))
    resposta.cookies.set(COOKIE_DO_ESTADO_OLX, `${conta}.${sorteado}`, {
      httpOnly: true, secure: true, sameSite: 'lax', path: '/api/olx', maxAge: 15 * 60,
    })
    return resposta
  } catch (err: any) {
    console.error('[olx/conectar]', err?.message || err)
    if (ehContaOlx(conta)) return voltar(conta, err?.message || 'Não consegui começar a conexão com a OLX.')
    return apiError(err?.status || 500, err?.message || 'Não consegui começar a conexão com a OLX.')
  }
}

export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM mexe na conta.')
    const corpo = await req.json().catch(() => ({} as any))
    if (!ehContaOlx(corpo?.conta)) return apiError(400, 'Diga a conta: proprietarios ou corretores.')
    const r = await ligarWebhookOlx(corpo.conta)
    return Response.json({ ok: r.ok, resposta: r.resposta }, { status: r.ok ? 200 : 502 })
  } catch (err: any) {
    console.error('[olx/conectar] webhook', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ligar o webhook na OLX.')
  }
}
