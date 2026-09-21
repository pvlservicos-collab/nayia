// Registra um token de API (tabela api_tokens) pra uma organização.
//
// Uso:
//   node scripts/create-api-token.mjs "Agenda Ascensão"            # gera e imprime
//   node scripts/create-api-token.mjs "Nome" --token atl_abc...    # registra um valor já escolhido
//   node scripts/create-api-token.mjs "Nome" --org <uuid>          # escolhe a organização
//
// Sem --org, usa a única organização existente; se houver mais de uma, lista os
// ids e para, em vez de adivinhar.
//
// O banco guarda só o SHA-256. O valor em claro é impresso uma única vez aqui e
// não fica salvo em lugar nenhum — se perder, gere outro e revogue este.
// Mesmo esquema de token da tela Configurações → Organização; este script existe
// pro caso de precisar de uma chave sem passar pela interface (ex: antes do
// primeiro login, ou pra um integrador externo).
import { config } from 'dotenv'
import pg from 'pg'
import { createHash, randomBytes } from 'node:crypto'
import { fileURLToPath } from 'node:url'

config({ path: fileURLToPath(new URL('../.env.local', import.meta.url)) })

const connectionString = process.env.DATABASE_URL
if (!connectionString) {
  console.error('DATABASE_URL não encontrada em .env.local')
  process.exit(1)
}

// Percorre os argumentos uma vez separando flags (--x valor) de posicionais, em
// vez de procurar por índice — assim um nome que por acaso seja igual ao valor
// de uma flag não confunde o parser.
const argv = process.argv.slice(2)
const flags = {}
const positionals = []
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) {
    flags[argv[i].slice(2)] = argv[i + 1] ?? null
    i++
  } else {
    positionals.push(argv[i])
  }
}
const flag = (name) => flags[name] ?? null

const name = positionals[0]
if (!name) {
  console.error('Informe um nome. Ex: node scripts/create-api-token.mjs "Agenda Ascensão"')
  process.exit(1)
}

const providedToken = flag('token')
if (providedToken && !providedToken.startsWith('atl_')) {
  // authenticateRequest() só trata como token de API o que começa com atl_;
  // qualquer outra coisa cai no caminho do JWT e falha com "JWT inválido".
  console.error('O token precisa começar com "atl_" — é assim que a API o distingue de um JWT de sessão.')
  process.exit(1)
}

const token = providedToken || `atl_${randomBytes(32).toString('hex')}`
const tokenHash = createHash('sha256').update(token).digest('hex')

const client = new pg.Client({ connectionString })
await client.connect()

try {
  let organizationId = flag('org')
  if (!organizationId) {
    const { rows } = await client.query('SELECT id, name FROM organizations ORDER BY created_at LIMIT 10')
    if (rows.length === 0) {
      console.error('Nenhuma organização no banco.')
      process.exit(1)
    }
    if (rows.length > 1) {
      console.error('Mais de uma organização — escolha com --org <uuid>:')
      for (const r of rows) console.error(`  ${r.id}  ${r.name}`)
      process.exit(1)
    }
    organizationId = rows[0].id
  }

  const { rows } = await client.query(
    'INSERT INTO api_tokens (organization_id, name, token_hash) VALUES ($1, $2, $3) RETURNING id, created_at',
    [organizationId, name, tokenHash]
  )

  console.log('')
  console.log('Token criado. Copie agora — ele não pode ser recuperado depois.')
  console.log('')
  console.log(`  organização : ${organizationId}`)
  console.log(`  nome        : ${name}`)
  console.log(`  id          : ${rows[0].id}`)
  console.log(`  token       : ${token}`)
  console.log('')
  console.log('Uso:  Authorization: Bearer ' + token)
  console.log('')
} catch (err) {
  console.error('Falhou:', err.message)
  process.exitCode = 1
} finally {
  await client.end()
}
