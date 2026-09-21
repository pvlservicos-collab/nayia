/**
 * GET /api/auth/entrar
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
  const email = process.env.LOGIN_AUTOMATICO_EMAIL
  const senha = process.env.LOGIN_AUTOMATICO_SENHA

  if (!email || !senha) {
    return new NextResponse(
      'LOGIN_AUTOMATICO_EMAIL e LOGIN_AUTOMATICO_SENHA nao estao no .env. ' +
        'Sem eles nao ha como entrar sem a tela de login.',
      { status: 500 },
    )
  }

  // Para onde a pessoa queria ir. So caminho interno: um callbackUrl absoluto
  // viraria redirecionamento aberto, e isto aqui responde sem sessao.
  const pedido = req.nextUrl.searchParams.get('callbackUrl') || '/'
  const destino = pedido.startsWith('/') && !pedido.startsWith('//') ? pedido : '/'

  try {
    // signIn com redirectTo lanca NEXT_REDIRECT, que o Next trata sozinho.
    return await signIn('credentials', { email, password: senha, redirectTo: destino })
  } catch (erro) {
    // O redirect do Next passa por aqui como excecao: deixa subir.
    if (erro && typeof erro === 'object' && 'digest' in erro) throw erro

    return new NextResponse(
      'Nao consegui entrar com o usuario automatico. Confira se ele existe no ' +
        'banco (scripts/criar-usuario.mjs) e se a senha no .env bate.',
      { status: 500 },
    )
  }
}
