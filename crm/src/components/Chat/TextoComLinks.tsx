/**
 * O texto de uma mensagem com os links clicáveis (Pedro, 07/10/2026: "coloca lá no CRM para ele identificar quando
 * é link e deixar clicável").
 *
 * Reconhece `http(s)://...`, `www....` e o endereço escrito sem protocolo com terminação conhecida
 * ("imobeasy.online/imovel/3050", "wa.me/5592...", "bit.ly/abc"). A pontuação colada no fim (".", ",", ")") fica
 * fora do link, e-mail não vira link e o resto do texto sai exatamente como veio (quebras de linha são do `<p>`
 * de quem usa, com `whitespace-pre-wrap`).
 *
 * Só abre http e https, em aba nova. O clique não chega ao balão, que tem as ações da mensagem.
 * Sem lookbehind no regex: navegador antigo (Safari antes do 16.4) quebraria a tela inteira ao montar o padrão.
 */
import type { MouseEvent } from 'react'

const TERMINACOES = 'com\\.br|net\\.br|org\\.br|gov\\.br|com|online|net|org|app|io|me|ly|gl|br'
const LINK = new RegExp(
  `https?:\\/\\/[^\\s<>"]+|www\\.[^\\s<>"]+|[a-z0-9][a-z0-9-]*(?:\\.[a-z0-9-]+)*\\.(?:${TERMINACOES})(?![a-z0-9-])(?:\\/[^\\s<>"]*)?`,
  'gi',
)
const SOBRA_NO_FIM = /[.,;:!?'"»]+$/
const COLADO_ANTES = /[@\w.\-/]/ // "fulano@gmail.com", "arquivo.final.com" no meio de outra palavra

export interface ParteDoTexto { texto: string; href?: string }

/** Tira do fim do link a pontuação que é da frase, e o parêntese que fecha algo aberto fora dele. */
function aparar(link: string): string {
  let limpo = link.replace(SOBRA_NO_FIM, '')
  while (/[)\]}]$/.test(limpo)) {
    const fecha = limpo.slice(-1)
    const abre = fecha === ')' ? '(' : fecha === ']' ? '[' : '{'
    if (limpo.split(abre).length > limpo.split(fecha).length - 1) break // o par está dentro do link
    limpo = limpo.slice(0, -1).replace(SOBRA_NO_FIM, '')
  }
  return limpo
}

/** O texto em pedaços: os que têm `href` são links. Função pura, para testar sem tela. */
export function partesDoTexto(texto: string | null | undefined): ParteDoTexto[] {
  const t = texto ?? ''
  const partes: ParteDoTexto[] = []
  let ate = 0
  for (const m of Array.from(t.matchAll(LINK))) {
    const inicio = m.index ?? 0
    const comProtocolo = /^(https?:\/\/|www\.)/i.test(m[0])
    if (!comProtocolo && inicio > 0 && COLADO_ANTES.test(t[inicio - 1])) continue
    const link = aparar(m[0])
    if (link.length < 4) continue
    if (inicio > ate) partes.push({ texto: t.slice(ate, inicio) })
    partes.push({ texto: link, href: /^https?:\/\//i.test(link) ? link : `https://${link}` })
    ate = inicio + link.length
  }
  if (ate < t.length) partes.push({ texto: t.slice(ate) })
  return partes
}

const naoSobe = (e: MouseEvent) => e.stopPropagation()

export default function TextoComLinks({ texto }: { texto: string | null | undefined }) {
  return (
    <>
      {partesDoTexto(texto).map((p, i) => (p.href
        ? (
          <a key={i} href={p.href} target="_blank" rel="noopener noreferrer" onClick={naoSobe}
            className="underline break-all" style={{ color: 'var(--wa-link, #027eb5)' }}>
            {p.texto}
          </a>
        )
        : p.texto))}
    </>
  )
}
