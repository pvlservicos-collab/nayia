/**
 * GET /api/olx/abordagens -- o que a aba "Chat OLX" mostra (Pedro, 08/10/2026).
 *
 * Cada anúncio que o bot da OLX consultou (webhook /api/public/imovel-consulta,
 * migração 309): a decisão (abordar ou fechar), o motivo e a mensagem que foi
 * entregue para ele mandar ao anunciante. Vem do banco da Nay pela função
 * crm_olx_abordagens (313): a tabela fica no schema `privado` e o CRM só
 * executa função lá.
 *
 * Só leitura, e só para quem está logado no CRM. O que o anunciante responde
 * na OLX não chega aqui: o bot ainda não manda as respostas de volta.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { naydb } from '@/lib/nayDisparo'
import type { AbordagemOlx } from '@/lib/olxAbordagens'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const iso = (v: unknown) => (v ? new Date(v as string).toISOString() : null)

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const r = await naydb().query('SELECT * FROM crm_olx_abordagens($1::int)', [500])
    const abordagens: AbordagemOlx[] = r.rows.map((l: any) => ({
      id: Number(l.id),
      link: String(l.link || ''),
      titulo: l.titulo || null,
      tipo: l.tipo || null,
      finalidade: l.finalidade || null,
      preco: l.preco == null ? null : Number(l.preco),
      bairro: l.bairro || null,
      condominio: l.condominio || null,
      anunciante: l.anunciante || null,
      telefone: l.telefone || null,
      acao: l.acao === 'abordar' ? 'abordar' : 'fechar',
      motivo: String(l.motivo || ''),
      codigo: l.codigo == null ? null : Number(l.codigo),
      mensagem: l.mensagem || null,
      entregueEm: iso(l.entregue_em),
      recebidoEm: iso(l.recebido_em) || new Date().toISOString(),
      pedidos: Number(l.pedidos || 1),
    }))
    return Response.json({ abordagens, em: Date.now() })
  } catch (err: any) {
    console.error('[olx/abordagens]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as abordagens da OLX.')
  }
}
