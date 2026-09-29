/**
 * O código de imóvel escrito numa mensagem. Funções puras, sem rede.
 *
 * Mora separado de `imoveisNay.ts` de propósito: aquele arquivo fala com a API
 * do site e só roda no servidor. Estas duas rodam na tela (o campo de mensagem
 * precisa reconhecer `/3050` enquanto a pessoa digita), e arrastar o cliente
 * HTTP para o navegador junto seria peso sem uso.
 */

/**
 * O código que a pessoa referenciou no campo de mensagem.
 *
 * Aceita `/3050`, `/imovel 3050` e `/cod 3050` -- a barra é o que o Tel pediu
 * ("ele pode só referenciar /codigo"). `3050` sozinho NÃO conta: numa
 * negociação a pessoa digita número o tempo todo, e cada um deles viraria um
 * envio de imóvel que ninguém pediu.
 */
export function codigoReferenciado(texto: string): number | null {
  const m = String(texto || '').trim().match(/^\/(?:im(?:o|ó)vel\s+|cod(?:igo)?\s+)?(\d{3,5})$/i)
  return m ? Number(m[1]) : null
}

/** Os códigos citados dentro de um texto qualquer (card colado, "Código: 3050"). */
export function codigosNoTexto(texto: string): number[] {
  const achados: number[] = []
  for (const m of String(texto || '').matchAll(/c(?:o|ó)digo:?\s*(\d{3,5})/gi)) {
    const n = Number(m[1])
    if (!achados.includes(n)) achados.push(n)
  }
  return achados
}
