/**
 * POST /api/leads/[id]/pipeline — põe um lead que já existe no Kanban.
 *
 * É o "Adicionar ao pipeline" da aba Leads: o lead já está no CRM (veio da
 * Agenda, do site, de planilha) mas nunca entrou no quadro, ou entrou e saiu.
 * Coloca na PRIMEIRA etapa e nada mais — não manda mensagem, não mexe em
 * funil, não avisa o cliente de forma nenhuma.
 *
 * Endpoint próprio em vez de PATCH /api/leads/[id]:
 *   - a etapa inicial é decidida no servidor (a menor `rank`), então a tela não
 *     precisa saber qual é nem receber uma lista de etapas só pra isso;
 *   - o PATCH substitui `custom_attributes` inteiro, e aqui é preciso JUNTAR:
 *     gravar "whatsapp_responsavel" por cima apagaria a fonte do lead, a agenda
 *     montada e o quiz — justamente o que ninguém espera de um botão que só
 *     "adiciona ao pipeline".
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import { leads, leadStageHistory, pipelineStages } from '@/lib/schema'
import { and, asc, eq, isNull } from 'drizzle-orm'
import { mapLead } from '@/lib/mappers'
import { momentoPorChave } from '@/lib/momentos'

type Params = { params: Promise<{ id: string }> }

export async function POST(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json().catch(() => ({}))

    const [lead] = await db
      .select({ id: leads.id, stageId: leads.stageId, customAttributes: leads.customAttributes })
      .from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Lead não encontrado.')

    const [primeiraEtapa] = await db
      .select({ id: pipelineStages.id, name: pipelineStages.name })
      .from(pipelineStages)
      .where(and(eq(pipelineStages.organizationId, auth.organizationId), isNull(pipelineStages.deletedAt)))
      .orderBy(asc(pipelineStages.rank))
      .limit(1)
    if (!primeiraEtapa) return apiError(400, 'Nenhuma etapa configurada no pipeline.')

    const atributos = { ...((lead.customAttributes ?? {}) as Record<string, unknown>) }
    // Marcação de quem é o lead — não muda quem envia (ver src/lib/atendentes.ts).
    if (typeof body.whatsapp_responsavel === 'string' && body.whatsapp_responsavel.trim()) {
      atributos.whatsapp_responsavel = body.whatsapp_responsavel.trim()
    }
    // Momento da jornada, no mesmo campo que a Agenda usa (src/lib/momentos.ts).
    // Só aceita valor do vocabulário: campo livre aqui viraria lixo na etiqueta.
    if (momentoPorChave(body.momento)) atributos.phase = body.momento

    // Lead que já está numa etapa continua onde está: o botão é pra ENTRAR no
    // quadro, e puxar de volta pra primeira coluna alguém que já avançou seria
    // perder trabalho de quem move os cards.
    const entrouAgora = !lead.stageId
    await db
      .update(leads)
      .set({
        ...(entrouAgora ? { stageId: primeiraEtapa.id } : {}),
        customAttributes: atributos,
        updatedAt: new Date(),
      })
      .where(eq(leads.id, lead.id))

    if (entrouAgora) {
      await db.insert(leadStageHistory).values({
        organizationId: auth.organizationId,
        leadId: lead.id,
        fromStageId: null,
        toStageId: primeiraEtapa.id,
        movedByMemberId: auth.memberId || null,
        movedAt: new Date(),
      })
    }

    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id: lead.id })

    const [atualizado] = await db.select().from(leads).where(eq(leads.id, lead.id)).limit(1)
    return Response.json({
      data: mapLead(atualizado),
      entrou_agora: entrouAgora,
      etapa: primeiraEtapa.name,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
