// Aplica drizzle/0108_orders_cash_settled.sql direto no Neon.
// Uso: node scripts/apply-0108.mjs
import { config } from 'dotenv'
import { neon } from '@neondatabase/serverless'
import { readFileSync } from 'node:fs'

config({ path: new URL('../.env.local', import.meta.url).pathname })

const url = process.env.DATABASE_URL || process.env.whatsappnaturabelas_DATABASE_URL
if (!url) {
  console.error('DATABASE_URL não encontrada em .env.local')
  process.exit(1)
}

const sql = neon(url)
const file = readFileSync(new URL('../drizzle/0108_orders_cash_settled.sql', import.meta.url), 'utf8')
const withoutComments = file.split('\n').filter(line => !line.trim().startsWith('--')).join('\n')
const statements = withoutComments.split(';').map(s => s.trim()).filter(s => s.length > 0)

for (const stmt of statements) {
  console.log(`Executando: ${stmt.slice(0, 80)}...`)
  await sql(stmt)
}
console.log('Migration aplicada com sucesso.')
