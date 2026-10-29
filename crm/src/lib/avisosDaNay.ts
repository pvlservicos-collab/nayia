/**
 * OS AVISOS DA NAY NAS NOTIFICAÇÕES (Pedro, 28/10/2026; migração 508): "as filas de dúvidas, e as mensagens de escala
 * põe no painel notificações do crm, deixa só as visitas e lembretes de visitas no grupo; o relatório da IA põe nas
 * notificações do CRM também". O que a Nay mandava ao grupo Altarquia e não é visita (escalada da Parceria, mídia e
 * escalada da captação, cliente do WhatsApp de captação, dúvida sem resposta, áudio de dono, relatório das 22h) mora
 * no banco da Nay (privado.aviso_equipe); aqui cada aviso novo vira uma notificação para cada pessoa da equipe.
 *
 * Roda na rodada rápida do espelho (~10 s). O último aviso levado é o maior `avisoId` já gravado: rodadas que se
 * cruzam no mesmo processo esperam a anterior, e por isso não duplicam.
 */
import { sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'
import { sendPushToMember } from '@/lib/push'

type Aviso = { id: string; fonte: string; tipo: string; titulo: string; texto: string; telefone: string | null }

// o tipo do aviso -> o ícone da página de notificações (typeConfig de notifications/page.tsx)
const ICONE: Record<string, string> = {
  escalada: 'support', duvida: 'warning', midia: 'message', relatorio: 'report', lead: 'support', outro: 'info',
}
// a linha em que a conversa de cada fonte mora, para o "Ver conversa"
const LINHA: Record<string, string> = {
  'nay-core': 'whatsapp_zapi', 'nay-captacao': 'whatsapp_zapi_captacao', 'nay-olx': 'whatsapp_zapi_captacao',
  'nay-grupos': 'whatsapp_zapi',   // 516: o pedido original do corretor, na conversa da Parceria
}

let rodando: Promise<number> | null = null

export function levarAvisosDaNay(organizacao: string): Promise<number> {
  if (!rodando) rodando = levar(organizacao).finally(() => { rodando = null })
  return rodando
}

async function levar(organizacao: string): Promise<number> {
  const [ultimo] = (await db.execute(sql`
    SELECT coalesce(max((metadata->>'avisoId')::bigint), 0)::text AS id FROM notifications
     WHERE organization_id = ${organizacao} AND metadata ? 'avisoId'`)).rows as Array<{ id: string }>
  const r = await naydb().query('SELECT id::text AS id, fonte, tipo, titulo, texto, telefone FROM crm_avisos_da_equipe($1)',
    [ultimo?.id || '0'])
  const avisos = r.rows as Aviso[]
  if (!avisos.length) return 0

  const equipe = (await db.execute(sql`
    SELECT id::text AS id FROM organization_members
     WHERE organization_id = ${organizacao} AND status = 'active' AND deleted_at IS NULL`)).rows as Array<{ id: string }>
  if (!equipe.length) return 0

  for (const a of avisos) {
    // a dúvida nova para o Tel (527) abre o painel Respostas Tel, não a conversa
    const leadId = a.fonte === 'respostas-tel' ? null : await conversaDoAviso(organizacao, a)
    const linkUrl = a.fonte === 'respostas-tel' ? '/respostas-tel' : leadId ? `/chat?leadId=${leadId}` : null
    await db.execute(sql`
      INSERT INTO notifications (organization_id, recipient_member_id, type, title, body, metadata)
      SELECT ${organizacao}::uuid, m::uuid, ${ICONE[a.tipo] || 'info'}, ${a.titulo}, ${a.texto},
             ${JSON.stringify({ avisoId: a.id, fonte: a.fonte, tipo: a.tipo, linkUrl, leadId })}::jsonb
        FROM unnest(${sql.raw(`ARRAY[${equipe.map((m) => `'${m.id}'`).join(',')}]::text[]`)}) AS m`)
    for (const m of equipe) {
      void sendPushToMember(organizacao, m.id, {
        title: a.titulo, body: a.texto.slice(0, 180), url: linkUrl || '/notifications', tag: `aviso-${a.id}`,
      }).catch(() => undefined)
    }
  }
  return avisos.length
}

/**
 * AS NOTAS DA NAY NA CONVERSA (511, Tel 28/10: "ela precisa enviar o link do imóvel para depois a gente clicar para
 * saber se esse imóvel pelo perfil vai atender o cliente"; Pedro: só no CRM). O aviso tipo 'nota' não é notificação:
 * vira nota interna (a amarela) na conversa do telefone. A conversa do anunciante da OLX pode nascer aqui depois da
 * nota, por isso não há marcador: cada rodada olha as notas dos últimos dias e grava as que faltam (pelo avisoId).
 */
let rodandoNotas: Promise<number> | null = null

export function levarNotasDaNay(organizacao: string): Promise<number> {
  if (!rodandoNotas) rodandoNotas = levarNotas(organizacao).finally(() => { rodandoNotas = null })
  return rodandoNotas
}

async function levarNotas(organizacao: string): Promise<number> {
  const r = await naydb().query('SELECT id::text AS id, fonte, titulo, texto, telefone, criado_em FROM crm_notas_da_nay(3)')
  const notas = r.rows as Array<Aviso & { criado_em: Date }>
  if (!notas.length) return 0
  const ja = new Set(((await db.execute(sql`
    SELECT metadata->>'avisoId' AS id FROM lead_activities
     WHERE organization_id = ${organizacao} AND type = 'note' AND metadata ? 'avisoId'
       AND created_at > now() - interval '4 days'`)).rows as Array<{ id: string }>).map((x) => x.id))
  let n = 0
  for (const a of notas) {
    if (ja.has(a.id)) continue
    const leadId = await conversaDoAviso(organizacao, { ...a, tipo: 'nota' })
    if (!leadId) continue                       // a conversa ainda não existe no CRM: a próxima rodada tenta de novo
    await db.execute(sql`
      INSERT INTO lead_activities (organization_id, lead_id, type, content, metadata, created_at)
      VALUES (${organizacao}::uuid, ${leadId}::uuid, 'note', ${a.texto},
              ${JSON.stringify({ avisoId: a.id, fonte: a.fonte, de: 'Nay', titulo: a.titulo })}::jsonb, ${a.criado_em})`)
    n++
  }
  return n
}

/** A conversa do telefone do aviso, pelos 8 últimos dígitos, de preferência na linha da fonte. */
async function conversaDoAviso(organizacao: string, a: Aviso): Promise<string | null> {
  const fim = String(a.telefone || '').replace(/\D/g, '').slice(-8)
  if (fim.length !== 8) return null
  const [l] = (await db.execute(sql`
    SELECT l.id::text AS id FROM leads l LEFT JOIN integrations i ON i.id = l.integration_id
     WHERE l.organization_id = ${organizacao} AND l.deleted_at IS NULL AND l.is_group IS NOT TRUE
       AND right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 8) = ${fim}
     ORDER BY (i.type = ${LINHA[a.fonte] || ''}) DESC, l.last_activity_at DESC NULLS LAST
     LIMIT 1`)).rows as Array<{ id: string }>
  return l?.id || null
}
