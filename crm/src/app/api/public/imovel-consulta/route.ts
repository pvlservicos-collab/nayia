/**
 * POST /api/public/imovel-consulta -- O BOT DA OLX PERGUNTA "TEMOS ESTE IMÓVEL?"
 * E RECEBE O QUE FAZER (Pedro, 08/10/2026): "ele vai achar um anúncio, mandar o
 * link e informações pra ti, tu vai checar no banco de dados e vai devolver se
 * temos para ele fechar, e se não temos para ele abordar e a mensagem para ele
 * mandar".
 *
 *   entra  { link*, portal, id_anuncio, titulo, descricao, tipo, finalidade, preco,
 *            cidade, uf, bairro, endereco, cep, condominio_nome, area_m2, quartos,
 *            suites, banheiros, vagas, valor_condominio, anunciante_nome,
 *            anunciante_perfil, profissional, telefone, teste }
 *   sai    { consulta_ok: true, acao: "fechar" | "abordar", temos, motivo,
 *            explicacao, id_imovel?, mensagem?, id_consulta, repetido? }
 *          ou { consulta_ok: false, codigo_erro, erro, faltam? }
 *
 * QUEM DECIDE É O BANCO (crm_anuncio_decidir, migração 309); o bot só obedece
 * `acao`. Até 07/10 esta rota devolvia a lista de candidatos (258) e a decisão
 * era de um agente do lado do bot -- isso acabou.
 *
 * FALHA NUNCA É "ABORDAR": em erro a resposta tem `consulta_ok: false` e `erro`,
 * nunca vem vazia, e nada fica gravado.
 *
 * Com `"teste": true` nada é gravado e a resposta não é ordem (`acao: "nenhuma"`).
 */
import { NextRequest } from 'next/server'
import { naydb } from '@/lib/nayDisparo'
import { erroDoBot, pedidoDoBot } from '@/lib/botDeImoveis'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const STATUS_DO_ERRO: Record<string, number> = { faltam_campos: 400, formato: 400, grande_demais: 413, falha: 502, texto: 502 }

export async function POST(req: NextRequest) {
  const pedido = await pedidoDoBot(req, 'consulta')
  if (!pedido.ok) return pedido.resposta
  const anuncio = pedido.corpo
  if (!String(anuncio.link ?? '').trim()) return erroDoBot(400, 'Faltou o "link" do anúncio.')
  try {
    const r = await naydb().query('SELECT crm_anuncio_decidir($1::jsonb) AS r', [JSON.stringify(anuncio)])
    const resposta = r.rows[0]?.r
    if (!resposta || typeof resposta !== 'object') return erroDoBot(502, 'O banco não respondeu a consulta.')
    const status = resposta.consulta_ok === false ? (STATUS_DO_ERRO[String(resposta.codigo_erro)] ?? 422) : 200
    return Response.json(resposta, { status })
  } catch (err: any) {
    console.error('[imovel-consulta]', err?.message || err)
    return erroDoBot(502, 'Não consegui consultar agora. Tente de novo em alguns minutos.')
  }
}

export async function GET() {
  return erroDoBot(405, 'Use POST com o JSON do anúncio.')
}
