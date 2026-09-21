import webpush from 'web-push'
import { eq, and, isNull } from 'drizzle-orm'
import { db } from './db'
import { pushSubscriptions, leads, organizationMembers, notifications } from './schema'

let vapidConfigured = false
function ensureVapid() {
  if (vapidConfigured) return
  webpush.setVapidDetails(
    process.env.VAPID_SUBJECT!,
    process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!,
    process.env.VAPID_PRIVATE_KEY!
  )
  vapidConfigured = true
}

// Mesmo rótulo usado no lado do envio (useLeadActivities.ts) — mantém a prévia da
// notificação consistente com o que já aparece na timeline do CRM.
const MEDIA_LABELS: Record<string, string> = {
  image: '📷 Imagem',
  video: '🎥 Vídeo',
  audio: '🎵 Áudio',
  document: '📄 Documento',
  sticker: '✨ Figurinha',
}

interface PushPayload {
  title: string
  body: string
  url: string
  tag?: string
}

/** Manda push pra todos os aparelhos inscritos de um membro. Nunca lança — inscrição
 * morta (404/410, navegador revogou) é limpa em vez de reportada como erro. */
export async function sendPushToMember(organizationId: string, memberId: string, payload: PushPayload) {
  ensureVapid()
  const subs = await db
    .select()
    .from(pushSubscriptions)
    .where(and(eq(pushSubscriptions.organizationId, organizationId), eq(pushSubscriptions.memberId, memberId)))

  await Promise.all(
    subs.map(async (sub) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          JSON.stringify(payload)
        )
      } catch (err: any) {
        if (err?.statusCode === 404 || err?.statusCode === 410) {
          await db.delete(pushSubscriptions).where(eq(pushSubscriptions.id, sub.id)).catch(() => {})
        } else {
          console.error('[push] sendNotification falhou', sub.id, err?.statusCode || err)
        }
      }
    })
  )
}

/**
 * Notifica sobre uma mensagem inbound nova — todo mundo da organização que tem push
 * ativado, dono do lead ou não (time pequeno, ninguém deve perder mensagem por não
 * ser o "responsável" formal do lead). Também grava em `notifications` (mesma tabela
 * do sino do app), reaproveitando a convenção de deep-link `linkUrl` já usada em
 * outros pontos do app. Nunca lança — chamável com segurança de dentro de um webhook
 * sem risco de quebrar a resposta.
 */
export async function notifyInboundMessage(
  organizationId: string,
  leadId: string,
  activity: { text?: string | null; mediaType?: string | null }
) {
  try {
    const [lead] = await db
      .select({ title: leads.title })
      .from(leads)
      .where(eq(leads.id, leadId))
      .limit(1)
    if (!lead) return

    const title = lead.title || 'Novo contato'
    const body = activity.text?.trim() || (activity.mediaType && MEDIA_LABELS[activity.mediaType]) || 'Nova mensagem'
    const linkUrl = `/chat?leadId=${leadId}`

    const rows = await db
      .selectDistinct({ memberId: pushSubscriptions.memberId })
      .from(pushSubscriptions)
      .innerJoin(organizationMembers, eq(organizationMembers.id, pushSubscriptions.memberId))
      .where(
        and(
          eq(pushSubscriptions.organizationId, organizationId),
          eq(organizationMembers.status, 'active'),
          isNull(organizationMembers.deletedAt)
        )
      )
    const targetMemberIds = rows.map((r) => r.memberId)
    if (targetMemberIds.length === 0) return

    await Promise.all(
      targetMemberIds.map((memberId) => sendPushToMember(organizationId, memberId, { title, body, url: linkUrl, tag: `lead-${leadId}` }))
    )

    await db.insert(notifications).values(
      targetMemberIds.map((memberId) => ({
        organizationId,
        recipientMemberId: memberId,
        type: 'inbound_message',
        title,
        body,
        metadata: { linkUrl, leadId },
      }))
    )
  } catch (err) {
    console.error('[push] notifyInboundMessage falhou', err)
  }
}
