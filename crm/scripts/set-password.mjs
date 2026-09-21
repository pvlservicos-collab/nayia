// Troca a senha de um usuário existente.
//
// Uso:
//   node scripts/set-password.mjs tita "NovaSenha"
//   node scripts/set-password.mjs alguem@dominio.com "NovaSenha"
//
// O seed (seed-workspace.mjs) é idempotente e de propósito NÃO mexe na senha de
// quem já existe — senão reexecutar o seed silenciosamente derrubaria a senha
// que alguém trocou pela tela. Trocar senha é ação à parte, e é este script.
//
// Usa o mesmo bcrypt com 12 rounds do cadastro pela tela (setup-owner), então o
// hash gerado aqui é indistinguível de um criado por lá.
import { config } from 'dotenv'
import pg from 'pg'
import bcrypt from 'bcryptjs'
import { fileURLToPath } from 'node:url'

// new URL(...).pathname NÃO decodifica %20 — esta pasta tem espaço no nome.
config({ path: fileURLToPath(new URL('../.env.local', import.meta.url)), quiet: true })

const connectionString = process.env.DATABASE_URL
if (!connectionString) {
  console.error('DATABASE_URL não encontrada em .env.local')
  process.exit(1)
}

const [login, password] = process.argv.slice(2)
if (!login || !password) {
  console.error('Uso: node scripts/set-password.mjs <usuario-ou-email> "NovaSenha"')
  process.exit(1)
}
if (password.length < 8) {
  console.warn(`AVISO: senha de ${password.length} caracteres. Fácil de quebrar em ataque automatizado.`)
}

const client = new pg.Client({ connectionString })
await client.connect()

try {
  // Mesma normalização do authorize() do NextAuth, senão a senha seria trocada
  // num registro e o login tentaria entrar em outro.
  const normalizado = login.toLowerCase().trim()

  const { rows } = await client.query(
    'SELECT id, email FROM users WHERE email = $1 LIMIT 1',
    [normalizado]
  )
  if (rows.length === 0) {
    console.error(`Usuário "${normalizado}" não existe. Crie com seed-workspace.mjs primeiro.`)
    process.exit(1)
  }

  const passwordHash = await bcrypt.hash(password, 12)
  await client.query('UPDATE users SET password_hash = $1 WHERE id = $2', [passwordHash, rows[0].id])

  // Confere o resultado em vez de confiar no UPDATE — é o mesmo compare que o
  // login vai fazer, então se passar aqui, passa lá.
  const { rows: check } = await client.query('SELECT password_hash FROM users WHERE id = $1', [rows[0].id])
  const confere = await bcrypt.compare(password, check[0].password_hash)

  console.log('')
  console.log(confere ? 'Senha trocada e confirmada.' : 'ERRO: a senha nova não confere após gravar.')
  console.log(`  login : ${rows[0].email}`)
  console.log('')
  if (!confere) process.exitCode = 1
} catch (err) {
  console.error('Falhou:', err.message)
  process.exitCode = 1
} finally {
  await client.end()
}
