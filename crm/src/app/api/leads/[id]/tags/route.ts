import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations, leadStageHistory, leadTags, leads, pipelineStages, pipelines, tags } from '@/lib/schema'
import { eq, and, ilike, isNull, sql } from 'drizzle-orm'
import { channels, events, publishEvent } from '@/lib/realtime'
import { pipelineDaLinha } from '@/lib/etapaDaLinha'

/**
 * A ETIQUETA É O CASO NO PIPELINE (Tel, 26/09/2026: "e ai isso vai virar cada um
 * um caso la no pipeline tambem, e vai ter essa divisão no pipeline cada pipeline
 * para cada zap").
 *
 * As etiquetas do chat e as etapas do pipeline têm os MESMOS nomes, de propósito:
 *
 *   Parceria  ->  Agendou visita · Follow up · Fechou contrato
 *   Captação  ->  Recebeu mensagem · Em atendimento · Atualizou cadastro do seu
 *                 imóvel · Sugeriu outro imóvel (28/09; as abas Oficial e
 *                 Captação usam este funil)
 *
 * Então marcar "Agendou visita" na conversa move o card para a coluna "Agendou
 * visita" do pipeline daquela linha. Uma coisa só, vista de dois lugares --
 * senão quem atende teria de fazer o mesmo trabalho duas vezes e o Kanban
 * envelheceria calado.
 *
 * POR QUE NÃO JOGAR TODA CONVERSA NO FUNIL. O `zapiInbound` não põe conversa no
 * funil de propósito: quem escreve no número pode ser qualquer um (já houve uma
 * comunidade de figurinhas virando card no meio dos leads). A conversa entra no
 * pipeline quando alguém a marca -- decisão de gente, que é como um caso deve
 * nascer.
 */
async function moverParaAEtapaDaEtiqueta(
  organizationId: string, leadId: string, tagId: string, quem?: string | null,
): Promise<string | null> {
  const [etiqueta] = await db.select({ name: tags.name }).from(tags)
    .where(and(eq(tags.id, tagId), eq(tags.organizationId, organizationId))).limit(1)
  if (!etiqueta?.name) return null

  // A linha da conversa decide QUAL pipeline. Sem linha, fica como está: mover
  // para o pipeline errado é pior que não mover.
  const [lead] = await db.select({ integrationId: leads.integrationId, stageId: leads.stageId }).from(leads)
    .where(and(eq(leads.id, leadId), eq(leads.organizationId, organizationId))).limit(1)
  if (!lead?.integrationId) return null

  const [integ] = await db.select({ type: integrations.type }).from(integrations)
    .where(and(eq(integrations.id, lead.integrationId), isNull(integrations.deletedAt))).limit(1)
  // um funil por número (29/09): o da linha da conversa
  const nomeDoPipeline = pipelineDaLinha(integ?.type)
  if (!nomeDoPipeline) return null

  const [etapa] = await db.select({ id: pipelineStages.id })
    .from(pipelineStages)
    .innerJoin(pipelines, eq(pipelines.id, pipelineStages.pipelineId))
    .where(and(
      eq(pipelineStages.organizationId, organizationId),
      isNull(pipelineStages.deletedAt),
      isNull(pipelines.deletedAt),
      ilike(pipelines.name, nomeDoPipeline),
      ilike(pipelineStages.name, etiqueta.name),
    ))
    .limit(1)
  if (!etapa) return null

  if (lead.stageId === etapa.id) return etapa.id
  await db.update(leads).set({ stageId: etapa.id, updatedAt: new Date() })
    .where(and(eq(leads.id, leadId), eq(leads.organizationId, organizationId)))
  // o movimento fica no histórico, como nas outras rotas que movem card
  await db.insert(leadStageHistory).values({
    organizationId, leadId, fromStageId: lead.stageId ?? null, toStageId: etapa.id, movedByMemberId: quem ?? null, movedAt: new Date(),
  })
  return etapa.id
}

type Params = { params: Promise<{ id: string }> }

export async function GET(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const data = await db.select({ tagId: leadTags.tagId, tag: tags })
      .from(leadTags)
      .leftJoin(tags, eq(tags.id, leadTags.tagId))
      .where(and(eq(leadTags.leadId, id), eq(leadTags.organizationId, auth.organizationId)))
    return Response.json({ data: data.map(d => ({ tag_id: d.tagId, tag: d.tag })) })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function POST(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    if (!body.tag_id) return apiError(400, 'tag_id é obrigatório.')
    await db.insert(leadTags).values({
      leadId: id,
      tagId: body.tag_id,
      organizationId: auth.organizationId,
    }).onConflictDoNothing()

    /* WHATSAPP LEADS: A ETIQUETA DA ETAPA É A ABA (Pedro, 20/10/2026: "as etapas não viraram as tags como eu pedi").
       Visita, Proprietários, Fechamento e Finalizados são as abas da linha; pôr uma delas à mão muda a conversa de aba,
       então as outras três saem desta conversa (só delas; as outras etiquetas e o lead ficam). O espelho do funis.ts
       não desfaz: ele só age quando a etapa da Nay muda. */
    let trocouAEtapa = false
    try {
      const r = await db.execute(sql`
        WITH etapa AS (
          SELECT t.id FROM tags t
           WHERE t.organization_id = ${auth.organizationId} AND t.id = ${body.tag_id}
             AND coalesce(t.nome_original, t.name) IN ('Visita', 'Proprietários', 'Fechamento', 'Finalizados')),
        lead AS (
          SELECT l.id FROM leads l JOIN integrations i ON i.id = l.integration_id
           WHERE l.id = ${id} AND l.organization_id = ${auth.organizationId} AND i.type = 'whatsapp_zapi_captacao'
             AND EXISTS (SELECT 1 FROM etapa))
        DELETE FROM lead_tags lt USING tags t
         WHERE lt.lead_id IN (SELECT id FROM lead) AND lt.tag_id = t.id AND t.organization_id = ${auth.organizationId}
           AND lt.tag_id <> ${body.tag_id}
           AND coalesce(t.nome_original, t.name) IN ('Visita', 'Proprietários', 'Fechamento', 'Finalizados')
        RETURNING lt.tag_id`)
      trocouAEtapa = r.rows.length > 0
    } catch (err) {
      console.error('[tags] etiqueta gravada, mas não tirei as outras etapas do Leads:', err)
    }
    if (trocouAEtapa) await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id })

    // A etiqueta move o card no pipeline da linha (ver o comentário acima).
    let etapaId: string | null = null
    try {
      etapaId = await moverParaAEtapaDaEtiqueta(auth.organizationId, id, body.tag_id, auth.memberId)
      if (etapaId) {
        await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id })
      }
    } catch (err) {
      // Marcar a conversa é o pedido; mover o card é consequência. Se o mover
      // falhar, a etiqueta continua valendo em vez de a ação inteira morrer.
      console.error('[tags] etiqueta gravada, mas não movi o card:', err)
    }

    return Response.json({ success: true, stage_id: etapaId }, { status: 201 })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}

export async function DELETE(req: NextRequest, { params }: Params) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json()
    if (!body.tag_id) return apiError(400, 'tag_id é obrigatório.')
    await db.delete(leadTags).where(
      and(eq(leadTags.leadId, id), eq(leadTags.tagId, body.tag_id), eq(leadTags.organizationId, auth.organizationId))
    )
    return Response.json({ success: true })
  } catch (err: any) { return apiError(err.status || 500, err.message || 'Erro interno.') }
}
