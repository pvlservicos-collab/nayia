/**
 * POST /api/public/imovel-cadastro -- O GROKBOT MANDA UM IMÓVEL PARA CADASTRAR
 * (Pedro, 02/10/2026): "o grok vai enviar nome de corretor, número dele, link do
 * imóvel, dados do imóvel completo para nosso cadastro, e esses imóveis vão vir
 * para uma nova aba no site... para aprovação manual humana".
 *
 *   entra  { corretor_nome*, corretor_telefone*, link*,
 *            autorizacao_proprietario*: true, autorizacao_como*: "...",
 *            proprietario_nome, proprietario_telefone, titulo, descricao, tipo,
 *            finalidade, preco, preco_venda, preco_aluguel, valor_condominio, iptu,
 *            cidade, uf, bairro, endereco, numero, complemento, cep,
 *            condominio_nome, area_m2, area_total_m2, quartos, suites, banheiros,
 *            vagas, andar, mobilia, caracteristicas[], caracteristicas_condominio[],
 *            fotos[], observacoes }
 *   sai    { ok, id_cadastro, situacao: "pendente", ja_existia, fotos_recebidas, mensagem }
 *          ou { ok: false, codigo_erro, erro }
 *
 * NADA DAQUI VIRA IMÓVEL SOZINHO: o que chega fica em `privado.olx_bot_imovel`
 * (migração 260) até alguém aprovar na aba "Imóveis da OLX Bot" do site.
 *
 * SEM AUTORIZAÇÃO CLARA DO PROPRIETÁRIO O BANCO RECUSA (`codigo_erro:
 * "sem_autorizacao"`, HTTP 422). O prompt do bot manda não enviar; a recusa aqui
 * existe para o dia em que o modelo esquecer a instrução.
 *
 * ESTE WEBHOOK É DE OUTRO BOT, com outro token (BOT_CADASTRO_CHAVE): o token
 * da consulta não entra aqui, e este não consulta o catálogo. Ver
 * src/lib/botDeImoveis.ts.
 */
import { NextRequest } from 'next/server'
import { naydb } from '@/lib/nayDisparo'
import { erroDoBot, pedidoDoBot } from '@/lib/botDeImoveis'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const STATUS_DO_ERRO: Record<string, number> = { sem_autorizacao: 422, faltam_campos: 400, formato: 400, grande_demais: 413 }

export async function POST(req: NextRequest) {
  const pedido = await pedidoDoBot(req, 'cadastro')
  if (!pedido.ok) return pedido.resposta
  try {
    const r = await naydb().query('SELECT crm_olx_bot_receber($1::jsonb) AS r', [JSON.stringify(pedido.corpo)])
    const resposta = r.rows[0]?.r
    if (!resposta || typeof resposta !== 'object') return erroDoBot(502, 'O banco não respondeu.')
    return Response.json(resposta, { status: resposta.ok === false ? (STATUS_DO_ERRO[String(resposta.codigo_erro)] ?? 502) : 200 })
  } catch (err: any) {
    console.error('[imovel-cadastro]', err?.message || err)
    return erroDoBot(502, 'Não consegui receber agora. Tente de novo em alguns minutos.')
  }
}

export async function GET() {
  return erroDoBot(405, 'Use POST com o JSON do imóvel.')
}
