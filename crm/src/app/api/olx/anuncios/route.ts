/**
 * GET /api/olx/anuncios?conta=proprietarios|corretores -- a aba Anúncios e a aba Informações do Chat OLX
 * (Pedro, 13/10/2026: "lá vai ter o chat, e os anúncios e todas as informações, em uma tab lá em cima como se
 * fosse um menu próprio dentro daquela aba").
 *
 * Devolve os anúncios da conta (o que a OLX lista + o que conhecemos pelas conversas), o estado da conta e o que
 * o nosso aplicativo usa (endereço de retorno e escopos). Só para quem está logado no CRM; nenhum segredo sai daqui.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { eq } from 'drizzle-orm'
import { db } from '@/lib/db'
import { profiles } from '@/lib/schema'
import { anunciosDaContaOlx, ehContaOlx, estadoDaContaOlx, gravarChaveOlx, informacoesDoAplicativoOlx, painelDosAnunciosOlx } from '@/lib/olxChat'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    const conta = req.nextUrl.searchParams.get('conta')
    if (!ehContaOlx(conta)) return apiError(400, 'Diga a conta: proprietarios ou corretores.')
    // o painel da publicação automática vem junto; se ele falhar, a lista da conta não pode cair por isso
    const [estado, lista, painel] = await Promise.all([
      estadoDaContaOlx(conta), anunciosDaContaOlx(conta),
      painelDosAnunciosOlx().catch((e) => { console.error('[olx/anuncios] painel', e?.message || e); return null }),
    ])
    return Response.json({ estado, ...lista, painel, aplicativo: informacoesDoAplicativoOlx(), em: Date.now() })
  } catch (err: any) {
    console.error('[olx/anuncios]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os anúncios da OLX.')
  }
}

/**
 * POST /api/olx/anuncios { chave, valor } -- muda uma chave da publicação automática (13/10/2026): `publicar`
 * (sim/nao), `conta_que_publica`, `teto`, `mostrar_telefone`, `telefone`. Quem valida é o banco
 * (`crm_olx_config_gravar`): ligar sem conta escolhida, por exemplo, ele recusa. O serviço nay-olx relê as chaves
 * a cada volta, então vale em segundos.
 */
export async function POST(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem está logado no CRM muda a publicação.')
    const corpo = await req.json().catch(() => ({}))
    const chave = String(corpo?.chave || '')
    const valor = String(corpo?.valor ?? '')
    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const r = await gravarChaveOlx(chave, valor, perfil?.nome?.trim() || 'alguém no CRM')
    if (!r.ok) return apiError(400, r.erro || 'Não consegui gravar.')
    return Response.json({ ok: true, painel: await painelDosAnunciosOlx() })
  } catch (err: any) {
    console.error('[olx/anuncios] gravar', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui gravar.')
  }
}
