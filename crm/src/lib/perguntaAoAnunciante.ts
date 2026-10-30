/**
 * A PERGUNTA QUE A NAY MANDA AO ANUNCIANTE DA OLX (nay-olx/olx/buscas.py: pergunta_ao_anunciante + trecho_do_predio),
 * para a busca manual (Pedro, 30/10/2026: "quando clicar em criar conversa já cria aquela mesma mensagem que a Nay
 * envia, digitada no WhatsApp, para ele só enviar"). Sem o link do anúncio (Pedro, 23/10): só o nome do prédio.
 * A Nay confere o prédio no cadastro de condomínios; aqui vale o trecho do título que nomeia o prédio, senão o título.
 */
const PREDIO = /\b(?:cond(?:om[ií]nio)?|resid(?:encial)?|edif[ií]cio|ed)\b\.?\s*(?:(?:cond(?:om[ií]nio)?|resid(?:encial)?)\b\.?\s*)*([^,;|\n]+?)(?=\s*(?:[,;|\n]|\s-\s|$))/i

export function trechoDoPredio(titulo: string | null | undefined): string | null {
  const m = PREDIO.exec(titulo || '')
  const t = (m?.[1] || '').replace(/^[ .-]+|[ .-]+$/g, '')
  return t.length >= 3 ? t : null
}

const reais = (v: number | null | undefined) => (v ? `R$ ${Math.round(Number(v)).toLocaleString('pt-BR')}` : '')

export function perguntaAoAnunciante(a: { titulo: string | null; preco: number | null; preco_texto: string | null; bairro: string | null }): string {
  const onde = [a.preco_texto || reais(a.preco), a.bairro].filter(Boolean).join(' · ')
  const predio = trechoDoPredio(a.titulo)
  const qual = predio ? `do *${predio}*` : `*${a.titulo || 'imóvel'}*`
  return `Olá! Tudo bem? Aqui é a Nay, da Imob Easy. Vi o seu anúncio na OLX ${qual}${onde ? ` (${onde})` : ''}.\n`
    + 'Tenho um cliente com esse perfil. Ele ainda está disponível? Você trabalha com parceria?'
}
