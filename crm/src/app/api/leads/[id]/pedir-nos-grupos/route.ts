/**
 * PEDIR NOS GRUPOS (Pedro, 01/11/2026): "no card do lead da aba Leads, dentro do buscar, um campo Pedir nos grupos de
 * WhatsApp: o cara digita e quando clica enviar, é enviado do número Parceria nos grupos onde a Nay pede busca de imóveis".
 *
 * GET  /api/leads/{id}/pedir-nos-grupos   os grupos da busca (crm_grupos_da_busca, nayia 558: privado.busca_grupo ativos)
 * POST /api/leads/{id}/pedir-nos-grupos   { texto }: manda pelo número da Parceria (mandarNoGrupo, o mesmo da aba Grupos),
 *      um grupo de cada vez, e anota na busca do lead (crm_lead_pedido_nos_grupos): o pedido aparece no card, a etapa vai
 *      ao histórico e cada grupo ganha o relógio (a Nay espera o intervalo antes do próximo pedido dela ali).
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads, profiles } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import { mandarNoGrupo } from '@/lib/gruposParceria'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const ENTRE_GRUPOS_MS = 1500     // um grupo de cada vez, sem rajada no WhatsApp
const TEXTO_MAX = 2000

interface GrupoDaBusca { id: string; nome: string; locacao: boolean; venda: boolean }

async function gruposDaBusca(): Promise<GrupoDaBusca[]> {
  const r = await naydb().query('SELECT crm_grupos_da_busca() AS j')
  return r.rows[0]?.j || []
}

export async function GET(req: NextRequest) {
  try {
    await authenticateRequest(req)
    return Response.json({ grupos: await gruposDaBusca() })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui ler os grupos.')
  }
}

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM pede nos grupos.')
    const { id } = await params
    const corpo = await req.json().catch(() => null)
    const texto = String(corpo?.texto ?? '').trim().slice(0, TEXTO_MAX)
    if (texto.length < 5) return apiError(400, 'Escreva o pedido antes de enviar.')
    const [lead] = await db
      .select({ id: leads.id, phone: leads.phone })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    const [perfil] = await db.select({ nome: profiles.fullName }).from(profiles).where(eq(profiles.id, auth.userId)).limit(1)
    const grupos = await gruposDaBusca()
    if (!grupos.length) return apiError(409, 'Nenhum grupo de busca ativo.')

    const enviados: Array<{ grupo: string; nome: string; mid: string | null }> = []
    const falhas: Array<{ nome: string; erro: string }> = []
    for (const [n, g] of grupos.entries()) {
      if (n) await new Promise((ok) => setTimeout(ok, ENTRE_GRUPOS_MS))
      try {
        enviados.push({ grupo: g.id, nome: g.nome, mid: await mandarNoGrupo(auth.organizationId, g.id, texto) })
      } catch (e: any) {
        falhas.push({ nome: g.nome, erro: String(e?.message || e).slice(0, 160) })
      }
    }
    let anotado = false
    if (enviados.length) {
      const r = await naydb().query('SELECT crm_lead_pedido_nos_grupos($1, $2, $3::jsonb, $4) AS b',
        [lead.phone || '', texto, JSON.stringify(enviados), perfil?.nome?.trim() || 'alguém no CRM'])
      anotado = r.rows[0]?.b != null
    }
    return Response.json({ enviados: enviados.map((e) => e.nome), falhas, anotado },
                         { status: enviados.length ? 200 : 502 })
  } catch (err: any) {
    console.error('[pedir-nos-grupos]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui pedir nos grupos.')
  }
}
