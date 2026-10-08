/**
 * GET /api/olx/oauth?code=...&state=... -- A VOLTA DA OLX depois que o dono da conta autorizou
 * (Pedro, 08/10/2026). É a `redirect_uri` cadastrada no aplicativo da OLX; não pode mudar de endereço
 * sem avisar a OLX.
 *
 * O que acontece aqui, na ordem:
 *   1. confere que quem voltou é quem começou (o `state` tem de ser o do cookie deste navegador);
 *   2. troca o código pelo token da conta (vale 10 minutos e uma vez só);
 *   3. grava o token e quem é a conta na OLX (para a equipe conferir que ligou a certa);
 *   4. liga o webhook do chat dessa conta, apontando para o nosso endereço;
 *   5. volta para a aba Chat OLX dizendo o que deu.
 *
 * Se o passo 4 falhar, a conta fica conectada e a aba mostra o botão "Ligar o recebimento" para tentar
 * de novo -- não é preciso autorizar outra vez.
 */
import { NextRequest, NextResponse } from 'next/server'
import { eq } from 'drizzle-orm'
import { authenticateRequest } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { ehContaOlx, enderecoNoCrm, gravarConexaoOlx, ligarWebhookOlx, quemEAContaOlx, tokenPeloCodigoOlx } from '@/lib/olxChat'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const COOKIE = 'olx_oauth_estado'   // o mesmo de /api/olx/conectar

function voltar(conta: string | null, aviso: string) {
  const u = enderecoNoCrm('/chat/olx')
  if (conta) u.searchParams.set('conta', conta)
  u.searchParams.set('aviso', aviso)
  const r = NextResponse.redirect(u)
  r.cookies.set(COOKIE, '', { path: '/api/olx', maxAge: 0 })
  return r
}

export async function GET(req: NextRequest) {
  const estado = req.nextUrl.searchParams.get('state') || ''
  const conta = estado.split('.')[0] || null
  const contaValida = ehContaOlx(conta) ? conta : null
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return voltar(contaValida, 'Entre no CRM antes de conectar a conta da OLX.')
    if (!contaValida) return voltar(null, 'A OLX voltou sem dizer de qual conta era. Comece de novo pelo botão Conectar.')
    const doCookie = req.cookies.get(COOKIE)?.value || ''
    if (!doCookie || doCookie !== estado) {
      return voltar(contaValida, 'Esta volta da OLX não é a da conexão que você começou (ou passou de 15 minutos). Clique em Conectar de novo.')
    }
    const erroDaOlx = req.nextUrl.searchParams.get('error')
    const codigo = req.nextUrl.searchParams.get('code') || ''
    if (erroDaOlx || !codigo) return voltar(contaValida, 'A autorização não foi concluída na OLX. Nada mudou.')

    const token = await tokenPeloCodigoOlx(codigo)
    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const quemE = await quemEAContaOlx(token)
    await gravarConexaoOlx(contaValida, token, perfil?.nome?.trim() || 'alguém no CRM', quemE.nome, quemE.email)

    let recebimento = ''
    try {
      const w = await ligarWebhookOlx(contaValida)
      recebimento = w.ok ? 'O recebimento das mensagens está ligado.' : `Mas a OLX não ligou o recebimento (${w.resposta}): use o botão "Ligar o recebimento".`
    } catch (e: any) {
      recebimento = `Mas não consegui ligar o recebimento (${e?.message || 'erro'}): use o botão "Ligar o recebimento".`
    }
    return voltar(contaValida, `Conta conectada${quemE.nome ? ` (${quemE.nome})` : ''}. ${recebimento}`)
  } catch (err: any) {
    console.error('[olx/oauth]', err?.message || err)
    return voltar(contaValida, err?.message || 'Não consegui concluir a conexão com a OLX.')
  }
}
