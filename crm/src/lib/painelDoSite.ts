/**
 * O PAINEL DE IMÓVEIS DO SITE, POR DENTRO DO CRM (Pedro, 30/09/2026): "quero
 * trocar essa aba imóveis do crm pela aba todos os imóveis lá do site,
 * exatamente como está no site, com todas as funções do site".
 *
 * A aba do site são ~1.800 linhas de JavaScript próprio e muda toda semana.
 * Uma cópia em React nasceria desatualizada. Então o CRM não copia: ele SERVE
 * a própria página do site, pelos mesmos caminhos (/admin/... e /assets/...),
 * buscando os arquivos no container do site pela rede interna do Docker. O que
 * mudar lá aparece aqui na mesma hora, sem deploy do CRM.
 *
 * DUAS REGRAS DE SEGURANÇA:
 *  - Só passa quem está logado no CRM (o middleware e o authenticateRequest).
 *  - Do /admin do site só passam as duas telas de imóveis e a API de imóveis.
 *    O resto do admin (captação, vagas, prompt da Nay) NÃO é servido aqui: o
 *    segredo de máquina abriria tudo, e ninguém pediu tudo.
 */
const WEB = process.env.SITE_WEB_INTERNA || 'http://nay-site-web'
const API = process.env.SITE_API_INTERNA || 'http://nay-site-api:8092'

export const PAGINAS_DO_PAINEL = new Set(['imoveis.html', 'imovel-editar.html'])

/** Caminho seguro: sem "..", sem barra invertida, sem nada que saia da pasta. */
export function caminhoLimpo(partes: string[]): string | null {
  if (!partes.length) return null
  for (const p of partes) {
    if (!p || p === '.' || p === '..' || p.includes('\\') || p.includes('\u0000')) return null
  }
  return partes.map(encodeURIComponent).join('/')
}

const REPASSAR_DA_RESPOSTA = ['content-type', 'etag', 'last-modified', 'cache-control', 'content-disposition']

/** Um arquivo do site (script, estilo, imagem), com a revalidação de cache repassada. */
export async function arquivoDoSite(caminho: string, busca: string, pedido: Headers): Promise<Response> {
  const cabecalhos: Record<string, string> = {}
  for (const c of ['if-none-match', 'if-modified-since']) {
    const v = pedido.get(c)
    if (v) cabecalhos[c] = v
  }
  const r = await fetch(`${WEB}/${caminho}${busca}`, { headers: cabecalhos, cache: 'no-store' })
  const saida = new Headers()
  for (const c of REPASSAR_DA_RESPOSTA) {
    const v = r.headers.get(c)
    if (v) saida.set(c, v)
  }
  return new Response(r.status === 304 ? null : r.body, { status: r.status, headers: saida })
}

/**
 * A página, com o menu e o rodapé do site escondidos: dentro do CRM o menu é o
 * do CRM, e dois menus um em cima do outro só confundem. O resto da página
 * fica como é -- é só um estilo a mais, nada do site é reescrito.
 */
export async function paginaDoSite(arquivo: string, busca: string): Promise<Response> {
  const r = await fetch(`${WEB}/admin/${arquivo}${busca}`, { cache: 'no-store' })
  if (!r.ok) return new Response('Página do site indisponível.', { status: r.status })
  const html = (await r.text()).replace('</head>',
    '<style>[data-layout-topo],[data-layout-rodape],.pular-conteudo{display:none!important}</style></head>')
  return new Response(html, { status: 200, headers: { 'content-type': 'text/html; charset=utf-8', 'cache-control': 'no-store' } })
}

/** A API de admin do site, com o segredo de máquina no lugar da senha do /admin. */
export async function apiDoAdmin(caminho: string, busca: string, metodo: string, corpo: ArrayBuffer | null, tipo: string | null): Promise<Response> {
  const segredo = process.env.CRM_PAINEL_SEGREDO || ''
  if (!segredo) return Response.json({ erro: 'CRM_PAINEL_SEGREDO não configurado no CRM' }, { status: 503 })
  const r = await fetch(`${API}/admin/${caminho}${busca}`, {
    method: metodo,
    headers: { 'X-Painel-Crm': segredo, ...(tipo ? { 'Content-Type': tipo } : {}) },
    body: corpo && corpo.byteLength ? corpo : undefined,
    cache: 'no-store',
  })
  const saida = new Headers({ 'cache-control': 'no-store' })
  const ct = r.headers.get('content-type')
  if (ct) saida.set('content-type', ct)
  return new Response(r.body, { status: r.status, headers: saida })
}
