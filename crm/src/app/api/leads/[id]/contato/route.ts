/**
 * PATCH /api/leads/{id}/contato -- o que a equipe anota no card do contato
 * (Pedro, 29/09/2026): "quero poder alterar o nome do contato por lá, colocar
 * um apelido" e "embaixo das tags um quadradinho de observação".
 *
 *   { apelido: "Lily (corretora da Ponta Negra)" }  troca o nome que a lista mostra
 *   { observacao: "..." }                           guarda em custom_attributes.observacao
 *
 * A observação SOMA ao custom_attributes (jsonb ||): a rota geral do lead troca
 * o objeto inteiro e apagaria o chat_lid e a etapa do funil guardados ali.
 * O apelido fica: a entrada da Z-API só troca o título quando ele ainda é o
 * número.
 */
import { NextRequest } from 'next/server'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { authenticateRequest, apiError } from '@/lib/api-auth'
import { db } from '@/lib/db'
import { leads } from '@/lib/schema'
import { publishEvent, channels, events } from '@/lib/realtime'
import { DESTINOS_DA_PARCERIA } from '@/lib/etapaDaParceria'
import { marcarEtapaNaNay } from '@/lib/nayLeitura'
import { naydb } from '@/lib/nayDisparo'

/** A etapa em que a Nay está com essa pessoa (visitas/proprietarios/fechamento), ou null. */
async function etapaNaNay(telefone: string): Promise<string | null> {
  if (!telefone) return null
  try {
    const r = await naydb().query('SELECT crm_etapa_da_nay($1::text) AS etapa', [telefone])
    return r.rows[0]?.etapa ?? null
  } catch (err: any) {
    console.error('[etapa da nay]', err?.message || err)
    return null
  }
}

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  try {
    const auth = await authenticateRequest(req)
    const { id } = await params
    const corpo = await req.json().catch(() => ({}))
    const [lead] = await db.select({ id: leads.id, phone: leads.phone }).from(leads)
      .where(and(eq(leads.id, id), eq(leads.organizationId, auth.organizationId), isNull(leads.deletedAt))).limit(1)
    if (!lead) return apiError(404, 'Contato não encontrado.')
    /* O QUE A NAY RESPONDEU À MUDANÇA DE ETAPA (03/10/2026): a tela avisa quem clicou.
       `nayRecebeu: false` é o caso em que o CRM gravou e o banco da Nay não respondeu
       -- a lista muda e ela segue agindo como antes, que é o "não salvou" de quem olha. */
    let daEtapa: { recado: string | null; nayRecebeu: boolean } | null = null

    if (typeof corpo.apelido === 'string') {
      const apelido = corpo.apelido.trim().slice(0, 120)
      if (!apelido) return apiError(400, 'O nome não pode ficar vazio.')
      await db.update(leads).set({ title: apelido, updatedAt: new Date() }).where(eq(leads.id, id))
    }
    if (typeof corpo.observacao === 'string') {
      const observacao = corpo.observacao.slice(0, 4000)
      await db.execute(sql`
        UPDATE leads
           SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                 || jsonb_build_object('observacao', ${observacao}::text, 'observacao_em', now()::text),
               updated_at = now()
         WHERE id = ${id}`)
    }
    /* A ETAPA, MUDADA NA MÃO (Tel, 30/09): "preciso que dê para mudar lá no
       card do cliente a etapa dele". Vale mais que o que a Nay deduziu -- ver
       src/lib/etapaDaParceria.ts. 'todos' apaga a escolha e devolve a conversa
       para a regra automática, em vez de prender ela em Todos para sempre. */
    if (typeof corpo.etapa === 'string') {
      const etapa = corpo.etapa.trim()
      /* O × DA ETIQUETA "COM O TEL / COM A RAYSSA" (migração 212): 'soltar' só
         tira a marca de humano na Nay. 'todos' também concluía o fechamento
         aberto e trocava a etapa escolhida à mão. Aqui sai só a escolha de
         PESSOA do card (tel/rayssa); uma etapa escolhida (Visitas, Fechamento...)
         fica. */
      if (etapa === 'soltar') {
        const quem = auth.userId ? 'CRM ' + auth.userId.slice(0, 8) : 'CRM'
        const recado = await marcarEtapaNaNay(lead.phone || '', 'soltar', quem)
        // A etapa que a Nay conhece (217): se a Rayssa tinha posto em Visitas e depois
        // escolheu "Rayssa", o card volta para Visitas, e não para Todos com a Nay calada.
        const etapaDaNay = await etapaNaNay(lead.phone || '')
        // pessoa_solta_em: a lista deixa de contar quem escreveu pelo login ANTES do ×
        // (senão a conversa ficava para sempre na aba Rayssa/Tel)
        await db.execute(sql`UPDATE leads SET custom_attributes =
                 (CASE WHEN custom_attributes->>'etapa_parceria' IN ('tel', 'rayssa')
                       THEN coalesce(custom_attributes, '{}'::jsonb) - 'etapa_parceria'
                       ELSE coalesce(custom_attributes, '{}'::jsonb) END)
                 || jsonb_build_object('pessoa_solta_em', now()::text)
                 || CASE WHEN ${etapaDaNay}::text IS NOT NULL AND coalesce(custom_attributes->>'etapa_parceria', 'tel') IN ('tel', 'rayssa')
                         THEN jsonb_build_object('etapa_parceria', ${etapaDaNay}::text, 'etapa_parceria_em', now()::text)
                         ELSE '{}'::jsonb END,
                 updated_at = now() WHERE id = ${id}`)
        await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id })
        return Response.json({ ok: true, recado, etapa: etapaDaNay })
      }
      // 'tel' não é etapa do CRM: quem mostra a aba Tel é a marca da Nay
      // (telAtendendo). Aqui ele só avisa a Nay e limpa a escolha manual.
      const paraPessoa = etapa === 'tel' || etapa === 'rayssa'
      if (!DESTINOS_DA_PARCERIA.includes(etapa as any)) return apiError(400, 'Etapa desconhecida.')
      /* E A NAY PRECISA SABER (migração 201): sem isto a escolha só arrumava a
         lista, e a Nay seguia respondendo quem estava preso em Fechamento.

         'rayssa' foi por um tempo como 'tel' aqui, porque o banco não conhecia
         a Rayssa. Desde a migração 208 ele conhece: a Nay cala do mesmo jeito,
         mas a marca fica 'Rayssa: ...' em vez de parecer do Tel. */
      const quem = auth.userId ? 'CRM ' + auth.userId.slice(0, 8) : 'CRM'
      const recado = await marcarEtapaNaNay(lead.phone || '', etapa, quem)
      daEtapa = { recado, nayRecebeu: recado != null || !lead.phone }
      if (paraPessoa) {
        await db.execute(sql`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                 || jsonb_build_object('etapa_parceria', ${etapa}::text, 'etapa_parceria_em', now()::text),
                 updated_at = now() WHERE id = ${id}`)
        await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id })
        return Response.json({ ok: true, ...daEtapa })
      }
      await db.execute(etapa === 'todos'
        ? sql`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb) - 'etapa_parceria',
                     updated_at = now() WHERE id = ${id}`
        : sql`UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                     || jsonb_build_object('etapa_parceria', ${etapa}::text, 'etapa_parceria_em', now()::text),
                     updated_at = now() WHERE id = ${id}`)
    }
    await publishEvent(channels.orgLeads(auth.organizationId), events.LEAD_UPDATED, { id })
    return Response.json({ ok: true, ...(daEtapa || {}) })
  } catch (err: any) {
    return apiError(err?.status || 500, err?.message || 'Não consegui salvar.')
  }
}
