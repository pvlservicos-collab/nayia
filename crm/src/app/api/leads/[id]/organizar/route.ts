/**
 * POST /api/leads/{id}/organizar -- a organização da conversa (Pedro, 03/11/2026; ver src/lib/organizacaoDoLead.ts).
 *
 *   { tipo: 'administracao' | null }                     o tipo de contato (null = volta ao que a lista deduz)
 *   { mostrarEm: { linha: 'parceria', ligar: true } }    a conversa aparece também na aba daquela linha (misto)
 *   { dentroDe: { pai: '<lead id>', ligar: true } }      põe esta conversa dentro de outra (a setinha da lista)
 *   { rayssa: true }                                     "Enviar para Rayssa": a conversa SAI do Leads e vai para a aba Rayssa da
 *                                                        Parceria, no topo e não lida, como conversa nova (mudou_para)
 *   { pessoas: ['<member id>', ...] }                    as pessoas adicionadas à conversa ("Adicionar pessoa")
 *   { devolver: true }                                   devolve a conversa enviada à aba do número dela
 *
 * Só mexe em custom_attributes da conversa; a linha (integration_id) nunca muda (crm/CLAUDE.md).
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { publishEvent, channels, events } from '@/lib/realtime'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const LINHAS = ['parceria', 'captacao', 'oficial']
const fim8 = (t: string | null | undefined) => (t || '').replace(/\D/g, '').slice(-8)

export async function POST(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    if (!auth.userId) return apiError(403, 'Só quem entra no CRM organiza as conversas.')
    const { id } = await params
    const corpo = await req.json().catch(() => ({} as any))
    const [lead] = await db.select({ id: leads.id, phone: leads.phone }).from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt))).limit(1)
    if (!lead) return apiError(404, 'Conversa não encontrada.')

    if ('tipo' in corpo) {
      const tipo = corpo.tipo == null ? null : String(corpo.tipo).trim().slice(0, 40)
      await db.execute(tipo
        ? sql`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('tipo_contato', ${tipo}::text),
                 updated_at = now() WHERE id = ${id}`
        : sql`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb) - 'tipo_contato', updated_at = now() WHERE id = ${id}`)
      /* 03/11 ("troca a etapa Fechamento pela etapa Administração"): mandar para Administração é mudar de ETAPA no Leads --
         a etiqueta Administração (nascida Fechamento) entra e as outras três etapas saem, como em api/leads/[id]/tags */
      if (tipo === 'administracao') {
        await db.execute(sql`
          DELETE FROM lead_tags lt USING tags t
           WHERE lt.lead_id = ${id} AND t.id = lt.tag_id AND t.organization_id = ${auth.organizationId}
             AND coalesce(t.nome_original, t.name) IN ('Visita', 'Proprietários', 'Finalizados')`)
        await db.execute(sql`
          INSERT INTO lead_tags (lead_id, tag_id, organization_id)
          SELECT ${id}::uuid, t.id, ${auth.organizationId}::uuid FROM tags t
           WHERE t.organization_id = ${auth.organizationId} AND coalesce(t.nome_original, t.name) = 'Fechamento'
             AND NOT EXISTS (SELECT 1 FROM lead_tags x WHERE x.lead_id = ${id} AND x.tag_id = t.id)
           LIMIT 1`)
      }
    }
    if (corpo.mostrarEm) {
      const linha = String(corpo.mostrarEm.linha || '')
      if (!LINHAS.includes(linha)) return apiError(400, 'Linha inválida.')
      await db.execute(corpo.mostrarEm.ligar === false
        ? sql`UPDATE leads SET custom_attributes = jsonb_set(coalesce(custom_attributes, '{}'::jsonb), '{mostrar_tambem_em}',
                 coalesce((SELECT jsonb_agg(x) FROM jsonb_array_elements_text(custom_attributes->'mostrar_tambem_em') x WHERE x <> ${linha}), '[]'::jsonb)),
                 updated_at = now() WHERE id = ${id}`
        : sql`UPDATE leads SET custom_attributes = jsonb_set(coalesce(custom_attributes, '{}'::jsonb), '{mostrar_tambem_em}',
                 (SELECT jsonb_agg(DISTINCT x) FROM (SELECT jsonb_array_elements_text(coalesce(custom_attributes->'mostrar_tambem_em', '[]'::jsonb)) AS x
                                                    UNION SELECT ${linha}::text) y)),
                 updated_at = now() WHERE id = ${id}`)
    }
    if (corpo.dentroDe) {
      const [pai] = await db.select({ id: leads.id, phone: leads.phone }).from(leads)
        .where(and(eq(leads.id, String(corpo.dentroDe.pai || '')), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt))).limit(1)
      const p8 = fim8(pai?.phone)
      if (!pai || p8.length !== 8) return apiError(400, 'Não achei a conversa de fora.')
      if (p8 === fim8(lead.phone)) return apiError(400, 'Uma conversa não entra dentro dela mesma.')
      await db.execute(corpo.dentroDe.ligar === false
        ? sql`UPDATE leads SET custom_attributes = jsonb_set(coalesce(custom_attributes, '{}'::jsonb), '{dentro_de}',
                 coalesce((SELECT jsonb_agg(x) FROM jsonb_array_elements_text(custom_attributes->'dentro_de') x WHERE x <> ${p8}), '[]'::jsonb)),
                 updated_at = now() WHERE id = ${id}`
        : sql`UPDATE leads SET custom_attributes = jsonb_set(coalesce(custom_attributes, '{}'::jsonb), '{dentro_de}',
                 (SELECT jsonb_agg(DISTINCT x) FROM (SELECT jsonb_array_elements_text(coalesce(custom_attributes->'dentro_de', '[]'::jsonb)) AS x
                                                    UNION SELECT ${p8}::text) y)),
                 updated_at = now() WHERE id = ${id}`)
    }
    if (corpo.rayssa === true) {
      /* a aba Rayssa da Parceria é a escolha à mão etapa_parceria = 'rayssa' (etapaDaParceria.ts). Pedro, 03/11: "quando
         enviar para o outro número ele some da lista do Leads, e aparece no outro número como se fosse uma conversa nova, já
         lá em cima": mudou_para tira da aba do Leads; a última atividade e o "não lida" põem no topo da Parceria */
      await db.execute(sql`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                 || jsonb_build_object('etapa_parceria', 'rayssa', 'etapa_parceria_em', now()::text,
                                       'mudou_para', 'parceria', 'mudou_em', now()::text),
                 last_activity_at = now(), is_unread = true, updated_at = now() WHERE id = ${id}`)
    }
    if (Array.isArray(corpo.pessoas)) {
      const pessoas = [...new Set(corpo.pessoas.map(String).filter((x: string) => /^[0-9a-f-]{36}$/i.test(x)))].slice(0, 20)
      await db.execute(sql`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                 || jsonb_build_object('pessoas', ${JSON.stringify(pessoas)}::jsonb, 'pessoas_em', now()::text),
                 updated_at = now() WHERE id = ${id}`)
    }
    if (corpo.devolver === true) {
      await db.execute(sql`UPDATE leads SET custom_attributes = (coalesce(custom_attributes, '{}'::jsonb) - 'mudou_para' - 'mudou_em'
                 - 'mostrar_tambem_em'
                 - (CASE WHEN custom_attributes->>'etapa_parceria' = 'rayssa' THEN 'etapa_parceria' ELSE '' END)),
                 last_activity_at = now(), updated_at = now() WHERE id = ${id}`)
    }
    const [depois] = await db.select({ custom_attributes: leads.customAttributes, last_activity_at: leads.lastActivityAt, is_unread: leads.isUnread })
      .from(leads).where(eq(leads.id, id)).limit(1)
    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id })
    return Response.json({ ok: true, custom_attributes: depois?.custom_attributes || {}, last_activity_at: depois?.last_activity_at, is_unread: depois?.is_unread })
  } catch (err: any) {
    console.error('[leads/organizar]', err?.message || err)
    return apiError(err?.status || 500, err?.message || 'Não consegui organizar a conversa.')
  }
}
