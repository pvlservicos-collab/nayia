/**
 * POST /api/public/imovel-consulta -- O GROKBOT PERGUNTA SE UM ANÚNCIO JÁ É NOSSO
 * (Pedro, 01/10/2026). O contrato é o que o próprio bot pediu:
 *
 *   entra  { link, portal, id_anuncio, titulo, tipo, finalidade, preco, cidade, uf,
 *            bairro, endereco, cep, condominio_nome, area_m2, quartos, suites,
 *            banheiros, vagas, valor_condominio, anunciante_nome, telefone }
 *          -- só o link é obrigatório; campo nulo não desclassifica ninguém
 *   sai    { consulta_ok, total_candidatos, melhor_score, entendido, candidatos: [
 *            { id_imovel, score, confianca, campos_que_bateram, campos_divergentes, dados } ] }
 *
 * Quem compara é o banco (crm_imovel_candidatos, migração 258); esta rota só
 * confere quem está pedindo (src/lib/botDeImoveis.ts) e repassa. A decisão de
 * "é o mesmo imóvel" é de outro agente, do lado do bot.
 *
 * Em erro a resposta tem `consulta_ok: false` e `erro` -- nunca vem vazia.
 */
import { NextRequest } from 'next/server'
import { naydb } from '@/lib/nayDisparo'
import { erroDoBot, pedidoDoBot } from '@/lib/botDeImoveis'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest) {
  const pedido = await pedidoDoBot(req)
  if (!pedido.ok) return pedido.resposta
  const anuncio = pedido.corpo
  if (!String(anuncio.link ?? '').trim()) return erroDoBot(400, 'Faltou o "link" do anúncio.')
  try {
    const r = await naydb().query('SELECT crm_imovel_candidatos($1::jsonb) AS r', [JSON.stringify(anuncio)])
    const resposta = r.rows[0]?.r
    if (!resposta || typeof resposta !== 'object') return erroDoBot(502, 'O banco não respondeu a consulta.')
    return Response.json(resposta, { status: resposta.consulta_ok === false ? 422 : 200 })
  } catch (err: any) {
    console.error('[imovel-consulta]', err?.message || err)
    return erroDoBot(502, 'Não consegui consultar agora. Tente de novo em alguns minutos.')
  }
}

export async function GET() {
  return erroDoBot(405, 'Use POST com o JSON do anúncio.')
}
