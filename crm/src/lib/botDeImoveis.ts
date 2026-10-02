/**
 * A PORTA DOS BOTS PARA OS IMÓVEIS (Pedro, 01–02/10/2026).
 *
 * SÃO DOIS WEBHOOKS, DE DOIS BOTS, E UM NÃO SABE DO OUTRO (Pedro, 01/10: "são
 * webhooks diferentes com funções diferentes que vão ser disparados por bots
 * diferentes, você precisa se atentar a isso"):
 *
 *   'consulta'  /api/public/imovel-consulta  e  /imovel-consulta/vincular
 *               o bot pergunta se um anúncio já é nosso      token: BOT_IMOVEIS_CHAVE
 *   'cadastro'  /api/public/imovel-cadastro
 *               o bot manda um imóvel para aprovação humana   token: BOT_CADASTRO_CHAVE
 *
 * CADA UM TEM O SEU TOKEN, e o de um não abre o outro: quem tem o da consulta
 * (só lê) não consegue cadastrar, e o do cadastro não lê o catálogo. Cada um tem
 * também o seu limite de pedidos -- um bot em laço não derruba o outro. A
 * primeira versão (01/10) usava um token só para os dois; era isso o erro.
 *
 * Como cada bot prova quem é:
 *   por HTTPS     ->  Authorization: Bearer <token>
 *   pela porta 80 ->  só o PEDIDO LACRADO { hora, cifrado, assinatura }, o mesmo
 *                     lacre do aviso ao Tel (src/lib/avisoLacrado.ts), em que o
 *                     texto cifrado é o JSON do pedido e a chave é o token DAQUELE
 *                     webhook. A nuvem do bot do Grok corta o HTTPS para os nossos
 *                     servidores (medido em 01/10), e token aberto por HTTP é
 *                     token entregue a quem estiver no caminho.
 *
 * Os tokens ficam no .env do CRM (fora do git). Sem o token configurado, aquele
 * webhook fica fechado (503), nunca aberto.
 *
 * A resposta de erro NUNCA é vazia: sempre JSON com `ok: false`, `consulta_ok:
 * false` e `erro`. Resposta vazia vira falso negativo do lado do bot.
 */
import { NextRequest } from 'next/server'
import { timingSafeEqual } from 'node:crypto'
import { abrirAvisoLacrado } from '@/lib/avisoLacrado'

export type WebhookDoBot = 'consulta' | 'cadastro'
export type PedidoDoBot = { ok: true; corpo: Record<string, unknown> } | { ok: false; resposta: Response }

const TOKEN_DE: Record<WebhookDoBot, string> = { consulta: 'BOT_IMOVEIS_CHAVE', cadastro: 'BOT_CADASTRO_CHAVE' }
/* por minuto, por processo. A consulta vai anúncio por anúncio; o cadastro é
   raro (só com autorização do proprietário) -- 30 já é muito. */
const TETO: Record<WebhookDoBot, number> = { consulta: 120, cadastro: 30 }
const JANELA_MS = 60_000
const janela: Record<WebhookDoBot, { desde: number; n: number }> = {
  consulta: { desde: 0, n: 0 }, cadastro: { desde: 0, n: 0 },
}

const erro = (status: number, mensagem: string) =>
  Response.json({ consulta_ok: false, ok: false, erro: mensagem }, { status })

function passouDoTeto(qual: WebhookDoBot, agora = Date.now()): boolean {
  const j = janela[qual]
  if (agora - j.desde > JANELA_MS) { j.desde = agora; j.n = 0 }
  j.n += 1
  return j.n > TETO[qual]
}

function confere(veio: string, certa: string): boolean {
  const a = Buffer.from(certa), b = Buffer.from(veio)
  return a.length === b.length && timingSafeEqual(a, b)
}

/** Lê o pedido do bot DAQUELE webhook e diz se ele pode entrar. O corpo devolvido já é o JSON aberto. */
export async function pedidoDoBot(req: NextRequest, qual: WebhookDoBot): Promise<PedidoDoBot> {
  const segredo = process.env[TOKEN_DE[qual]] || ''
  if (!segredo) return { ok: false, resposta: erro(503, 'Este webhook não está configurado.') }
  if (passouDoTeto(qual)) return { ok: false, resposta: erro(429, 'Pedidos demais em um minuto. Espere e tente de novo.') }

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
  if (!confere(bearer, segredo)) return { ok: false, resposta: erro(401, 'Token errado para este webhook.') }
  return { ok: true, corpo: c }
}

export { erro as erroDoBot }
