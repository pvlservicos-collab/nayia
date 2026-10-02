/**
 * POST /api/public/imovel-consulta/vincular -- O BOT CONFIRMOU QUE É O MESMO
 * IMÓVEL (Pedro, 01/10/2026; pedido do bot: "crie também um endpoint para
 * registrar o link do anúncio num imóvel existente quando eu confirmar que é o
 * mesmo, assim a próxima consulta já bate por link").
 *
 *   entra  { id_imovel, link, portal?, id_anuncio? }
 *   sai    { ok, id_imovel, link, id_anuncio, ja_estava, mensagem }  ou  { ok: false, erro }
 *
 * Grava em `imovel_anuncio` (migração 258). O mesmo anúncio não entra em dois
 * imóveis: a segunda tentativa volta com o imóvel em que ele já está.
 */
import { NextRequest } from 'next/server'
import { naydb } from '@/lib/nayDisparo'
import { erroDoBot, pedidoDoBot } from '@/lib/botDeImoveis'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest) {
  const pedido = await pedidoDoBot(req)
  if (!pedido.ok) return pedido.resposta
  const c = pedido.corpo
  const codigo = Number(String(c.id_imovel ?? c.codigo ?? '').replace(/\D/g, ''))
  const link = String(c.link ?? '').trim()
  if (!Number.isInteger(codigo) || codigo <= 0) return erroDoBot(400, 'Faltou o "id_imovel" (o número que veio na consulta).')
  if (!link) return erroDoBot(400, 'Faltou o "link" do anúncio.')
  try {
    const r = await naydb().query(
      'SELECT crm_imovel_vincular_anuncio($1::int, $2::text, $3::text, $4::text, $5::text) AS r',
      [codigo, link.slice(0, 600), c.portal ? String(c.portal).slice(0, 30) : null,
       c.id_anuncio ? String(c.id_anuncio).slice(0, 40) : null, 'grokbot'])
    const resposta = r.rows[0]?.r
    if (!resposta || typeof resposta !== 'object') return erroDoBot(502, 'O banco não respondeu.')
    return Response.json(resposta, { status: resposta.ok === false ? 409 : 200 })
  } catch (err: any) {
    console.error('[imovel-consulta/vincular]', err?.message || err)
    return erroDoBot(502, 'Não consegui registrar agora. Tente de novo em alguns minutos.')
  }
}

export async function GET() {
  return erroDoBot(405, 'Use POST com { id_imovel, link }.')
}
