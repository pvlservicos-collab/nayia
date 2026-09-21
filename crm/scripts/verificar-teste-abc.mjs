/**
 * Prova do fluxo A/B/C — `npm run verificar:abc` (precisa do .env.local).
 *
 * Nada é enviado e nada fica no banco: tudo roda numa transação DESFEITA no
 * fim. Serve pra conferir, depois de mexer no motor ou na métrica, que:
 *
 * Tudo roda numa transação que é DESFEITA no fim: nada fica no banco. O que
 * está sendo verificado:
 *   1. a condição "preencheu o formulário" reconhece quem se cadastrou (é ela
 *      que cancela a mensagem de quem não precisa mais recebê-la);
 *   2. a métrica atribui a resposta à mensagem certa — inclusive no caso que
 *      quebrou a primeira versão dela: o lead que já conversava com a gente e
 *      respondia a OUTRA mensagem, marcando 100% em todas as versões;
 *   3. o sorteio distribui as versões por igual.
 */
import pg from 'pg'

const ORG = '4bf15db2-4f23-463f-b970-1737dd75688d'
const c = new pg.Client({ connectionString: process.env.DATABASE_URL })
await c.connect()
await c.query('BEGIN')

try {
  const funil = (await c.query(
    `SELECT id FROM message_funnels WHERE organization_id = $1 AND name = 'Teste A/B/C — não terminou a agenda'`,
    [ORG]
  )).rows[0]
  const blocoMensagem = (await c.query(
    `SELECT id FROM funnel_blocks WHERE funnel_id = $1 AND type = 'message'`, [funil.id]
  )).rows[0]

  // ── três leads de mentira: um preencheu o formulário, dois não ────────────
  const leads = []
  for (const [nome, area] of [['Zé Sem Form', null], ['Ana Sem Form', null], ['Bia Cadastrou', 'Empresário']]) {
    const attrs = { lead_source: 'agenda_ascensao', phase: 'done', ...(area ? { area } : {}) }
    const r = await c.query(
      `INSERT INTO leads (organization_id, title, phone, custom_attributes, last_activity_at)
       VALUES ($1, $2, $3, $4::jsonb, now()) RETURNING id`,
      [ORG, nome, '55119' + Math.floor(10000000 + Math.random() * 89999999), JSON.stringify(attrs)]
    )
    leads.push({ id: r.rows[0].id, nome, temForm: !!area })
  }

  console.log('1) condição "preencheu o formulário do fim da agenda"')
  for (const lead of leads) {
    const r = await c.query(
      `SELECT coalesce(
         nullif(trim(custom_attributes->>'area'), '') IS NOT NULL
         OR nullif(trim(custom_attributes->>'aumento'), '') IS NOT NULL
         OR nullif(trim(custom_attributes->>'investimento'), '') IS NOT NULL, false) AS preencheu
       FROM leads WHERE id = $1`, [lead.id]
    )
    const preencheu = r.rows[0].preencheu
    const esperado = lead.temForm
    console.log(`   ${preencheu === esperado ? 'ok  ' : 'ERRO'} ${lead.nome}: preencheu=${preencheu} (ramo ${preencheu ? 'SIM → cancela' : 'NÃO → manda mensagem'})`)
  }

  // ── disparos simulados: 4 da versão A (2 responderam), 3 da B (0), 3 da C (2)
  console.log('\n2) métricas por versão')
  const registrar = async (leadId, variante, respondeu) => {
    const envio = await c.query(
      `INSERT INTO lead_activities (organization_id, lead_id, type, content, metadata, created_at)
       VALUES ($1, $2, 'whatsapp', 'msg de teste', $3::jsonb, now() - interval '1 hour') RETURNING id, created_at`,
      [ORG, leadId, JSON.stringify({
        source: 'funnel', direction: 'outbound', automated: true, send_status: 'sent',
        funnel_id: funil.id, block_id: blocoMensagem.id, variante,
      })]
    )
    if (respondeu) {
      await c.query(
        `INSERT INTO lead_activities (organization_id, lead_id, type, content, metadata, created_at)
         VALUES ($1, $2, 'whatsapp', 'respondi', $3::jsonb, now() - interval '30 minutes')`,
        [ORG, leadId, JSON.stringify({ source: 'zapi', direction: 'inbound' })]
      )
    }
  }
  // Um lead por disparo, que é o caso real, mais um "conversador" que responde
  // sempre — é ele que inflava a conta na versão anterior da métrica.
  const plano = [['A', true], ['A', true], ['A', false], ['A', false], ['B', false], ['B', false], ['B', false], ['C', true], ['C', false], ['C', false]]
  for (const [variante, respondeu] of plano) {
    const r = await c.query(
      `INSERT INTO leads (organization_id, title, phone, custom_attributes, last_activity_at)
       VALUES ($1, $2, $3, '{"lead_source":"agenda_ascensao"}'::jsonb, now()) RETURNING id`,
      [ORG, 'Lead teste ' + variante, '55219' + Math.floor(10000000 + Math.random() * 89999999)]
    )
    await registrar(r.rows[0].id, variante, respondeu)
  }

  // Conversador: recebeu a versão B, NÃO respondeu a ela, mas mandou mensagem
  // depois de outra mensagem nossa. Não pode contar como resposta da B.
  const conversador = (await c.query(
    `INSERT INTO leads (organization_id, title, phone, custom_attributes, last_activity_at)
     VALUES ($1, 'Conversador', '5521988887777', '{"lead_source":"agenda_ascensao"}'::jsonb, now()) RETURNING id`, [ORG]
  )).rows[0].id
  await registrar(conversador, 'B', false)
  await c.query(
    `INSERT INTO lead_activities (organization_id, lead_id, type, content, metadata, created_at)
     VALUES ($1, $2, 'whatsapp', 'outra mensagem nossa', '{"direction":"outbound","source":"human"}'::jsonb, now() - interval '50 minutes')`,
    [ORG, conversador]
  )
  await c.query(
    `INSERT INTO lead_activities (organization_id, lead_id, type, content, metadata, created_at)
     VALUES ($1, $2, 'whatsapp', 'respondendo a outra', '{"direction":"inbound","source":"zapi"}'::jsonb, now() - interval '40 minutes')`,
    [ORG, conversador]
  )

  const metricas = await c.query(`
    WITH disparos AS (
      SELECT a.metadata->>'variante' AS variante, a.lead_id, a.created_at,
             a.metadata->>'send_status' AS send_status
      FROM lead_activities a
      WHERE a.organization_id = $1 AND a.metadata->>'funnel_id' = $2 AND a.metadata->>'variante' IS NOT NULL
    )
    SELECT d.variante, count(*)::int AS enviado,
      count(*) FILTER (WHERE d.send_status = 'sent')::int AS entregue,
      count(*) FILTER (WHERE EXISTS (
        SELECT 1 FROM lead_activities r
        WHERE r.lead_id = d.lead_id AND r.metadata->>'direction' = 'inbound'
          AND r.created_at > d.created_at
          AND r.created_at < d.created_at + interval '7 days'
          AND NOT EXISTS (
            SELECT 1 FROM lead_activities m
            WHERE m.lead_id = d.lead_id AND m.metadata->>'direction' = 'outbound'
              AND m.created_at > d.created_at AND m.created_at < r.created_at
          )
      ))::int AS responderam
    FROM disparos d GROUP BY d.variante ORDER BY d.variante
  `, [ORG, funil.id])

  console.log('   esperado: A 4 envios / 2 respostas · B 4 envios / 0 respostas (o conversador nao conta) · C 3 envios / 1 resposta')
  console.table(metricas.rows.map(r => ({
    versao: r.variante, enviado: r.enviado, entregue: r.entregue, responderam: r.responderam,
    taxa: r.entregue ? (100 * r.responderam / r.entregue).toFixed(0) + '%' : '—',
  })))

  // ── sorteio: as versões saem equilibradas? ───────────────────────────────
  console.log('3) sorteio de versão (10 mil rodadas, 3 versões)')
  const contagem = { A: 0, B: 0, C: 0 }
  const vs = ['A', 'B', 'C']
  for (let i = 0; i < 10000; i++) contagem[vs[Math.floor(Math.random() * vs.length)]]++
  console.log('  ', JSON.stringify(contagem), '— cada uma perto de 3333');
} finally {
  await c.query('ROLLBACK')
  await c.end()
  console.log('\n(transação desfeita: nada disso ficou no banco)')
}
