/**
 * OS FUNIS ANDAM SOZINHOS (Pedro, 29/09/2026): "cada tag é uma etapa da
 * pipeline e o lead é movido pelo CRM conforme muda de tag automaticamente".
 *
 * Um funil por número (crm/drizzle/0127). A cada minuto (/api/cron/funis):
 *
 *   CAPTAÇÃO -- todos que receberam o disparo da campanha (decisão dele). A
 *   etapa vem do banco da Nay (crm_captacao_funil, migração 172): Não respondeu
 *   > Respondeu > Disponível > Alugado > Vendido > Mandou os dados. Quem ainda
 *   não tem conversa no CRM ganha um card (sem mensagem, então não aparece na
 *   lista do chat -- ver ehConversaVisivel). A etiqueta de mesmo nome acompanha.
 *
 *   PARCERIA -- a etapa da Nay (Identificação > Recebeu imóvel > Agendamento de
 *   visita) move o card SÓ enquanto ele está nessas etapas (ou fora do funil).
 *   Quem a equipe pôs em Agendou visita / Follow up / Fechou contrato fica lá.
 *   Não cria conversa: o card é de quem já conversa.
 *
 * O CARD SÓ ANDA QUANDO A ETAPA CALCULADA MUDA (guardada em
 * custom_attributes.funil_auto). Quem arrastou à mão não é desfeito a cada
 * minuto -- só na próxima mudança de verdade.
 */
import { and, eq, isNull, sql } from 'drizzle-orm'
import { db } from '@/lib/db'
import { integrations, leads, leadStageHistory } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import { telefoneCanonico, telefoneVariantes } from '@/lib/leadSources'
import { PIPELINE_DA_LINHA } from '@/lib/etapaDaLinha'
import { isUniqueViolation } from '@/lib/db-helpers'
import { publishEvent, channels, events } from '@/lib/realtime'

const ETAPAS_DA_NAY = ['Identificação', 'Recebeu imóvel', 'Agendamento de visita']
const ETAPAS_DA_CAPTACAO = ['Não respondeu', 'Respondeu', 'Disponível', 'Alugado', 'Vendido', 'Mandou os dados']

export interface ResultadoDosFunis {
  captacao: { naNay: number; criados: number; movidos: number }
  parceria: { naNay: number; movidos: number; semConversa: number; ficouNaEquipe: number }
}

type LeadDoFunil = { id: string; phone: string | null; stage_id: string | null; custom_attributes: Record<string, any> | null }

let rodando = false

export async function sincronizarFunis(org: string): Promise<ResultadoDosFunis | null> {
  if (rodando) return null
  rodando = true
  try {
    const r: ResultadoDosFunis = {
      captacao: { naNay: 0, criados: 0, movidos: 0 },
      parceria: { naNay: 0, movidos: 0, semConversa: 0, ficouNaEquipe: 0 },
    }

    // as etapas de cada funil, por nome
    // 0133: a etapa e a etiqueta renomeadas na tela continuam achadas pelo nome de nascença (nome_original)
    const etapas = await db.execute(sql`
      SELECT s.id, s.name, s.nome_original, p.name AS pipeline FROM pipeline_stages s JOIN pipelines p ON p.id = s.pipeline_id
       WHERE s.organization_id = ${org} AND s.deleted_at IS NULL AND p.deleted_at IS NULL`)
    type Etapa = { id: string; name: string; nome_original: string | null; pipeline: string }
    const etapaDe = (pipeline: string, nome: string) => {
      const doFunil = (etapas.rows as Etapa[]).filter((e) => e.pipeline === pipeline)
      return (doFunil.find((e) => e.name === nome) ?? doFunil.find((e) => e.nome_original === nome))?.id ?? null
    }

    // as etiquetas de mesmo nome (a da captação acompanha o card)
    const etiquetas = await db.execute(sql`SELECT id, name, nome_original FROM tags WHERE organization_id = ${org}`)
    type Marca = { id: string; name: string; nome_original: string | null }
    const etiquetaDe = (nome: string) =>
      ((etiquetas.rows as Marca[]).find((t) => t.name === nome) ?? (etiquetas.rows as Marca[]).find((t) => t.nome_original === nome))?.id ?? null
    const idsDaCaptacao = ETAPAS_DA_CAPTACAO.map(etiquetaDe).filter(Boolean) as string[]

    const linhas = await db.select({ id: integrations.id, type: integrations.type }).from(integrations)
      .where(and(eq(integrations.organizationId, org), isNull(integrations.deletedAt)))
    const linhaDe = (tipo: string) => linhas.find((l) => l.type === tipo)?.id ?? null

    let mexeu = false

    async function mover(lead: LeadDoFunil, paraEtapa: string, etapaCalculada: string) {
      await db.execute(sql`
        UPDATE leads SET stage_id = ${paraEtapa}, updated_at = now(),
               custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('funil_auto', ${etapaCalculada}::text)
         WHERE id = ${lead.id}`)
      await db.insert(leadStageHistory).values({
        organizationId: org, leadId: lead.id, fromStageId: lead.stage_id, toStageId: paraEtapa, movedByMemberId: null, movedAt: new Date(),
      })
      mexeu = true
    }
    async function lembrar(lead: LeadDoFunil, etapaCalculada: string) {
      await db.execute(sql`
        UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb) || jsonb_build_object('funil_auto', ${etapaCalculada}::text)
         WHERE id = ${lead.id}`)
    }
    async function etiquetar(leadId: string, nome: string) {
      const tag = etiquetaDe(nome)
      if (!tag) return
      await db.execute(sql`
        DELETE FROM lead_tags WHERE lead_id = ${leadId} AND tag_id <> ${tag}
           AND tag_id IN (SELECT (jsonb_array_elements_text(${JSON.stringify(idsDaCaptacao)}::jsonb))::uuid)`)
      await db.execute(sql`
        INSERT INTO lead_tags (lead_id, tag_id, organization_id) VALUES (${leadId}, ${tag}, ${org}) ON CONFLICT DO NOTHING`)
    }

    // ── Captação ──
    const linhaCaptacao = linhaDe('whatsapp_zapi_captacao')
    const funilCaptacao = PIPELINE_DA_LINHA.whatsapp_zapi_captacao
    if (linhaCaptacao && etapaDe(funilCaptacao, ETAPAS_DA_CAPTACAO[0])) {
      const { rows } = await naydb().query('SELECT * FROM crm_captacao_funil()')
      r.captacao.naNay = rows.length
      const doBanco = await db.execute(sql`
        SELECT id, phone, stage_id, custom_attributes FROM leads
         WHERE organization_id = ${org} AND integration_id = ${linhaCaptacao} AND deleted_at IS NULL AND NOT coalesce(is_group, false)`)
      const porTelefone = new Map<string, LeadDoFunil>()
      for (const l of doBanco.rows as LeadDoFunil[]) if (l.phone) porTelefone.set(l.phone, l)

      for (const linha of rows as Array<{ telefone: string; nome: string | null; etapa: string }>) {
        const etapa = etapaDe(funilCaptacao, linha.etapa)
        if (!etapa) continue
        const formas = telefoneVariantes(linha.telefone)
        const lead = formas.map((f) => porTelefone.get(f)).find(Boolean)
        if (!lead) {
          const fone = telefoneCanonico(linha.telefone)
          if (!fone) continue
          try {
            const [novo] = await db.insert(leads).values({
              organizationId: org,
              title: linha.nome || fone,
              phone: fone,
              isGroup: false,
              integrationId: linhaCaptacao,
              stageId: etapa,
              customAttributes: { origem: 'captacao_campanha', funil_auto: linha.etapa },
            }).returning({ id: leads.id })
            await db.insert(leadStageHistory).values({
              organizationId: org, leadId: novo.id, fromStageId: null, toStageId: etapa, movedByMemberId: null, movedAt: new Date(),
            })
            await etiquetar(novo.id, linha.etapa)
            porTelefone.set(fone, { id: novo.id, phone: fone, stage_id: etapa, custom_attributes: { funil_auto: linha.etapa } })
            r.captacao.criados++
            mexeu = true
          } catch (err) {
            if (!isUniqueViolation(err)) throw err
          }
          continue
        }
        if (lead.custom_attributes?.funil_auto === linha.etapa) continue
        if (lead.stage_id !== etapa) {
          await mover(lead, etapa, linha.etapa)
          r.captacao.movidos++
        } else {
          await lembrar(lead, linha.etapa)
        }
        await etiquetar(lead.id, linha.etapa)
      }
    }

    // ── Parceria ──
    const linhaParceria = linhaDe('whatsapp_zapi')
    const funilParceria = PIPELINE_DA_LINHA.whatsapp_zapi
    if (linhaParceria && etapaDe(funilParceria, ETAPAS_DA_NAY[0])) {
      const idsDaNay = new Set(ETAPAS_DA_NAY.map((n) => etapaDe(funilParceria, n)).filter(Boolean) as string[])
      const { rows } = await naydb().query('SELECT * FROM crm_parceria_funil()')
      r.parceria.naNay = rows.length
      const doBanco = await db.execute(sql`
        SELECT id, phone, stage_id, custom_attributes FROM leads
         WHERE organization_id = ${org} AND integration_id = ${linhaParceria} AND deleted_at IS NULL AND NOT coalesce(is_group, false)`)
      const porTelefone = new Map<string, LeadDoFunil>()
      const porLid = new Map<string, LeadDoFunil>()
      for (const l of doBanco.rows as LeadDoFunil[]) {
        if (l.phone) porTelefone.set(l.phone, l)
        const lid = String(l.custom_attributes?.chat_lid || '').replace(/\D/g, '')
        if (lid) porLid.set(lid, l)
        if (l.phone && !l.phone.startsWith('55')) porLid.set(l.phone, l)
      }
      for (const linha of rows as Array<{ telefone: string | null; lid: string | null; etapa: string }>) {
        const etapa = etapaDe(funilParceria, linha.etapa)
        if (!etapa) continue
        const lead = (linha.telefone ? telefoneVariantes(linha.telefone).map((f) => porTelefone.get(f)).find(Boolean) : undefined)
          ?? (linha.lid ? porLid.get(linha.lid) : undefined)
        if (!lead) { r.parceria.semConversa++; continue }
        if (lead.custom_attributes?.funil_auto === linha.etapa) continue
        // quem a equipe já pôs nas etapas dela fica lá
        if (lead.stage_id && !idsDaNay.has(lead.stage_id)) {
          await lembrar(lead, linha.etapa)
          r.parceria.ficouNaEquipe++
          continue
        }
        if (lead.stage_id !== etapa) {
          await mover(lead, etapa, linha.etapa)
          r.parceria.movidos++
        } else {
          await lembrar(lead, linha.etapa)
        }
      }
    }

    /* A ETIQUETA ACOMPANHA A ETAPA NA PARCERIA E NA OFICIAL (Pedro, 19/10/2026: "todas as tags do WhatsApp Parceria
       ainda zeradas"). Aqui o card andava (Identificação 119, Recebeu imóvel 69...) mas a etiqueta de mesmo nome nunca
       era posta: só havia as "Nay: ...", que a prancheta esconde. Agora cada conversa da linha tem a etiqueta da etapa em
       que está, e só ela (entre as etiquetas de etapa daquele funil). Marcar a etiqueta à mão já move o card
       (api/leads/[id]/tags); arrastar o card troca a etiqueta aqui, no minuto seguinte. A etiqueta que faltar é criada. */
    for (const tipo of ['whatsapp_zapi', 'whatsapp_cloud_official'] as const) {
      const linhaId = linhaDe(tipo)
      const funil = PIPELINE_DA_LINHA[tipo]
      if (!linhaId || !funil) continue
      await db.execute(sql`
        INSERT INTO tags (organization_id, name, color)
        SELECT DISTINCT ${org}::uuid, s.name, '#64748b' FROM pipeline_stages s JOIN pipelines p ON p.id = s.pipeline_id
         WHERE p.organization_id = ${org} AND p.name = ${funil} AND s.deleted_at IS NULL AND p.deleted_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM tags t WHERE t.organization_id = ${org} AND t.name = s.name)`)
      const espelho = await db.execute(sql`
        WITH etapas AS (
          SELECT s.id AS stage_id, s.name FROM pipeline_stages s JOIN pipelines p ON p.id = s.pipeline_id
           WHERE p.organization_id = ${org} AND p.name = ${funil} AND s.deleted_at IS NULL AND p.deleted_at IS NULL),
        marcas AS (SELECT t.id AS tag_id, t.name FROM tags t WHERE t.organization_id = ${org} AND t.name IN (SELECT name FROM etapas)),
        dela AS (
          SELECT l.id AS lead_id, m.tag_id FROM leads l JOIN etapas e ON e.stage_id = l.stage_id JOIN marcas m ON m.name = e.name
           WHERE l.organization_id = ${org} AND l.integration_id = ${linhaId} AND l.deleted_at IS NULL),
        tira AS (
          DELETE FROM lead_tags lt USING leads l
           WHERE lt.lead_id = l.id AND l.integration_id = ${linhaId} AND lt.tag_id IN (SELECT tag_id FROM marcas)
             AND NOT EXISTS (SELECT 1 FROM dela d WHERE d.lead_id = lt.lead_id AND d.tag_id = lt.tag_id)
          RETURNING 1),
        poe AS (
          INSERT INTO lead_tags (lead_id, tag_id, organization_id) SELECT lead_id, tag_id, ${org}::uuid FROM dela
          ON CONFLICT DO NOTHING RETURNING 1)
        SELECT (SELECT count(*) FROM tira)::int AS tirou, (SELECT count(*) FROM poe)::int AS pos`)
      const e = (espelho.rows[0] || {}) as { tirou?: number; pos?: number }
      if ((e.tirou || 0) + (e.pos || 0) > 0) mexeu = true
    }

    /* AS ETAPAS DO WHATSAPP LEADS VIRAM ETIQUETAS (Pedro, 20/10/2026: "a partir de agora vão sair essas etapas [as do
       disparo] e as etapas vão virar as tags lá em cima"). Visita, Proprietários, Fechamento e Finalizados: a etapa do
       cliente da OLX (crm_olx_clientes_etapas, a mesma da lista) ou, sem ela, Proprietários para o dono da campanha.
       As etiquetas do disparo antigo NÃO são tocadas (a foto delas está em Relatórios, 426). Achadas pelo nome de
       nascença (0133).
       ETIQUETA DE VERDADE, EDITÁVEL (Pedro, 20/10, mais tarde: "lá no whatsapp leads as etapas não viraram as tags como
       eu pedi"). Até aqui o espelho refazia as quatro a cada minuto: quem pusesse ou tirasse a etiqueta da etapa à mão
       via a mudança desfeita no minuto seguinte. Agora o espelho só age quando a ETAPA muda (a Nay mudou, ou a equipe
       pelo card / botão direito): tira as outras três e põe a da etapa nova. A última etapa espelhada fica em
       leads.custom_attributes.etapa_leads_fato ('' = nenhuma das quatro). Pôr ou tirar a etiqueta à mão fica valendo
       (api/leads/[id]/tags: pôr uma das quatro tira as outras três, é mudar de aba). Nada de lead é apagado. */
    const linhaLeads = linhaDe('whatsapp_zapi_captacao')
    if (linhaLeads) {
      const ETAPA_PARA_ETIQUETA: Record<string, { nome: string; cor: string }> = {
        visita: { nome: 'Visita', cor: '#be185d' }, proprietarios: { nome: 'Proprietários', cor: '#d97706' },
        fechamento: { nome: 'Fechamento', cor: '#7c3aed' }, finalizado: { nome: 'Finalizados', cor: '#6b7280' },
      }
      for (const { nome, cor } of Object.values(ETAPA_PARA_ETIQUETA)) {
        await db.execute(sql`
          INSERT INTO tags (organization_id, name, color, nome_original)
          SELECT ${org}::uuid, ${nome}, ${cor}, ${nome}
           WHERE NOT EXISTS (SELECT 1 FROM tags WHERE organization_id = ${org} AND (nome_original = ${nome} OR name = ${nome}))`)
      }
      const marcas = (await db.execute(sql`
        SELECT id::text, coalesce(nome_original, name) AS chave FROM tags
         WHERE organization_id = ${org}
           AND coalesce(nome_original, name) IN (${sql.join(Object.values(ETAPA_PARA_ETIQUETA).map((e) => sql`${e.nome}`), sql`, `)})`))
        .rows as Array<{ id: string; chave: string }>
      const etiquetaDaEtapa = (etapa: string) => marcas.find((m) => m.chave === ETAPA_PARA_ETIQUETA[etapa]?.nome)?.id
      const [clientes, donosDaCampanha] = await Promise.all([
        naydb().query('SELECT telefone, etapa FROM crm_olx_clientes_etapas()'),
        naydb().query('SELECT telefone FROM crm_captacao_donos()'),
      ])
      const fim8 = (t: unknown) => String(t || '').replace(/\D/g, '').slice(-8)
      const etapaPorFim = new Map<string, string>()
      for (const d of donosDaCampanha.rows as Array<{ telefone: string }>) if (fim8(d.telefone).length === 8) etapaPorFim.set(fim8(d.telefone), 'proprietarios')
      for (const c of clientes.rows as Array<{ telefone: string; etapa: string }>) if (fim8(c.telefone).length === 8) etapaPorFim.set(fim8(c.telefone), c.etapa)
      const conversas = (await db.execute(sql`
        SELECT l.id::text, l.phone, l.custom_attributes->>'etapa_leads_fato' AS antes,
               EXISTS (SELECT 1 FROM lead_tags lt WHERE lt.lead_id = l.id
                          AND lt.tag_id = ANY(${sql.raw(`ARRAY[${marcas.map((m) => `'${m.id}'`).join(',')}]::uuid[]`)})) AS tem_etapa
          FROM leads l
         WHERE l.organization_id = ${org} AND l.integration_id = ${linhaLeads} AND l.deleted_at IS NULL AND NOT coalesce(l.is_group, false)`))
        .rows as Array<{ id: string; phone: string | null; antes: string | null; tem_etapa: boolean }>
      /* só quem mudou de etapa desde o último espelho. Sem anotação (a 1ª vez, ou alguém regravou o custom_attributes
         inteiro): quem já tem uma das quatro só ganha a anotação, para não desfazer o que foi posto à mão. */
      const mudou = conversas
        .map((l) => {
          const e = etapaPorFim.get(fim8(l.phone)) || ''
          const fato = ETAPA_PARA_ETIQUETA[e] ? e : ''
          const soAnota = l.antes === null && !!l.tem_etapa
          return { lead_id: l.id, tag_id: fato ? etiquetaDaEtapa(fato) || null : null, fato, antes: l.antes, so_anota: soAnota }
        })
        .filter((x) => x.antes === null || x.antes !== x.fato)
        .map(({ lead_id, tag_id, fato, so_anota }) => ({ lead_id, tag_id, fato, so_anota }))
      if (marcas.length && mudou.length) {
        const ids = marcas.map((m) => m.id)
        const espelho = await db.execute(sql`
          WITH alvo AS (SELECT * FROM jsonb_to_recordset(${JSON.stringify(mudou)}::jsonb) AS x(lead_id uuid, tag_id uuid, fato text, so_anota boolean)),
          tira AS (
            DELETE FROM lead_tags lt USING alvo a
             WHERE lt.lead_id = a.lead_id AND NOT a.so_anota
               AND lt.tag_id = ANY(${sql.raw(`ARRAY[${ids.map((i) => `'${i}'`).join(',')}]::uuid[]`)})
               AND lt.tag_id IS DISTINCT FROM a.tag_id
            RETURNING 1),
          poe AS (
            INSERT INTO lead_tags (lead_id, tag_id, organization_id) SELECT lead_id, tag_id, ${org}::uuid FROM alvo
             WHERE tag_id IS NOT NULL AND NOT so_anota
            ON CONFLICT DO NOTHING RETURNING 1),
          anota AS (
            UPDATE leads l SET custom_attributes = coalesce(l.custom_attributes, '{}'::jsonb) || jsonb_build_object('etapa_leads_fato', a.fato)
              FROM alvo a WHERE l.id = a.lead_id
            RETURNING 1)
          SELECT (SELECT count(*) FROM tira)::int AS tirou, (SELECT count(*) FROM poe)::int AS pos, (SELECT count(*) FROM anota)::int AS anotou`)
        const e = (espelho.rows[0] || {}) as { tirou?: number; pos?: number }
        if ((e.tirou || 0) + (e.pos || 0) > 0) mexeu = true
      }
    }

    if (mexeu) await publishEvent(channels.orgLeads(org), events.LEAD_UPDATED, { id: null, funis: true })
    return r
  } finally {
    rodando = false
  }
}
