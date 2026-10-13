import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function middleware(req: NextRequest) {
  const { pathname } = req.nextUrl

  const publicPaths = [
    '/login', '/ativar-conta', '/api/auth', '/api/webhooks', '/api/funnels/tick', '/api/integrations/instagram/check-tokens',
    // Entrada de leads: o handler autentica sozinho (chave `atl_` no cabeçalho
    // OU em ?key=, porque plugin de formulário do WordPress muitas vezes não
    // deixa mandar cabeçalho). O bypass de Bearer logo abaixo não cobre o caso
    // do ?key=, então sem esta linha o webhook do site caía no redirect de
    // login e o lead se perdia.
    '/api/ingest',
    // Formulário de aplicação do site: roda no navegador de quem se inscreve,
    // sem sessão e sem token nenhum (a rota valida origem, fonte e limite por
    // IP sozinha). Sem esta linha o envio caía no redirect de login e a
    // aplicação da pessoa se perdia. O arquivo dela é
    // public/formulario-aplicacao.html, que também precisa abrir sem sessão.
    '/api/public/',
    '/formulario-aplicacao.html',
    '/codigo-do-formulario.html',
    // Cron da Vercel não manda cookie de sessão nem Authorization (CRON_SECRET não está
    // configurado no projeto) — sem isso na lista, toda chamada do cron caía no redirect
    // de login e a reconciliação nunca rodou de verdade desde que foi criada (13/07).
    '/api/cron/evolution-reconcile',
    // Manifest/service worker/ícones do PWA: o navegador busca isso sem sessão
    // (checagem de instalabilidade), então não pode cair no redirect de login.
    '/manifest.webmanifest', '/sw.js', '/icons/',
    // Assets estáticos de public/ servidos na raiz (logos, fontes, imagens de fundo) —
    // o matcher abaixo só livra _next/static e afins, então sem isso qualquer imagem
    // usada numa tela sem sessão (ex: login) cairia no redirect também.
    '/logos/', '/fonts/', '/chat-bg.svg',
    // A mídia do armazém (29/09): a própria rota confere a sessão OU o endereço
    // assinado. A Z-API e a Meta baixam o que mandamos sem cookie nenhum, e o
    // redirect de login entregaria a elas uma página HTML no lugar da foto.
    '/api/midia/',
    // A conferência com a Nay (29/09): o cron do servidor chama com o segredo
    // CRON_SEGREDO no cabeçalho, e é a rota que confere.
    '/api/cron/espelho-nay', '/api/cron/funis', '/api/cron/followups',
    // A volta da OLX (13/10): é a redirect_uri que vai no cadastro do aplicativo, e a OLX confere se o endereço
    // abre. A própria rota exige a sessão para trocar o código; sem código ela só mostra uma página de aviso.
    '/api/olx/oauth',
  ]
  const isPublic = publicPaths.some((p) => pathname.startsWith(p))

  if (isPublic) return NextResponse.next()

  // Requisições com Bearer token (API externa, n8n, etc.) passam direto — auth é validada no handler
  if (req.headers.get('authorization')?.startsWith('Bearer ')) return NextResponse.next()

  // NextAuth v5 usa "authjs.session-token" (v4 usava "next-auth.session-token")
  const sessionToken =
    req.cookies.get('__Secure-authjs.session-token') ??
    req.cookies.get('authjs.session-token') ??
    req.cookies.get('next-auth.session-token') ??
    req.cookies.get('__Secure-next-auth.session-token')

  // Sem sessão vai pro login. Ficou desativado durante a revisão visual do
  // redesign, com uma identidade "demo" sintetizada no cliente pra as telas não
  // renderizarem vazias. Isso saiu junto: em produção, o app servia dados falsos
  // (leads e conversas de exemplo) pra quem abrisse sem logar — indistinguíveis
  // dos reais na tela, o que é pior que uma tela vazia.
  // CADA UM COM O SEU LOGIN (Tel, 26/09/2026): "tira essa entrada
  // automatica, deixa o login normal do app mesmo".
  //
  // De 20/09 ate aqui, quem chegasse sem sessao era mandado para
  // /api/auth/entrar, que logava SEMPRE como o usuario unico da casa. Com
  // uma pessoa so isso passava; com duas, nao: a Rayssa entrava e virava o
  // Tel, com permissao de Admin, e o cargo dela nao valia nada.
  //
  // O navegador guarda a senha: o formulario tem autoComplete username +
  // current-password e e um <form> de verdade, entao o "salvar senha"
  // aparece e o preenchimento automatico funciona nas proximas vezes.
  if (!sessionToken) {
    const login = new URL('/login', req.url)
    // volta para onde a pessoa queria ir depois de entrar
    if (pathname && pathname !== '/') login.searchParams.set('callbackUrl', pathname)
    return NextResponse.redirect(login)
  }

  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|public/).*)'  ],
}
