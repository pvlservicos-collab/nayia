import { NextRequest } from 'next/server'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { publishEvent, channels, events } from '@/lib/realtime'
import { leads, leadActivities } from '@/lib/schema'
import { eq, and, isNull } from 'drizzle-orm'
import { getChannelAdapter } from '@/lib/channels/registry'
import { isOrgAdmin } from '@/lib/admin-auth'

/**
 * DELETE /api/leads/[id]/messages/[activityId]
 * Apaga uma única mensagem enviada pela equipe (ex: vendedor mandou por engano).
 * Sempre some do CRM. Body opcional `{ deleteForEveryone: boolean }` (default true)
 * escolhe se também tenta apagar "para todos" no WhatsApp do cliente — só é possível
 * de verdade quando o canal por onde ela foi enviada suporta revogar a mensagem (hoje
 * só a Evolution — WhatsApp Nº 2). A Cloud API oficial da Meta e o Instagram Direct não
 * expõem essa operação pra mensagens de negócio já enviadas — nesses canais só existe
 * "apagar pra mim", e isso é sinalizado na resposta (`channel_supports_delete`) pro
 * front nem oferecer a opção de "para todos".
 */
export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string; activityId: string }> }
) {
  try {
    const auth = await authenticateRequest(req)
    const { id, activityId } = await params

    // Corpo é opcional pra manter compatibilidade com um DELETE sem body — nesse caso
    // preserva o comportamento antigo (sempre tenta "para todos" quando o canal suporta).
    // `deleteForEveryone: false` é a escolha explícita de "apagar só pra mim".
    const body = await req.json().catch(() => ({}))
    const wantsEveryone = body?.deleteForEveryone !== false

    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)

    // activityId sempre precisa ser um uuid de verdade (coluna é uuid) — se o front
    // mandar o id otimista local (ex: "temp-1783984181626", de uma mensagem que ainda
    // nem terminou de enviar), a query abaixo quebraria com um erro cru do Postgres
    // ("invalid input syntax for type uuid") em vez de uma mensagem de erro decente.
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(activityId)) {
      return apiError(400, 'Essa mensagem ainda está sendo enviada — aguarde ela terminar de enviar antes de apagar.')
    }

    const [lead] = await db
      .select({ id: leads.id, phone: leads.phone, isGroup: leads.isGroup, integrationId: leads.integrationId })
      .from(leads)
      .where(
        and(
          eq(leads.organizationId, auth.organizationId),
          isNull(leads.deletedAt),
          isUuid ? eq(leads.id, id) : eq(leads.phone, decodeURIComponent(id))
        )
      )
      .limit(1)

    if (!lead) return apiError(404, 'Lead não encontrado.')

    const [activity] = await db
      .select()
      .from(leadActivities)
      .where(
        and(
          eq(leadActivities.id, activityId),
          eq(leadActivities.organizationId, auth.organizationId),
          eq(leadActivities.leadId, lead.id)
        )
      )
      .limit(1)

    if (!activity) return apiError(404, 'Mensagem não encontrada.')

    const metadata = (activity.metadata as Record<string, any>) || {}

    // Mensagens recebidas do cliente nunca são apagáveis por aqui (não é um "envio da
    // equipe" pra desfazer). Mensagens enviadas por automação externa (source !== 'human',
    // sem actor_member_id) só um admin apaga — ver isOwner abaixo.
    if (activity.type !== 'whatsapp' || metadata.direction !== 'outbound') {
      return apiError(400, 'Só é possível apagar mensagens de WhatsApp enviadas (não é possível apagar mensagens recebidas do cliente).')
    }
    if (metadata.deleted) return apiError(400, 'Essa mensagem já foi apagada.')

    const isOwner = !!auth.memberId && activity.actorMemberId === auth.memberId
    if (!isOwner && !(await isOrgAdmin(auth))) {
      return apiError(403, 'Você só pode apagar mensagens que você mesmo enviou (ou pedir a um administrador).')
    }

    // Prioriza o canal que a mensagem realmente usou no envio (gravado em metadata.channel)
    // sobre a integração atual do lead, que pode ter mudado desde então.
    const adapter = getChannelAdapter(metadata.channel)
    const externalId = metadata[adapter.metadataIdKey]

    let deletedForEveryone = false
    let deleteError: string | null = null
    const channelSupportsDelete = typeof adapter.deleteMessage === 'function'

    // Só a Evolution implementa deleteMessage hoje, e seu destinatário é o telefone —
    // por isso o telefone só é exigido quando o canal realmente suporta apagar pra todos
    // (leads do Instagram não têm telefone e não devem ser bloqueados de apagar do CRM).
    // Se o usuário escolheu explicitamente "apagar só pra mim", nem tenta revogar no
    // canal — mesmo que ele suporte.
    if (!wantsEveryone) {
      // Escolha explícita do usuário — não é erro, não tenta apagar no canal.
    } else if (adapter.deleteMessage && !lead.phone) {
      deleteError = 'Lead sem telefone — não é possível apagar no WhatsApp do cliente.'
    } else if (adapter.deleteMessage) {
      if (externalId) {
        try {
          await adapter.deleteMessage(auth.organizationId, lead.integrationId, lead.phone!, externalId, lead.isGroup ?? false)
          deletedForEveryone = true
        } catch (err: any) {
          deleteError = err.message || 'Falha ao apagar no WhatsApp do cliente.'
        }
      } else {
        deleteError = 'Mensagem sem id externo salvo — não é possível apagar no WhatsApp do cliente.'
      }
    }

    await db
      .update(leadActivities)
      .set({
        metadata: {
          ...metadata,
          deleted: true,
          deleted_by_member_id: auth.memberId,
          deleted_at: new Date().toISOString(),
          deleted_for_everyone: deletedForEveryone,
          // Registra a intenção de quem apagou, separado do resultado — distingue "não
          // tentou porque o usuário escolheu só pra mim" de "tentou e falhou".
          delete_scope: wantsEveryone ? 'everyone' : 'me',
        },
        updatedAt: new Date(),
      })
      .where(eq(leadActivities.id, activityId))

    await publishEvent(channels.leadActivities(lead.id), events.ACTIVITY_UPDATED, { id: activityId })

    return Response.json({
      success: true,
      deleted_for_everyone: deletedForEveryone,
      channel_supports_delete: channelSupportsDelete,
      delete_error: deleteError,
    })
  } catch (err: any) {
    return apiError(err.status || 500, err.message || 'Erro interno.')
  }
}
