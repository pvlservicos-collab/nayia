/**
 * /api/public/aviso-ao-tel -- UM ROBÔ DE FORA AVISA O TEL PELO WHATSAPP
 * (Pedro, 01/10/2026): "cria um link para eu pôr em um Grok bot, usando nossa
 * tecnologia, para ele mandar mensagem para o Tel avisando as coisas, só o
 * endpoint com a mensagem certa".
 *
 *   POST  { "mensagem": "...", "origem": "Grok" }     com a chave no cabeçalho
 *         Authorization: Bearer <chave>   (ou  x-aviso-chave: <chave>)
 *   GET   ?chave=<chave>&mensagem=...                 para robô que só sabe abrir link
 *   POST  { "hora", "cifrado", "assinatura" }         O AVISO LACRADO, o único jeito
 *         que vale pela porta 80 (src/lib/avisoLacrado.ts): a nuvem do bot do
 *         Grok corta o HTTPS para cá, então ele manda por HTTP com o texto
 *         cifrado e assinado -- a chave nunca viaja.
 *
 * A CHAVE PURA SÓ VALE POR HTTPS. Pela porta 80 ela é recusada: aceitar seria
 * ensinar alguém a mandá-la aberta pela internet.
 *
 * A chave é AVISO_TEL_CHAVE no .env do CRM (não está no git). Sem ela
 * configurada, a porta fica fechada (503) -- nunca aberta.
 *
 * Quem protege o celular do Tel é o banco (migração 251): a mesma mensagem não
 * sai duas vezes em 30 min, no máximo 12 por hora e 60 por dia, e tudo o que
 * chega fica registrado em `aviso_externo`, aceito ou não. A mensagem sai pela
 * caixa da Nay, com "Aviso do <origem>:" na frente.
 *
 * O caminho está em /api/public/ (o middleware deixa passar sem sessão): quem
 * autentica é esta rota, pela chave.
 */
import { NextRequest } from 'next/server'
import { timingSafeEqual } from 'node:crypto'
import { naydb } from '@/lib/nayDisparo'
import { abrirAvisoLacrado } from '@/lib/avisoLacrado'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

function chaveConfere(veio: string | null): boolean | null {
  const certa = process.env.AVISO_TEL_CHAVE || ''
  if (!certa) return null                       // porta fechada: não configurado
  if (!veio) return false
  const a = Buffer.from(certa), b = Buffer.from(veio)
  return a.length === b.length && timingSafeEqual(a, b)
}

async function atender(req: NextRequest, corpo: Record<string, unknown>): Promise<Response> {
  const q = req.nextUrl.searchParams
  const segredo = process.env.AVISO_TEL_CHAVE || ''
  if (!segredo) return Response.json({ ok: false, mensagem: 'Aviso ao Tel não está configurado.' }, { status: 503 })

  let mensagem: string
  if (corpo.cifrado !== undefined || corpo.assinatura !== undefined) {
    // O AVISO LACRADO: quem prova que é o bot é a assinatura, não a chave
    const aberto = abrirAvisoLacrado(segredo, corpo.hora, corpo.cifrado, corpo.assinatura)
    if (!aberto.ok) return Response.json({ ok: false, mensagem: `Não aceitei: ${aberto.motivo}.` }, { status: 401 })
    mensagem = aberto.mensagem
  } else {
    // a chave pura: só por HTTPS (o Traefik diz por onde o pedido entrou)
    const porHttps = (req.headers.get('x-forwarded-proto') || '').split(',')[0].trim() === 'https'
    const bearer = (req.headers.get('authorization') || '').replace(/^Bearer\s+/i, '').trim()
    const chave = bearer || req.headers.get('x-aviso-chave') || q.get('chave') || String(corpo.chave || '') || null
    if (!porHttps) {
      return Response.json({ ok: false, mensagem: 'Pela porta 80 só aceito o aviso lacrado (hora, cifrado, assinatura). Não mande a chave por aqui.' }, { status: 400 })
    }
    if (!chaveConfere(chave)) return Response.json({ ok: false, mensagem: 'Chave errada.' }, { status: 401 })
    mensagem = String(corpo.mensagem ?? corpo.message ?? corpo.texto ?? corpo.text ?? q.get('mensagem') ?? q.get('message') ?? '').trim()
  }
  const origem = String(corpo.origem ?? q.get('origem') ?? 'Grok').trim()
  if (!mensagem) return Response.json({ ok: false, mensagem: 'Faltou a mensagem.' }, { status: 400 })

  try {
    const r = await naydb().query('SELECT * FROM crm_avisar_tel($1::text, $2::text)', [mensagem.slice(0, 4000), origem])
    const l = r.rows[0] || {}
    const ok = l.ok === true
    // recusado por regra (repetida, limite) é 429: o robô entende que é para parar, não para insistir
    return Response.json({ ok, mensagem: String(l.mensagem || ''), restamNaHora: Number(l.restam_na_hora ?? 0) }, { status: ok ? 200 : 429 })
  } catch (err: any) {
    console.error('[aviso ao tel]', err?.message || err)
    return Response.json({ ok: false, mensagem: 'Não consegui entregar agora. Tente de novo em alguns minutos.' }, { status: 502 })
  }
}

export async function POST(req: NextRequest) {
  const tipo = req.headers.get('content-type') || ''
  let corpo: Record<string, unknown> = {}
  if (tipo.includes('application/json')) corpo = await req.json().catch(() => ({}))
  else if (tipo.includes('form')) corpo = Object.fromEntries((await req.formData().catch(() => new FormData())).entries())
  else {
    // texto puro: o corpo inteiro é a mensagem
    const texto = await req.text().catch(() => '')
    try { corpo = JSON.parse(texto) } catch { corpo = { mensagem: texto } }
  }
  return atender(req, corpo && typeof corpo === 'object' ? corpo : {})
}

export async function GET(req: NextRequest) {
  return atender(req, {})
}
