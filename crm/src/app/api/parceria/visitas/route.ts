/**
 * GET /api/parceria/visitas -- as visitas que a Nay agenda, com todas as
 * datas (29/09/2026). Pedro: "uma aba só de visitas agendadas que a ia
 * preenche sozinha quando confirma uma visita e a Rayssa pode acompanhar por
 * lá o andamento, e as datas de tudo".
 *
 * Vem da Nay (crm_visitas, migração 166): as abertas sempre; as fechadas na
 * janela pedida (?desde=AAAA-MM-DD&ate=AAAA-MM-DD; sem janela, todas). Cada
 * visita traz a conversa do corretor no CRM, quando existe, para abrir o
 * chat dele com um clique. As chaves de telefone ficam aqui no servidor.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { visitasDaNay } from '@/lib/nayLeitura'
import { conversaPorChave, conversasDaParceria } from '@/lib/conversasDaParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const DATA = /^\d{4}-\d{2}-\d{2}$/

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const desde = req.nextUrl.searchParams.get('desde')
    const ate = req.nextUrl.searchParams.get('ate')
    const [visitas, conversas] = await Promise.all([
      visitasDaNay(desde && DATA.test(desde) ? desde : null, ate && DATA.test(ate) ? ate : null),
      conversasDaParceria(auth.organizationId),
    ])
    const porChave = conversaPorChave(conversas)
    const saida = visitas.map(({ corretorChaves, ...v }) => {
      const conversa = corretorChaves.map((ch) => porChave.get(ch)).find(Boolean) || null
      return { ...v, conversa: conversa ? { leadId: conversa.id, titulo: conversa.titulo, avatar: conversa.avatar } : null }
    })
    return Response.json({ visitas: saida, em: Date.now() })
  } catch (err: any) {
    console.error('[parceria/visitas]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui ler as visitas da Nay.')
  }
}
