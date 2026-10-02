/**
 * A PORTA DO GROKBOT PARA OS IMÓVEIS (Pedro, 01/10/2026): "eu quero meu grokbot
 * perguntando sobre um imóvel que ele achou para nosso sistema e o sistema
 * responde apenas".
 *
 * Quem autentica as rotas /api/public/imovel-consulta[/vincular]:
 *
 *   por HTTPS  ->  Authorization: Bearer <token>   (foi o que o bot pediu)
 *   pela porta 80 -> só o PEDIDO LACRADO { hora, cifrado, assinatura }, o mesmo
 *                    lacre do aviso ao Tel (src/lib/avisoLacrado.ts), em que o
 *                    texto cifrado é o JSON do pedido. A nuvem do bot do Grok
 *                    corta o HTTPS para os nossos servidores (medido em 01/10),
 *                    e token aberto por HTTP é token entregue a quem estiver no
 *                    caminho -- por isso ele é recusado ali.
 *
 * O token é BOT_IMOVEIS_CHAVE no .env do CRM (fora do git). É OUTRO segredo, não
 * o AVISO_TEL_CHAVE: aquele manda mensagem no WhatsApp do Tel, este só consulta
 * o catálogo -- quem tem um não ganha o outro. Sem ele configurado a porta fica
 * fechada (503), nunca aberta.
 *
 * A resposta de erro NUNCA é vazia: sempre `consulta_ok: false` com `erro`. O
 * bot avisou que resposta vazia vira falso negativo ("não é nosso") do lado
 * dele.
 */
import { NextRequest } from 'next/server'
import { timingSafeEqual } from 'node:crypto'
import { abrirAvisoLacrado } from '@/lib/avisoLacrado'

export type PedidoDoBot = { ok: true; corpo: Record<string, unknown> } | { ok: false; resposta: Response }

const erro = (status: number, mensagem: string) =>
  Response.json({ consulta_ok: false, ok: false, erro: mensagem }, { status })

/* 120 pedidos por minuto, por processo: o bot consulta anúncio por anúncio, e
   isso sobra; quem achar o token não varre o catálogo inteiro em um minuto. */
const JANELA_MS = 60_000
const TETO = 120
let janelaDesde = 0
let naJanela = 0
function passouDoTeto(agora = Date.now()): boolean {
  if (agora - janelaDesde > JANELA_MS) { janelaDesde = agora; naJanela = 0 }
  naJanela += 1
  return naJanela > TETO
}

function confere(veio: string, certa: string): boolean {
  const a = Buffer.from(certa), b = Buffer.from(veio)
  return a.length === b.length && timingSafeEqual(a, b)
}

/** Lê o pedido do bot e diz se ele pode entrar. O corpo devolvido já é o JSON aberto. */
export async function pedidoDoBot(req: NextRequest): Promise<PedidoDoBot> {
  const segredo = process.env.BOT_IMOVEIS_CHAVE || ''
  if (!segredo) return { ok: false, resposta: erro(503, 'A consulta de imóveis não está configurada.') }
  if (passouDoTeto()) return { ok: false, resposta: erro(429, 'Pedidos demais em um minuto. Espere e tente de novo.') }

  const texto = await req.text().catch(() => '')
  let corpo: unknown
  try { corpo = texto ? JSON.parse(texto) : {} } catch {
    return { ok: false, resposta: erro(400, 'O corpo não é um JSON válido.') }
  }
  if (!corpo || typeof corpo !== 'object' || Array.isArray(corpo)) {
    return { ok: false, resposta: erro(400, 'Mande um objeto JSON.') }
  }
  const c = corpo as Record<string, unknown>

  if (c.cifrado !== undefined || c.assinatura !== undefined) {
    // O PEDIDO LACRADO: quem prova que é o bot é a assinatura; o token não viaja
    const aberto = abrirAvisoLacrado(segredo, c.hora, c.cifrado, c.assinatura)
    if (!aberto.ok) return { ok: false, resposta: erro(401, `Não aceitei: ${aberto.motivo}.`) }
    try {
      const dentro = JSON.parse(aberto.mensagem)
      if (!dentro || typeof dentro !== 'object' || Array.isArray(dentro)) throw new Error('não é objeto')
      return { ok: true, corpo: dentro as Record<string, unknown> }
    } catch {
      return { ok: false, resposta: erro(400, 'O texto cifrado tem de ser o JSON do pedido.') }
    }
  }

  // o token puro: só por HTTPS (o Traefik diz por onde o pedido entrou)
  const porHttps = (req.headers.get('x-forwarded-proto') || '').split(',')[0].trim() === 'https'
  if (!porHttps) {
    return { ok: false, resposta: erro(400, 'Pela porta 80 só aceito o pedido lacrado (hora, cifrado, assinatura). Não mande o token por aqui.') }
  }
  const bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '').trim()
  if (!bearer) return { ok: false, resposta: erro(401, 'Faltou o token: Authorization: Bearer <token>.') }
  if (!confere(bearer, segredo)) return { ok: false, resposta: erro(401, 'Token errado.') }
  return { ok: true, corpo: c }
}

export { erro as erroDoBot }
