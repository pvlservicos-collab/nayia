/**
 * GET /api/leads/{id}/atendimento -- o histórico de atendimento do card
 * (Pedro, 05/10/2026; ver src/lib/historicoDeAtendimento.ts): quem do nosso
 * lado falou nesta conversa, em tags. Devolve { tags: TagDeAtendimento[] },
 * da mais antiga para a mais nova.
 *
 * BARATO DE PROPÓSITO ("que não gaste muito dos nossos recursos"): uma leitura
 * das últimas 300 mensagens nossas da conversa (índice lead_id + created_at,
 * só quatro colunas, sem o texto) e UMA chamada ao banco da Nay com os ids dos
 * ecos (crm_quem_mandou, 290: ~4 ms para 300 ids). Nada é gravado: a fila sai
 * das próprias mensagens, então vale para conversa antiga também.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import { montarAtendentes } from '@/lib/atendentes'
import {
  AUTOR_DESCONHECIDO, COR_DO_CELULAR, autorDoEco, fotosDoEnvioAutomatico, juntarEmTags, type AutorDoEnvio,
} from '@/lib/historicoDeAtendimento'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const ULTIMAS = 300

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const [lead] = await db
      .select({ id: leads.id })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')

    const r = await db.execute(sql`
      SELECT a.created_at AS em, a.actor_member_id::text AS membro, p.full_name AS nome,
             a.metadata->>'zapi_message_id' AS zapi, a.metadata->>'media_type' AS midia
        FROM lead_activities a
        LEFT JOIN organization_members m ON m.id = a.actor_member_id
        LEFT JOIN profiles p ON p.id = m.user_id
       WHERE a.lead_id = ${id} AND a.type = 'whatsapp' AND a.metadata->>'direction' = 'outbound'
         AND coalesce(a.metadata->>'is_reaction', 'false') <> 'true'
       ORDER BY a.created_at DESC
       LIMIT ${ULTIMAS}`)
    const linhas = (r.rows as Array<{ em: string | Date; membro: string | null; nome: string | null; zapi: string | null; midia: string | null }>).reverse()

    // os ecos (sem conta do CRM): o banco da Nay diz de quem são, pelo id
    const ecos = linhas.filter((l) => !l.membro && l.zapi).map((l) => l.zapi as string)
    const origem = new Map<string, string>()
    if (ecos.length) {
      try {
        const q = await naydb().query('SELECT message_id, origem FROM crm_quem_mandou($1::text[])', [ecos])
        for (const x of q.rows) origem.set(String(x.message_id), String(x.origem))
      } catch (err: any) {
        // sem a Nay a fila ainda mostra o que saiu pelo CRM; o resto fica "?"
        console.error('[leads/atendimento] não li a Nay', err?.message || err)
      }
    }

    const contas = new Map<string, AutorDoEnvio>()
    const autorDaConta = (membro: string, nome: string | null): AutorDoEnvio => {
      let a = contas.get(membro)
      if (!a) {
        // a cor e o nome de chamada do time (Tel, Rayssa...); quem não é do time sai com o primeiro nome
        const [doTime] = montarAtendentes([{ id: membro, profiles: { full_name: nome } }])
        a = doTime
          ? { tipo: 'conta', nome: doTime.nome, cor: doTime.cor }
          : { tipo: 'conta', nome: (nome || 'CRM').trim().split(/\s+/)[0] || 'CRM', cor: COR_DO_CELULAR }
        contas.set(membro, a)
      }
      return a
    }

    const tags = juntarEmTags(fotosDoEnvioAutomatico(linhas.map((l) => ({
      em: new Date(l.em).toISOString(),
      autor: l.membro ? autorDaConta(l.membro, l.nome) : l.zapi ? autorDoEco(origem.get(l.zapi)) : AUTOR_DESCONHECIDO,
      midia: l.midia === 'image' || l.midia === 'video',
    }))))
    return Response.json({ tags })
  } catch (err: any) {
    console.error('[leads/atendimento]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui montar o histórico de atendimento.')
  }
}
