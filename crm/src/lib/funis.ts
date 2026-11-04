/**
 * OS FUNIS ANDAM SOZINHOS (Pedro, 29/09/2026): "cada tag é uma etapa da
 * pipeline e o lead é movido pelo CRM conforme muda de tag automaticamente".
 *
 * Um funil por número (crm/drizzle/0127). A cada minuto (/api/cron/funis):
 *
 *   WHATSAPP LEADS (8595, funil "WhatsApp Captação") -- os CLIENTES da Nay Leads
 *   (Pedro, 30/10/2026: "o pipeline não tá pegando os leads direitos"). Era o
 *   funil dos donos da campanha de disparo (crm_captacao_funil, 172), que acabou;
 *   as etapas foram renomeadas por ele em 29/10 para o caminho do lead. A etapa
 *   vem de crm_leads_pipeline.foi_ate (o mesmo do PipelineDosLeads), sem quem
 *   crm_leads_pipeline_outros tira (corretor, proprietário, empresa, consultado):
 *   chegou > em atendimento, busca > filtrado, enviados > enviado opção,
 *   visita/confirmada/visitou > visitas, fechou > fechamento. Não cria conversa.
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
import { integrations, leadStageHistory } from '@/lib/schema'
import { naydb } from '@/lib/nayDisparo'
import { corretoresDaCaptacao } from '@/app/api/captacao/donos/route'
import { telefoneCanonico, telefoneVariantes } from '@/lib/leadSources'
import { PIPELINE_DA_LINHA } from '@/lib/etapaDaLinha'
import { publishEvent, channels, events } from '@/lib/realtime'

const ETAPAS_DA_NAY = ['Identificação', 'Recebeu imóvel', 'Agendamento de visita']
// 431: o cadastro de imóvel pelo WhatsApp (nay-cadastro), a última etapa do funil da Parceria
const CADASTRANDO = 'Cadastrando'
// foi_ate (crm_leads_pipeline) -> etapa do funil da Leads, pelo nome que o Pedro deu em 29/10
const ETAPA_DO_LEAD: Record<string, string> = {
  chegou: 'em atendimento', busca: 'filtrado', enviados: 'enviado opção',
  visita: 'visitas', confirmada: 'visitas', visitou: 'visitas', fechou: 'fechamento',
}
// os clientes que entram: os chegados nos últimos 90 dias
const DIAS_DO_FUNIL_DA_LEADS = 90

export interface ResultadoDosFunis {
  captacao: { naNay: number; movidos: number; semConversa: number }
  parceria: { naNay: number; movidos: number; semConversa: number; ficouNaEquipe: number }
}

type LeadDoFunil = { id: string; phone: string | null; stage_id: string | null; custom_attributes: Record<string, any> | null }

let rodando = false

export async function sincronizarFunis(org: string): Promise<ResultadoDosFunis | null> {
  if (rodando) return null
  rodando = true
  try {
    const r: ResultadoDosFunis = {
      captacao: { naNay: 0, movidos: 0, semConversa: 0 },
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

    // a etapa da Leads pelo nome que está na tela, sem caixa nem espaço sobrando ("filtrado " tem um espaço no fim)
    const solto = (s: string | null) => String(s || '').trim().toLowerCase()
    const etapaSolta = (pipeline: string, nome: string) =>
      (etapas.rows as Etapa[]).find((e) => e.pipeline === pipeline && (solto(e.name) === solto(nome) || solto(e.nome_original) === solto(nome)))?.id ?? null

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
    // ── WhatsApp Leads (8595): os clientes da Nay Leads ──
    const linhaCaptacao = linhaDe('whatsapp_zapi_captacao')
    const funilCaptacao = PIPELINE_DA_LINHA.whatsapp_zapi_captacao
    if (linhaCaptacao && etapaSolta(funilCaptacao, ETAPA_DO_LEAD.chegou)) {
      const janela = `(now() AT TIME ZONE 'America/Manaus')::date - ${DIAS_DO_FUNIL_DA_LEADS}, (now() AT TIME ZONE 'America/Manaus')::date`
      const [clientes, outros] = await Promise.all([
        naydb().query(`SELECT telefone, foi_ate FROM crm_leads_pipeline(${janela})`),
        naydb().query(`SELECT fone8 FROM crm_leads_pipeline_outros(${janela})`),
      ])
      const fim8 = (t: unknown) => String(t || '').replace(/\D/g, '').slice(-8)
      const naoELead = new Set((outros.rows as Array<{ fone8: string | null }>).map((o) => fim8(o.fone8)).filter(Boolean))
      const doBanco = await db.execute(sql`
        SELECT id, phone, stage_id, custom_attributes FROM leads
         WHERE organization_id = ${org} AND integration_id = ${linhaCaptacao} AND deleted_at IS NULL AND NOT coalesce(is_group, false)`)
      const porTelefone = new Map<string, LeadDoFunil>()
      for (const l of doBanco.rows as LeadDoFunil[]) if (l.phone) porTelefone.set(l.phone, l)

      const noFunil = new Set<string>()
      const vistos = new Set<string>()
      // a função vem do mais novo para o mais velho: o mesmo telefone duas vezes vale a conversa mais recente
      for (const c of clientes.rows as Array<{ telefone: string; foi_ate: string }>) {
        const f8 = fim8(c.telefone)
        if (!f8 || vistos.has(f8) || naoELead.has(f8)) continue
        vistos.add(f8)
        const nome = ETAPA_DO_LEAD[c.foi_ate]
        const etapa = nome ? etapaSolta(funilCaptacao, nome) : null
        if (!nome || !etapa) continue
        r.captacao.naNay++
        const lead = telefoneVariantes(telefoneCanonico(c.telefone) || c.telefone).map((f) => porTelefone.get(f)).find(Boolean)
        if (!lead) { r.captacao.semConversa++; continue }
        noFunil.add(lead.id)
        if (lead.custom_attributes?.funil_auto === nome) continue      // arrastado à mão fica até a etapa da Nay mudar
        if (lead.stage_id !== etapa) {
          await mover(lead, etapa, nome)
          r.captacao.movidos++
        } else {
          await lembrar(lead, nome)
        }
      }

      /* os donos da campanha de disparo antiga (funil_auto Não respondeu, Respondeu, Disponível, Alugado, Vendido,
         Mandou os dados) saem do funil; a etapa em que estavam fica em custom_attributes.etapa_da_campanha */
      const DA_CAMPANHA = new Set(['Não respondeu', 'Respondeu', 'Disponível', 'Alugado', 'Vendido', 'Mandou os dados'])
      for (const lead of doBanco.rows as LeadDoFunil[]) {
        if (!lead.stage_id || noFunil.has(lead.id) || !DA_CAMPANHA.has(String(lead.custom_attributes?.funil_auto || ''))) continue
        await db.execute(sql`
          UPDATE leads SET stage_id = NULL, updated_at = now(),
                 custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                   || jsonb_build_object('funil_auto', 'saiu_da_campanha', 'etapa_da_campanha', ${String(lead.custom_attributes?.funil_auto)}::text)
           WHERE id = ${lead.id}`)
        await db.insert(leadStageHistory).values({
          organizationId: org, leadId: lead.id, fromStageId: lead.stage_id, toStageId: null, movedByMemberId: null, movedAt: new Date(),
        })
        r.captacao.movidos++
        mexeu = true
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
      const emCadastro = new Set<string>()
      for (const linha of rows as Array<{ telefone: string | null; lid: string | null; etapa: string }>) {
        const etapa = etapaDe(funilParceria, linha.etapa)
        if (!etapa) continue
        const lead = (linha.telefone ? telefoneVariantes(linha.telefone).map((f) => porTelefone.get(f)).find(Boolean) : undefined)
          ?? (linha.lid ? porLid.get(linha.lid) : undefined)
        if (!lead) { r.parceria.semConversa++; continue }
        /* CADASTRANDO (Pedro, 20/10/2026, 431): a Nay do cadastro está perguntando a ele sobre um imóvel. Passa na frente
           de qualquer etapa (da Nay ou da equipe) e guarda onde o card estava, para devolver quando o cadastro acabar. */
        if (linha.etapa === CADASTRANDO) {
          emCadastro.add(lead.id)
          if (lead.stage_id !== etapa) {
            await db.execute(sql`
              UPDATE leads SET custom_attributes = coalesce(custom_attributes, '{}'::jsonb)
                     || jsonb_build_object('antes_do_cadastro', ${lead.stage_id ?? ''}::text)
               WHERE id = ${lead.id}`)
            await mover(lead, etapa, CADASTRANDO)
            r.parceria.movidos++
          }
          continue
        }
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
      // o cadastro acabou: o card volta para a etapa em que estava antes (ou sai do funil, se não estava em nenhuma)
      const etapaCadastrando = etapaDe(funilParceria, CADASTRANDO)
      for (const lead of doBanco.rows as LeadDoFunil[]) {
        if (!etapaCadastrando || lead.stage_id !== etapaCadastrando || emCadastro.has(lead.id)) continue
        if (lead.custom_attributes?.funil_auto !== CADASTRANDO) continue      // quem a equipe pôs em Cadastrando fica
        const antes = String(lead.custom_attributes?.antes_do_cadastro || '') || null
        await db.execute(sql`
          UPDATE leads SET stage_id = ${antes}, updated_at = now(),
                 custom_attributes = (coalesce(custom_attributes, '{}'::jsonb) - 'antes_do_cadastro')
                   || jsonb_build_object('funil_auto', 'saiu_do_cadastro')
           WHERE id = ${lead.id}`)
        if (antes) {
          await db.insert(leadStageHistory).values({
            organizationId: org, leadId: lead.id, fromStageId: lead.stage_id, toStageId: antes, movedByMemberId: null, movedAt: new Date(),
          })
        }
        r.parceria.movidos++
        mexeu = true
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
      const [clientes, donosDaCampanha, corretores] = await Promise.all([
        naydb().query('SELECT telefone, etapa FROM crm_olx_clientes_etapas()'),
        naydb().query('SELECT telefone FROM crm_captacao_donos()'),
        corretoresDaCaptacao(),
      ])
      const fim8 = (t: unknown) => String(t || '').replace(/\D/g, '').slice(-8)
      const etapaPorFim = new Map<string, string>()
      /* 04/11 (Pedro: "revisar todas as tags do CRM e tirar os proprietários falsos"): a etiqueta Proprietários ia para todo
         dono da campanha, inclusive o corretor que a campanha procurou como se fosse dono (Moacy, Sarah, Davi Izel, Marcia...),
         e para o CLIENTE na etapa 'proprietarios' da Nay Leads (que é "combinando com o proprietário", não ser dono). Agora:
         corretor não ganha; a etapa do cliente 'proprietarios' não vira essa etiqueta */
      for (const d of donosDaCampanha.rows as Array<{ telefone: string }>) {
        if (fim8(d.telefone).length === 8 && !corretores.has(fim8(d.telefone))) etapaPorFim.set(fim8(d.telefone), 'proprietarios')
      }
      for (const c of clientes.rows as Array<{ telefone: string; etapa: string }>) {
        if (fim8(c.telefone).length === 8 && c.etapa !== 'proprietarios') etapaPorFim.set(fim8(c.telefone), c.etapa)
      }
      const conversas = (await db.execute(sql`
        SELECT l.id::text, l.phone, l.custom_attributes->>'etapa_leads_fato' AS antes, l.custom_attributes->>'tipo_contato' AS tipo,
               EXISTS (SELECT 1 FROM lead_tags lt WHERE lt.lead_id = l.id
                          AND lt.tag_id = ANY(${sql.raw(`ARRAY[${marcas.map((m) => `'${m.id}'`).join(',')}]::uuid[]`)})) AS tem_etapa
          FROM leads l
         WHERE l.organization_id = ${org} AND l.integration_id = ${linhaLeads} AND l.deleted_at IS NULL AND NOT coalesce(l.is_group, false)`))
        .rows as Array<{ id: string; phone: string | null; antes: string | null; tem_etapa: boolean; tipo: string | null }>
      /* só quem mudou de etapa desde o último espelho. Sem anotação (a 1ª vez, ou alguém regravou o custom_attributes
         inteiro): quem já tem uma das quatro só ganha a anotação, para não desfazer o que foi posto à mão. */
      const mudou = conversas
        .map((l) => {
          const e = etapaPorFim.get(fim8(l.phone)) || ''
          // 04/11: o tipo escolhido à mão (corretor, equipe, cliente...) vence: não é dono
          const fato = ETAPA_PARA_ETIQUETA[e] && !(e === 'proprietarios' && l.tipo && l.tipo !== 'proprietario') ? e : ''
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
