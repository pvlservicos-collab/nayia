/**
 * Manda um imóvel para a conversa: o card e depois as fotos.
 *
 * Tel, 27/09/2026: "se alguem quiser buscar imoveis para la e ja enviar para
 * uma conversa ele pode so referenciar /codigo que ja vai as fotos e o card do
 * imovel para o contato".
 *
 * O CARD É O MESMO DOS GRUPOS. Vem de `nai_card_do_imovel` pela API do site --
 * não é um card novo escrito aqui. Dois cards diferentes para o mesmo imóvel
 * seria o pior dos dois mundos: o corretor recebendo uma coisa no grupo e outra
 * no privado.
 *
 * A COLAGEM DE 4 FOTOS NÃO VAI. Ela é só dos grupos desde 14/09 (pedido dele);
 * a API do site já a tira da lista. Aqui vão as fotos soltas.
 *
 * IMÓVEL DE PARCEIRO NÃO É BARRADO -- quem manda é uma pessoa, não a Nay, e a
 * parede existe para ela. Mas a resposta devolve `e_parceiro`, e a tela avisa
 * antes de mandar. A regra do Tel continua valendo onde ela vale: no gatilho da
 * caixa de saída da Nay.
 */
import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { integrations, leadActivities, leads, pipelineStages } from '@/lib/schema'
import { and, eq, isNull, ilike } from 'drizzle-orm'
import { getChannelAdapter } from '@/lib/channels/registry'
import { channels, events, publishEvent } from '@/lib/realtime'
import { cardDoImovel } from '@/lib/imoveisNay'
import { etapaEmAtendimentoDoMesmoPipeline } from '@/lib/etapaDaLinha'
import { recusaEscreverNaCaptacao } from '@/lib/captacaoSoRespondeServidor'

/** Quantas fotos no máximo. Mandar 18 fotos de uma vez é spam, não atendimento. */
const TETO_DE_FOTOS = 8

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const body = await req.json().catch(() => ({}))
    const codigo = Number(String(body?.codigo ?? '').replace(/\D/g, ''))
    if (!codigo) return apiError(400, 'Diga o código do imóvel.')
    const comFotos = body?.fotos !== false

    const [lead] = await db
      .select({
        id: leads.id, phone: leads.phone, title: leads.title, stageId: leads.stageId,
        isGroup: leads.isGroup, integrationId: leads.integrationId, externalId: leads.externalId,
      })
      .from(leads)
      .where(and(eq(leads.organizationId, auth.organizationId), eq(leads.id, id), isNull(leads.deletedAt)))
      .limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')
    if (!lead.phone && !lead.externalId) return apiError(400, 'Essa conversa não tem telefone.')
    // quem só responde na captação não começa conversa por lá (Pedro, 02/10)
    const recusa = await recusaEscreverNaCaptacao(auth.organizationId, auth.memberId, lead.id)
    if (recusa) return apiError(403, recusa)

    const imovel = await cardDoImovel(codigo)

    let tipo: string | null = null
    if (lead.integrationId) {
      const [integ] = await db.select({ type: integrations.type }).from(integrations)
        .where(and(eq(integrations.id, lead.integrationId), isNull(integrations.deletedAt))).limit(1)
      tipo = integ?.type ?? null
    }
    // Mesma escolha da resposta manual: sem linha conhecida, sai pela Z-API --
    // é o número que o corretor já conhece, e a oficial exige template.
    if (!tipo) tipo = 'whatsapp_zapi'
    const adapter = getChannelAdapter(tipo)
    const destino = lead.phone || lead.externalId || ''

    const enviados: { tipo: string; id: string | null; erro?: string }[] = []

    async function gravar(conteudo: string, extra: Record<string, any>) {
      const [a] = await db.insert(leadActivities).values({
        organizationId: auth.organizationId,
        leadId: lead.id,
        actorMemberId: auth.memberId || null,
        type: 'whatsapp',
        content: conteudo,
        metadata: {
          source: 'imoveis', direction: 'outbound', channel: tipo,
          imovel_codigo: codigo, ...extra,
        },
      }).returning({ id: leadActivities.id })
      return a.id
    }

    // 1) o card
    try {
      const r = await adapter.sendText(auth.organizationId, lead.integrationId, destino,
                                      imovel.card, lead.isGroup ?? false)
      const idAtividade = await gravar(imovel.card, {
        send_status: 'sent', ...(r.externalId ? { [adapter.metadataIdKey]: r.externalId } : {}),
      })
      enviados.push({ tipo: 'card', id: idAtividade })
    } catch (err: any) {
      // O card falhou: não manda foto nenhuma. Foto sem card é imóvel sem nome.
      await gravar(imovel.card, { send_status: 'failed', send_error: err?.message || 'erro ao enviar' })
      return apiError(502, `não consegui mandar o card do ${codigo}: ${err?.message || 'erro'}`)
    }

    // 2) as fotos, uma a uma
    if (comFotos) {
      for (const url of imovel.fotos.slice(0, TETO_DE_FOTOS)) {
        try {
          const r = await adapter.sendMedia(auth.organizationId, lead.integrationId, destino,
                                            'image', url, '', undefined, lead.isGroup ?? false)
          const idAtividade = await gravar('📷 Imagem', {
            media_type: 'image', media_url: url, send_status: 'sent',
            ...(r.externalId ? { [adapter.metadataIdKey]: r.externalId } : {}),
          })
          enviados.push({ tipo: 'foto', id: idAtividade })
        } catch (err: any) {
          // Uma foto que não vai não derruba as outras nem o card que já saiu.
          await gravar('📷 Imagem', {
            media_type: 'image', media_url: url,
            send_status: 'failed', send_error: err?.message || 'erro ao enviar',
          })
          enviados.push({ tipo: 'foto', id: null, erro: err?.message || 'erro' })
        }
      }
    }

    // "Em atendimento" do pipeline DELE e só para a frente (28/09, ver
    // `etapaEmAtendimentoDoMesmoPipeline`): antes era a primeira com esse nome
    // na organização, de qualquer funil.
    const emAtendimentoId = await etapaEmAtendimentoDoMesmoPipeline(auth.organizationId, lead.stageId)
    const emAtendimento = emAtendimentoId ? { id: emAtendimentoId } : null

    await db.update(leads).set({
      lastMessageContent: imovel.card.split('\n')[0] || `Imóvel ${codigo}`,
      lastMessageSenderType: 'human',
      lastActivityAt: new Date(),
      lastActivityType: 'whatsapp',
      lastActivityByMemberId: auth.memberId || null,
      isUnread: false,
      ...(emAtendimento ? { stageId: emAtendimento.id } : {}),
    }).where(eq(leads.id, lead.id))

    await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_CREATED, { id: enviados[0]?.id })
    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id: lead.id })

    const fotosQueFalharam = enviados.filter((e) => e.tipo === 'foto' && e.erro).length
    return Response.json({
      ok: true,
      codigo,
      card: imovel.card,
      fotos_enviadas: enviados.filter((e) => e.tipo === 'foto' && !e.erro).length,
      fotos_que_falharam: fotosQueFalharam,
      e_parceiro: imovel.e_parceiro,
      canal: tipo,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Não consegui mandar o imóvel.')
  }
}
