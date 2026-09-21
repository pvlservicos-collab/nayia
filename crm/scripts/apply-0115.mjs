// Aplica drizzle/0115_profiles_onboarding_completed.sql direto no Neon.
// Uso: node scripts/apply-0115.mjs
import { config } from 'dotenv'
import { neon } from '@neondatabase/serverless'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

// new URL(...).pathname NÃO decodifica %20 — quebra porque esta pasta tem espaço
// no nome ("a VINICIUS WEB FOLEM MIDIA"). fileURLToPath decodifica corretamente.
config({ path: fileURLToPath(new URL('../.env.local', import.meta.url)) })

const url = process.env.DATABASE_URL || process.env.whatsappnaturabelas_DATABASE_URL
if (!url) {
  console.error('DATABASE_URL não encontrada em .env.local')
  process.exit(1)
}

const sql = neon(url)
const file = readFileSync(fileURLToPath(new URL('../drizzle/0115_profiles_onboarding_completed.sql', import.meta.url)), 'utf8')
const withoutComments = file.split('\n').filter(line => !line.trim().startsWith('--')).join('\n')
const statements = withoutComments.split(';').map(s => s.trim()).filter(s => s.length > 0)

for (const stmt of statements) {
  console.log(`Executando: ${stmt.slice(0, 80)}...`)
  await sql(stmt)
}
console.log('Migration aplicada com sucesso.')
