/**
 * POST /api/public/olx-lead/<conta>/<segredo> -- A OLX AVISA UM CONTATO NUM ANÚNCIO (Pedro, 14/10/2026: "um script de
 * métricas ... com os dados que a OLX compartilha").
 *
 * É o endereço configurado em /autoservice/v1/lead para a conta. Cada contato feito num anúncio dela -- chat, clique no
 * WhatsApp, ver o telefone, simulação de financiamento -- chega aqui como um POST:
 *   { source, adId, listId, linkAd, name, email, phone, message, createdAt, externalId, buyerHistory? }
 * Fica em `privado.olx_lead` (migração 369) e vira as colunas de contatos da tabela de métricas.
 *
 * Como o chat, a OLX não assina a chamada: quem prova é o segredo do caminho (o mesmo da conta). O repetido (mesmo
 * externalId) não duplica. Respondemos 200 quando gravou, 401 com o segredo errado, 500 se o banco falhou.
 */
import { NextRequest } from 'next/server'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function POST(req: NextRequest, { params }: { params: Promise<{ conta: string; segredo: string }> }) {
  const { conta, segredo } = await params
  const texto = await req.text().catch(() => '')
  let corpo: unknown
  try { corpo = texto ? JSON.parse(texto) : null } catch {
    return Response.json({ ok: false, erro: 'O corpo não é um JSON válido.' }, { status: 400 })
  }
  try {
    const r = await naydb().query('SELECT crm_olx_lead_receber($1, $2, $3::jsonb, $4) AS r',
      [conta, segredo, JSON.stringify(corpo ?? null), req.headers.get('authorization')])
    const res = r.rows[0]?.r || {}
    if (res.ok) return Response.json({ ok: true, novo: !!res.novo })
    if (res.codigo_erro === 'nao_autorizado') return Response.json({ ok: false, erro: 'Não autorizado.' }, { status: 401 })
    if (res.codigo_erro === 'formato') return Response.json({ ok: false, erro: 'Lead fora do formato.' }, { status: 400 })
    console.error('[olx-lead] o banco recusou', conta, res.codigo_erro, res.erro)
    return Response.json({ ok: false, erro: 'Não consegui gravar agora.' }, { status: 500 })
  } catch (err: any) {
    console.error('[olx-lead]', conta, err?.message || err)
    return Response.json({ ok: false, erro: 'Não consegui gravar agora.' }, { status: 500 })
  }
}

export async function GET() {
  return Response.json({ ok: true, mensagem: 'Endereço de leads da OLX da Imob Easy. Use POST.' })
}
