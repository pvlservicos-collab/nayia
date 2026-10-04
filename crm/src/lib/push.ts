import webpush from 'web-push'
import { eq, and, isNull, sql } from 'drizzle-orm'
import { db } from './db'
import { pushSubscriptions, leads, organizationMembers, notifications, integrations } from './schema'
import { donosDaCaptacao, marcasDaNay } from './nayLeitura'
import { LINHA_DA_CAPTACAO, LINHA_DA_PARCERIA, nuncaAvisa, precisaDeGente } from './precisaDeGente'
import type { MarcaDaNay } from './tiposNay'

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

/*
 * O QUE A NAY SABE DA PESSOA, para decidir o aviso (ver precisaDeGente.ts).
 *
 * A marca de UMA pessoa custa ~350 ms no banco da Nay (medido em 04/10), e a
 * mesma pessoa manda várias mensagens seguidas: a resposta vale 30 s. `null` =
 * não consegui ler (aí o aviso sai, na dúvida); `undefined` = a Nay não conhece.
 */
const VALE_MS = 30_000
const marcasGuardadas = new Map<string, { em: number; marca: MarcaDaNay | undefined }>()
let donosGuardados: { em: number; porFim: Map<string, string[]>; porLid: Map<string, string[]> } | null = null

async function marcaDaPessoa(telefone: string | null): Promise<MarcaDaNay | null | undefined> {
  if (!telefone) return undefined
  const guardada = marcasGuardadas.get(telefone)
  if (guardada && Date.now() - guardada.em < VALE_MS) return guardada.marca
  try {
    const marca = (await marcasDaNay([telefone])).get(telefone)
    if (marcasGuardadas.size > 500) marcasGuardadas.clear()
    marcasGuardadas.set(telefone, { em: Date.now(), marca })
    return marca
  } catch (err: any) {
    console.error('[push] não li a marca da Nay', err?.message || err)
    return null
  }
}

/** As abas do dono na campanha, pelo telefone (8 últimos dígitos) ou pelo @lid -- como em /api/captacao/donos. */
async function abasDoDonoDaCaptacao(telefone: string | null, lid: string | null): Promise<string[] | null | undefined> {
  try {
    if (!donosGuardados || Date.now() - donosGuardados.em >= VALE_MS) {
      const porFim = new Map<string, string[]>()
      const porLid = new Map<string, string[]>()
      for (const d of await donosDaCaptacao()) {
        if (d.telefone.length >= 8) porFim.set(d.telefone.slice(-8), d.abas)
        if (d.lid) porLid.set(d.lid, d.abas)
      }
      donosGuardados = { em: Date.now(), porFim, porLid }
    }
    const fim8 = String(telefone || '').replace(/\D/g, '').slice(-8)
    return (fim8.length === 8 ? donosGuardados.porFim.get(fim8) : undefined) ?? (lid ? donosGuardados.porLid.get(lid) : undefined)
  } catch (err: any) {
    console.error('[push] não li os donos da captação', err?.message || err)
    return null
  }
}

/*
 * UM AVISO POR RAJADA, E NENHUM ENQUANTO ALGUÉM ESTÁ RESPONDENDO (04/10).
 *
 * Medido nas mensagens de 02 a 04/10 com o filtro de cima: avisar cada mensagem
 * que precisa de gente daria ~400 avisos num dia cheio, 98 numa hora -- a pessoa
 * manda cinco mensagens seguidas e quem atende já está na conversa. Com as duas
 * regras abaixo ficam ~80 no dia e 12 na pior hora:
 *   - nós respondemos essa conversa há menos de 5 min: alguém está nela, não avisa;
 *   - já avisei essa conversa depois da nossa última resposta, há menos de 10 min:
 *     é a mesma rajada, não avisa de novo.
 * O último aviso de cada conversa mora na memória: se o CRM reinicia, o pior que
 * acontece é um aviso a mais.
 */
const RESPONDENDO_MS = 5 * 60_000
const RAJADA_MS = 10 * 60_000
const ultimoAviso = new Map<string, number>()

/** Vem ANTES de perguntar à Nay: é uma leitura de 5 ms no banco do CRM, contra 350 ms no dela. */
async function jaEstaSendoVista(leadId: string): Promise<boolean> {
  const r = await db.execute(sql`
    SELECT max(created_at) AS em FROM lead_activities
     WHERE lead_id = ${leadId} AND type = 'whatsapp' AND metadata->>'direction' = 'outbound'`)
  const em = (r.rows[0] as { em: string | Date | null } | undefined)?.em
  const nossa = em ? new Date(em).getTime() : 0
  const agora = Date.now()
  if (agora - nossa < RESPONDENDO_MS) return true
  const aviso = ultimoAviso.get(leadId) || 0
  return aviso > nossa && agora - aviso < RAJADA_MS
}

function anotarAviso(leadId: string) {
  if (ultimoAviso.size > 2000) ultimoAviso.clear()
  ultimoAviso.set(leadId, Date.now())
}

/**
 * Notifica sobre uma mensagem inbound nova — todo mundo da organização que tem push
 * ativado, dono do lead ou não (time pequeno, ninguém deve perder mensagem por não
 * ser o "responsável" formal do lead). SÓ A QUE PRECISA DE GENTE (04/10, ver
 * precisaDeGente.ts): o que a Nay responde sozinha não avisa. Também grava em `notifications` (mesma tabela
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
    // primeiro quem tem o aviso ligado: sem ninguém, nada a fazer (nem perguntar à Nay)
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

    const [lead] = await db
      .select({
        title: leads.title, phone: leads.phone, isGroup: leads.isGroup,
        customAttributes: leads.customAttributes, linha: integrations.type,
      })
      .from(leads)
      .leftJoin(integrations, eq(integrations.id, leads.integrationId))
      .where(eq(leads.id, leadId))
      .limit(1)
    if (!lead) return

    const atributos: any = lead.customAttributes || {}
    const mensagem = {
      linha: lead.linha ?? null,
      grupo: lead.isGroup === true,
      telefone: lead.phone,
      texto: activity.text ?? null,
      midia: activity.mediaType ?? null,
      customAttributes: atributos,
    }
    // do mais barato para o mais caro: o que nunca avisa, depois quem já está vendo, e só então a Nay
    if (nuncaAvisa(mensagem)) return
    if (await jaEstaSendoVista(leadId)) return
    const decisao = precisaDeGente({
      ...mensagem,
      marca: lead.linha === LINHA_DA_PARCERIA ? await marcaDaPessoa(lead.phone) : undefined,
      abasDoDono: lead.linha === LINHA_DA_CAPTACAO
        ? await abasDoDonoDaCaptacao(lead.phone, typeof atributos.chat_lid === 'string' ? atributos.chat_lid : null)
        : undefined,
    })
    if (!decisao.avisar) return
    anotarAviso(leadId)

    const title = lead.title || 'Novo contato'
    const body = activity.text?.trim() || (activity.mediaType && MEDIA_LABELS[activity.mediaType]) || 'Nova mensagem'
    const linkUrl = `/chat?leadId=${leadId}`

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
