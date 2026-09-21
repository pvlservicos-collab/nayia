/**
 * Cria (ou atualiza) o funil "Teste A/B/C — não terminou a agenda".
 *
 *   node --env-file=.env.local scripts/criar-funil-teste-agenda.mjs
 *
 * O fluxo, de ponta a ponta:
 *
 *   gatilho (lead novo da Agenda)
 *        └── condição "preencheu o formulário do fim da agenda?" — espera 30 min
 *              ├── sim  → fim            (cancelado: a pessoa se cadastrou)
 *              └── não  → mensagem A/B/C → fim
 *
 * A condição é o que cancela sozinho: quem preenche durante os 30 minutos sai
 * pelo ramo "sim" e não recebe nada. Quem não preenche cai no "não" e recebe
 * UMA das três versões, sorteada — é o teste que diz qual texto faz mais gente
 * responder (Métricas, dentro do fluxo).
 *
 * Roda quantas vezes quiser: se o funil já existe, os blocos são refeitos e o
 * histórico de execuções continua intacto.
 */
import pg from 'pg'

const ORG = process.env.ORG_ID || '4bf15db2-4f23-463f-b970-1737dd75688d'
const NOME = 'Teste A/B/C — não terminou a agenda'
const GATILHO = 'lead_agenda_ascensao'
const ESPERA_MINUTOS = 30

/*
 * Os três textos. Mesma promessa, jeitos diferentes de pedir resposta:
 *   A — direto e curto;
 *   B — pergunta o que atrapalhou (convida a contar o motivo);
 *   C — oferece ajuda pra terminar (tira o trabalho da pessoa).
 * Mude à vontade aqui ou pelo editor do fluxo; o que importa é uma variável só
 * por vez, senão não dá pra saber o que causou a diferença.
 */
const VARIANTES = [
  {
    id: 'A',
    texto:
      'Oi {nome}! Aqui é a Michele da equipe do Augusto Titã 😁\n\n' +
      'Vi que você montou sua agenda mas não terminou a aplicação para a sessão de avaliação.\n' +
      'Quer que eu garanta sua vaga?',
  },
  {
    id: 'B',
    texto:
      'Oi {nome}! Aqui é a Michele da equipe do Augusto Titã 😁\n\n' +
      'Você chegou até o fim da agenda e parou na aplicação — o que te fez parar ali?\n' +
      'Me conta rapidinho que eu te ajudo.',
  },
  {
    id: 'C',
    texto:
      'Oi {nome}! Aqui é a Michele da equipe do Augusto Titã 😁\n\n' +
      'Sua agenda ficou pronta, só falta a aplicação para a sessão de avaliação.\n' +
      'Se preferir, eu termino por aqui com você em 2 minutos. Posso?',
  },
]

const c = new pg.Client({ connectionString: process.env.DATABASE_URL })
await c.connect()

try {
  await c.query('BEGIN')

  let [funil] = (
    await c.query(
      `SELECT id FROM message_funnels WHERE organization_id = $1 AND name = $2 AND deleted_at IS NULL`,
      [ORG, NOME]
    )
  ).rows

  if (!funil) {
    ;[funil] = (
      await c.query(
        `INSERT INTO message_funnels (organization_id, name, trigger, is_active)
         VALUES ($1, $2, $3, false) RETURNING id`,
        [ORG, NOME, GATILHO]
      )
    ).rows
    console.log('funil criado:', funil.id)
  } else {
    // Refaz os blocos: as execuções apontam pra blocos por id, e as antigas já
    // terminaram. `ON DELETE CASCADE` leva as conexões junto.
    await c.query(`DELETE FROM funnel_blocks WHERE funnel_id = $1`, [funil.id])
    console.log('funil já existia, blocos refeitos:', funil.id)
  }

  const bloco = async (tipo, config, x, y) => {
    const { rows } = await c.query(
      `INSERT INTO funnel_blocks (funnel_id, type, config, position_x, position_y)
       VALUES ($1, $2, $3::jsonb, $4, $5) RETURNING id`,
      [funil.id, tipo, JSON.stringify(config), x, y]
    )
    return rows[0].id
  }
  const liga = (de, para, ramo = 'default') =>
    c.query(
      `INSERT INTO funnel_connections (funnel_id, source_block_id, target_block_id, branch)
       VALUES ($1, $2, $3, $4)`,
      [funil.id, de, para, ramo]
    )

  const gatilho = await bloco('trigger', { label: 'Lead novo da Agenda' }, 80, 200)
  const condicao = await bloco(
    'condition',
    {
      conditionType: 'formulario_agenda',
      label: 'Preencheu o formulário do fim da agenda?',
      value: ESPERA_MINUTOS,
      unit: 'minutes',
    },
    360,
    200
  )
  const mensagem = await bloco(
    'message',
    { label: 'Mensagem A/B/C', variantes: VARIANTES, text: VARIANTES[0].texto },
    660,
    320
  )
  const fimCadastrou = await bloco('end', { label: 'Cadastrou — não envia' }, 660, 90)
  const fimEnviou = await bloco('end', { label: 'Fim' }, 960, 320)

  await liga(gatilho, condicao)
  await liga(condicao, fimCadastrou, 'yes') // preencheu: cancela
  await liga(condicao, mensagem, 'no') // não preencheu: manda o teste
  await liga(mensagem, fimEnviou)

  await c.query('COMMIT')

  const ativo = (await c.query(`SELECT is_active FROM message_funnels WHERE id = $1`, [funil.id])).rows[0]
  console.log('\nPronto. Blocos:', { gatilho, condicao, mensagem, fimCadastrou, fimEnviou })
  console.log('Ativo?', ativo.is_active ? 'SIM' : 'NÃO — ligue no painel quando quiser começar o teste')
} catch (err) {
  await c.query('ROLLBACK')
  throw err
} finally {
  await c.end()
}
