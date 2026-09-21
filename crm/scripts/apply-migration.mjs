// Aplica um arquivo de drizzle/ no Postgres.
// Uso: node scripts/apply-migration.mjs 0119_lead_source_submissions.sql
//
// Usa `pg` (e não @neondatabase/serverless como os scripts apply-01xx antigos):
// o banco saiu do Neon e hoje é Postgres na VPS, alcançado localmente pelo túnel
// SSH do scripts/vps-tunnel.mjs. Suba o túnel antes de rodar isto.
import { config } from 'dotenv'
import pg from 'pg'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// new URL(...).pathname NÃO decodifica %20 — esta pasta tem espaço no nome
// ("TITÃ 2026"). fileURLToPath decodifica corretamente.
config({ path: fileURLToPath(new URL('../.env.local', import.meta.url)) })

const connectionString = process.env.DATABASE_URL
if (!connectionString) {
  console.error('DATABASE_URL não encontrada em .env.local')
  process.exit(1)
}

const fileName = process.argv[2]
if (!fileName) {
  console.error('Informe o arquivo. Ex: node scripts/apply-migration.mjs 0119_lead_source_submissions.sql')
  process.exit(1)
}

const path = fileURLToPath(new URL(`../drizzle/${fileName}`, import.meta.url))
const sqlText = readFileSync(path, 'utf8')

// ALTER TYPE ... ADD VALUE não pode ser usado na mesma transação que o cria, e
// em Postgres < 12 nem roda dentro de transação. Nesse caso vai statement a
// statement; no resto, tudo numa transação só (ou aplica inteiro, ou nada).
const hasEnumChange = /ALTER\s+TYPE[\s\S]*?ADD\s+VALUE/i.test(sqlText)

const client = new pg.Client({ connectionString })
await client.connect()

try {
  if (hasEnumChange) {
    const statements = sqlText
      .split('\n')
      .filter((line) => !line.trim().startsWith('--'))
      .join('\n')
      .split(';')
      .map((s) => s.trim())
      .filter(Boolean)
    for (const statement of statements) {
      console.log(`  ${statement.slice(0, 70)}…`)
      await client.query(statement)
    }
  } else {
    await client.query('BEGIN')
    await client.query(sqlText)
    await client.query('COMMIT')
  }
  console.log(`Migration ${fileName} aplicada.`)
} catch (err) {
  if (!hasEnumChange) await client.query('ROLLBACK').catch(() => {})
  console.error('Falhou:', err.message)
  process.exitCode = 1
} finally {
  await client.end()
}
