/**
 * GET /api/parceria/visitas/opcoes -- quem dá para escolher como corretor ao
 * agendar uma visita à mão (Pedro, 01/10/2026): as conversas da Parceria que a
 * Nay reconhece como corretor (e não são da equipe). Só o nome e a conversa: o
 * telefone fica no servidor, a tela manda o id da conversa de volta.
 * Quem não está na lista entra pelo número, digitado no próprio formulário.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { marcasDaNay } from '@/lib/nayLeitura'
import { conversasDaParceria } from '@/lib/conversasDaParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const conversas = await conversasDaParceria(auth.organizationId)
    const marcas = await marcasDaNay(conversas.map((c) => c.telefone || '').filter(Boolean))
    const corretores = conversas
      .filter((c) => { const m = c.telefone ? marcas.get(c.telefone) : undefined; return m?.corretor && !m.equipe })
      .map((c) => {
        const m = marcas.get(c.telefone || '')
        return { leadId: c.id, nome: (m?.corretorNome || c.titulo || '').trim() || 'Sem nome', fim: (c.telefone || '').slice(-4) }
      })
      .sort((a, b) => a.nome.localeCompare(b.nome, 'pt-BR'))
    return Response.json({ corretores })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os corretores.')
  }
}
