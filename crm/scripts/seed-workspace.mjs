// Cria o conteúdo mínimo de um banco vazio: tiers, organização, papéis e a
// conta de acesso (com senha, marcada como superadmin).
//
// Uso:
//   node scripts/seed-workspace.mjs "Nome da Org" email@dominio.com "SenhaForte" "Nome da Pessoa"
//
// Idempotente: o que já existe é reaproveitado, nada é duplicado nem
// sobrescrito. Reexecutar com o mesmo e-mail não troca a senha — para isso,
// use a tela de perfil.
//
// Espelha exatamente o que POST /api/admin/create-workspace e
// POST /api/auth/setup-owner fazem; existe separado porque as duas rotas exigem
// uma sessão que ainda não há como ter num banco recém-criado.
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

const [orgName, email, password, fullName] = process.argv.slice(2)
if (!orgName || !email || !password) {
  console.error('Uso: node scripts/seed-workspace.mjs "Org" email@dominio.com "Senha" "Nome"')
  process.exit(1)
}
if (password.length < 8) {
  // Aviso, e nao bloqueio: este script e ferramenta de dono do sistema, rodada
  // com acesso direto ao banco. Quem o executa ja pode fazer qualquer coisa —
  // impedir aqui so atrapalharia. A regra de 8+ continua valendo no cadastro
  // pela tela (setup-owner), que e por onde passa qualquer outra pessoa.
  console.warn(`AVISO: senha de ${password.length} caracteres. Facil de adivinhar em ataque automatizado.`)
}

const client = new pg.Client({ connectionString })
await client.connect()

async function one(sql, params = []) {
  const { rows } = await client.query(sql, params)
  return rows[0] || null
}

try {
  await client.query('BEGIN')
  const feito = []

  // ── Tier ──
  let tier = await one(`SELECT id FROM tiers WHERE name = 'free' LIMIT 1`)
  if (!tier) {
    tier = await one(
      `INSERT INTO tiers (name, max_users, can_use_custom_fields, permissions)
       VALUES ('free', 5, true, '{}'::jsonb) RETURNING id`
    )
    feito.push('tier "free"')
  }

  // ── Organização ──
  let org = await one(`SELECT id FROM organizations WHERE name = $1 LIMIT 1`, [orgName])
  if (!org) {
    org = await one(
      `INSERT INTO organizations (name, tier_id, timezone)
       VALUES ($1, $2, 'America/Sao_Paulo') RETURNING id`,
      [orgName, tier.id]
    )
    feito.push(`organização "${orgName}"`)
  }

  // ── Papéis (mesmos de create-workspace) ──
  for (const [name, permissions] of [
    ['Admin', { '*': true }],
    ['Agente', { leads: { view: true, edit: true }, chat: { view: true, send: true } }],
  ]) {
    const existe = await one(
      `SELECT id FROM organization_roles WHERE organization_id = $1 AND name = $2 LIMIT 1`,
      [org.id, name]
    )
    if (!existe) {
      await client.query(
        `INSERT INTO organization_roles (organization_id, name, permissions) VALUES ($1, $2, $3)`,
        [org.id, name, JSON.stringify(permissions)]
      )
      feito.push(`papel "${name}"`)
    }
  }
  const adminRole = await one(
    `SELECT id FROM organization_roles WHERE organization_id = $1 AND name = 'Admin' LIMIT 1`,
    [org.id]
  )

  // ── Usuário ──
  const normalizado = email.toLowerCase().trim()
  let user = await one(`SELECT id FROM users WHERE email = $1 LIMIT 1`, [normalizado])
  if (!user) {
    // 12 rounds: o mesmo custo usado em setup-owner, pra o hash daqui ser
    // indistinguível de um criado pela tela.
    const passwordHash = await bcrypt.hash(password, 12)
    user = await one(
      `INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id`,
      [normalizado, passwordHash]
    )
    feito.push(`usuário ${normalizado}`)
  }

  const profile = await one(`SELECT id FROM profiles WHERE id = $1 LIMIT 1`, [user.id])
  if (!profile) {
    // is_superadmin: primeira conta do sistema precisa alcançar o painel /admin.
    await client.query(
      `INSERT INTO profiles (id, full_name, is_superadmin) VALUES ($1, $2, true)`,
      [user.id, fullName || normalizado]
    )
    feito.push('perfil (superadmin)')
  }

  const member = await one(
    `SELECT id FROM organization_members WHERE organization_id = $1 AND user_id = $2 LIMIT 1`,
    [org.id, user.id]
  )
  if (!member) {
    await client.query(
      `INSERT INTO organization_members (organization_id, user_id, role_id, status)
       VALUES ($1, $2, $3, 'active')`,
      [org.id, user.id, adminRole.id]
    )
    feito.push('vínculo com a organização')
  }

  await client.query('COMMIT')

  console.log('')
  console.log(feito.length ? 'Criado: ' + feito.join(', ') : 'Nada a criar — já estava tudo lá.')
  console.log('')
  console.log(`  organização : ${orgName} (${org.id})`)
  console.log(`  login       : ${normalizado}`)
  console.log('')
} catch (err) {
  await client.query('ROLLBACK').catch(() => {})
  console.error('Falhou, nada foi gravado:', err.message)
  process.exitCode = 1
} finally {
  await client.end()
}
