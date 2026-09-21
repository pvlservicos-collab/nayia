/**
 * Realtime Client — substitui Supabase Realtime (WebSockets)
 *
 * Usa Pusher como broker de eventos em tempo real.
 * O servidor publica eventos via pusher-js server SDK.
 * O cliente assina canais via pusher-js browser SDK.
 *
 * Mapeamento de canais (equivalência com Supabase):
 *   supabase.channel('public:lead_activities:X')  →  pusher.subscribe('lead-X')
 *   supabase.channel('leads_global:orgId')         →  pusher.subscribe('org-{orgId}')
 *   supabase.channel('leads:orgId:stageId')        →  pusher.subscribe('stage-{stageId}')
 */

// ── Servidor: publicar eventos ────────────────────────────────────────────────
import Pusher from 'pusher'

let _pusherServer: Pusher | null = null

export function getPusherServer(): Pusher {
  if (!_pusherServer) {
    if (
      !process.env.PUSHER_APP_ID ||
      !process.env.PUSHER_KEY ||
      !process.env.PUSHER_SECRET ||
      !process.env.PUSHER_CLUSTER
    ) {
      throw new Error('Variáveis de ambiente Pusher não configuradas (PUSHER_APP_ID, PUSHER_KEY, PUSHER_SECRET, PUSHER_CLUSTER)')
    }
    _pusherServer = new Pusher({
      appId: process.env.PUSHER_APP_ID,
      key: process.env.PUSHER_KEY,
      secret: process.env.PUSHER_SECRET,
      cluster: process.env.PUSHER_CLUSTER,
      useTLS: true,
    })
  }
  return _pusherServer
}

/**
 * Publica um evento em um canal Pusher.
 * Chame isto nas API routes após qualquer INSERT/UPDATE/DELETE relevante.
 *
 * Exemplo:
 *   await publishEvent(`lead-${leadId}`, 'activity.created', { id: activity.id })
 *   await publishEvent(`org-${orgId}`, 'lead.updated', { id: lead.id })
 */
export async function publishEvent(
  channel: string,
  event: string,
  data: Record<string, any>
): Promise<void> {
  try {
    const pusher = getPusherServer()
    await pusher.trigger(channel, event, data)
  } catch (err) {
    // Não bloquear a resposta da API se o Pusher falhar
    console.error('[Pusher] Falha ao publicar evento:', err)
  }
}

// ── Nomes de canais (convenção centralizada) ──────────────────────────────────
export const channels = {
  leadActivities: (leadId: string) => `lead-${leadId}`,
  orgLeads: (orgId: string) => `org-${orgId}`,
  stageLeads: (stageId: string) => `stage-${stageId}`,
  orgMembers: (orgId: string) => `members-${orgId}`,
}

// ── Eventos disponíveis ───────────────────────────────────────────────────────
export const events = {
  ACTIVITY_CREATED: 'activity.created',
  ACTIVITY_UPDATED: 'activity.updated',
  LEAD_CREATED: 'lead.created',
  /**
   * O lead respondeu uma mensagem que o SISTEMA mandou (funil/IA).
   *
   * Separado de LEAD_UPDATED porque é o evento mais importante do dia pra quem
   * atende: alguém que a automação abordou acabou de responder, e a janela pra
   * entrar na conversa é agora. É por isso que ele toca um som diferente do
   * lead novo (ver SomNovoLead).
   */
  LEAD_REPLIED_AUTOMATION: 'lead.replied_automation',
  LEAD_UPDATED: 'lead.updated',
  LEAD_DELETED: 'lead.deleted',
  MEMBER_UPDATED: 'member.updated',
  PIN_CREATED: 'pin.created',
  PIN_DELETED: 'pin.deleted',
  /**
   * Instância de WhatsApp (Z-API) caiu — dispara o aviso fixo em cima do chat.
   * Fica ligado até um humano fechar (ver PUT /api/integrations/zapi ação
   * "fechar_aviso"), mesmo que a instância já tenha reconectado sozinha —
   * ninguém detectou a queda de hoje até um lead reclamar, então reconectar
   * sozinho não é motivo pra sumir o aviso sem alguém confirmar que viu.
   */
  INTEGRATION_DISCONNECT_ALERT: 'integration.disconnect_alert',
}
