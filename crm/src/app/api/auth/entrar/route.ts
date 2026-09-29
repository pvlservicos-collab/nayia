/**
 * GET /api/auth/entrar -- DESLIGADA em 26/09/2026
 *
 * ENTRADA AUTOMATICA -- o "sem login" que o Tel pediu.
 *
 * Por que nao arrancar a autenticacao: 17 arquivos do app chamam auth() para
 * saber quem e o usuario e de qual organizacao sao os dados. Sem sessao eles
 * nao ficam vazios -- o proprio middleware do projeto modelo registra que, da
 * ultima vez que desativaram o login, o app passou a servir leads e conversas
 * de EXEMPLO indistinguiveis dos reais na tela. Isso e pior que uma tela vazia.
 *
 * Entao a sessao continua existindo e sendo de verdade. O que sai e a TELA de
 * login: quem chega aqui e logado no usuario unico da casa e devolvido para
 * onde queria ir.
 *
 * A porta e protegida FORA do app, pelo basicauth do traefik (a mesma senha
 * simples do /admin do site). Sem isso, este endpoint seria uma porta aberta.
 */
import { NextRequest, NextResponse } from 'next/server'
import { signIn } from '@/lib/auth'

export async function GET(req: NextRequest) {
  /*
   * DESLIGADA (Tel, 26/09/2026): "tira essa entrada automatica, deixa o
   * login normal do app mesmo".
   *
   * Ela existia enquanto a casa tinha um usuario so. Com a Rayssa entrando,
   * virou um buraco: quem chegasse aqui era logado como o Tel, com
   * permissao de Admin, e o cargo SDR dela nao valia nada. Pior, ninguem
   * saberia quem fez o que -- toda acao ficaria no nome do Tel.
   *
   * O arquivo continua aqui, e nao apagado, porque o caminho pode estar
   * salvo em favorito ou atalho de celular: quem cair nele e mandado para a
   * tela de login em vez de receber um erro seco.
   */
  const pedido = req.nextUrl.searchParams.get('callbackUrl') || '/'
  const destino = pedido.startsWith('/') && !pedido.startsWith('//') ? pedido : '/'
  const login = new URL('/login', req.url)
  if (destino !== '/') login.searchParams.set('callbackUrl', destino)
  return NextResponse.redirect(login)
}
