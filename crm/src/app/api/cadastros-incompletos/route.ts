/**
 * GET /api/cadastros-incompletos -- CADASTROS INCOMPLETOS (Pedro, 03/11/2026): "os donos com quem a conversa do cadastro do
 * imóvel parou, no CRM, com o número e as mensagens dele e um botão para ir para a conversa, com uma nota do imóvel pelo que
 * nossos clientes estão pedindo, e a certeza de que não vamos falar com quem já falamos em outro número recentemente ou já
 * teve o imóvel cadastrado".
 *
 * Os cadastros e a nota vêm do banco da Nay (crm_cadastros_incompletos, 571); as conversas, do CRM. Cada dono cai em UM grupo:
 *   - 'nao_chamar'  já cadastramos o imóvel, já falamos com ele em outro número (Parceria, outra linha do CRM ou a Nay do
 *                   cadastro) nos últimos 14 dias, ou ele pediu para não receber mais mensagem;
 *   - 'com_equipe'  o Tel ou alguém da equipe assumiu a conversa: a Nay não retoma;
 *   - 'livre'       o cadastro parou e ninguém falou com ele em outro lugar: dá para continuar.
 * Só lê. Quem manda mensagem é a pessoa, pela conversa (o botão abre o chat).
 */
import { NextRequest } from 'next/server'
import { sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { naydb } from '@/lib/nayDisparo'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const DIAS_DE_FALA = 14
const LINHA: Record<string, string> = {
  whatsapp_cloud_official: 'Oficial · 8456-0874', whatsapp_zapi_captacao: 'Leads · 8595-6408', whatsapp_zapi: 'Parceria · 9445-3618',
}
const TIPO_DA_LINHA: Record<string, string> = { oficial: 'whatsapp_cloud_official', zapi: 'whatsapp_zapi_captacao' }

const so8 = (t: string | null) => (t || '').replace(/\D/g, '').slice(-8)

export async function GET(req: NextRequest) {
  try {
    const auth = await authenticateRequest(req)
    const a = await naydb().query('SELECT crm_cadastros_incompletos($1::int) AS j', [DIAS_DE_FALA])
    const cadastros = (a.rows[0]?.j || []) as any[]

    // as conversas do CRM de todos esses telefones, em todas as linhas
    const fones = Array.from(new Set(cadastros.map((c) => so8(c.telefone)).filter((f) => f.length === 8)))
    const leads: any[] = fones.length
      ? ((await db.execute(sql`
          SELECT l.id::text AS id, l.title, l.phone, i.type AS linha,
                 right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 8) AS f8,
                 (SELECT max(x.created_at) FROM lead_activities x WHERE x.lead_id = l.id AND x.type = 'whatsapp') AS ultima
            FROM leads l JOIN integrations i ON i.id = l.integration_id
           WHERE l.organization_id = ${auth.organizationId}::uuid AND l.deleted_at IS NULL
             AND right(regexp_replace(coalesce(l.phone, ''), '\D', '', 'g'), 8) IN (${sql.join(fones.map((f) => sql`${f}`), sql`, `)})`)).rows as any[])
      : []

    // a conversa de cada cadastro: o lead da MESMA linha por onde ele falava (oficial ou 8595)
    const principal = new Map<string, any>()
    for (const c of cadastros) {
      const tipo = TIPO_DA_LINHA[c.canal] || 'whatsapp_cloud_official'
      const l = leads.find((x) => x.f8 === so8(c.telefone) && x.linha === tipo) || leads.find((x) => x.f8 === so8(c.telefone) && x.linha !== 'whatsapp_zapi')
      if (l) principal.set(String(c.cadastro_id), l)
    }
    const ids = Array.from(new Set(Array.from(principal.values()).map((l) => l.id)))
    const msgs = new Map<string, any[]>()
    if (ids.length) {
      const r = await db.execute(sql`
        SELECT lead_id::text AS lead_id, content, metadata->>'direction' AS direcao, metadata->>'source' AS origem, created_at FROM (
          SELECT a.*, row_number() OVER (PARTITION BY a.lead_id ORDER BY a.created_at DESC) AS n
            FROM lead_activities a
           WHERE a.type = 'whatsapp' AND a.lead_id IN (${sql.join(ids.map((i) => sql`${i}::uuid`), sql`, `)})) z
         WHERE n <= 8 ORDER BY lead_id, created_at`)
      for (const m of r.rows as any[]) {
        if (!msgs.has(m.lead_id)) msgs.set(m.lead_id, [])
        msgs.get(m.lead_id)!.push({ texto: String(m.content || '').slice(0, 400), direcao: m.direcao, origem: m.origem, quando: m.created_at })
      }
    }

    const corte = Date.now() - DIAS_DE_FALA * 86400000
    const itens = cadastros.map((c) => {
      const f8 = so8(c.telefone)
      const lead = principal.get(String(c.cadastro_id)) || null
      const motivos: string[] = []
      for (const j of (c.ja_cadastrado || []) as any[]) motivos.push(`Imóvel ${j.codigo} já cadastrado (${j.como})`)
      // outra linha do CRM com mensagem recente
      for (const l of leads.filter((x) => x.f8 === f8 && (!lead || x.id !== lead.id) && x.ultima && new Date(x.ultima).getTime() > corte)) {
        motivos.push(`Falamos em outro número (${LINHA[l.linha] || l.linha}) em ${new Date(l.ultima).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Manaus' })}`)
      }
      if (c.falou_parceria) {
        motivos.push(`Falamos pela Parceria em ${new Date(c.falou_parceria.quando).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Manaus' })} (${c.falou_parceria.mensagens} mensagens)`)
      }
      if (c.cadastro_whats_aberto) motivos.push(`A Nay do cadastro está com ele agora (${c.cadastro_whats_aberto.canal}, ${c.cadastro_whats_aberto.estado})`)
      if (c.opt_out) motivos.push('Pediu para não receber mais mensagem')
      const grupo = motivos.length ? 'nao_chamar' : c.humano ? 'com_equipe' : 'livre'
      return {
        ...c, f8, grupo, motivos, linha: LINHA[TIPO_DA_LINHA[c.canal] || 'whatsapp_cloud_official'],
        leadId: lead?.id || null, titulo: lead?.title || c.nome, ultimaMensagem: lead?.ultima || null,
        mensagens: lead ? msgs.get(lead.id) || [] : [],
      }
    })
    const ordem = { livre: 0, com_equipe: 1, nao_chamar: 2 } as Record<string, number>
    itens.sort((p, q) => ordem[p.grupo] - ordem[q.grupo] || (q.nota ?? -1) - (p.nota ?? -1))
    return Response.json({ itens, diasDeFala: DIAS_DE_FALA })
  } catch (err: any) {
    console.error('[cadastros-incompletos]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui montar a lista de cadastros incompletos.')
  }
}
