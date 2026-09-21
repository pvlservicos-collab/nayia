/**
 * Cria a organizacao e o usuario unico da casa. Roda UMA vez, depois das
 * migracoes. E idempotente: rodar de novo nao duplica nada.
 *
 *   node scripts/seed-inicial.mjs
 *
 * O usuario existe porque o app inteiro pergunta "quem e voce e de qual
 * organizacao?" -- 17 arquivos chamam auth(). Sem sessao real as telas nao
 * ficam vazias, elas mostram dado de exemplo (o middleware do projeto modelo
 * registra que foi isso que aconteceu da ultima vez). Entao a sessao e real;
 * o que sai e a tela de login, via /api/auth/entrar.
 *
 * O papel nasce com permissions {"*": true} porque e assim que o fluxo padrao
 * do modelo (create-workspace) cria o Admin -- e e o que faz o menu aparecer
 * inteiro no Navbar.
 */
import pg from 'pg'
import bcrypt from 'bcryptjs'

const { Client } = pg

const EMAIL = (process.env.LOGIN_AUTOMATICO_EMAIL || '').toLowerCase().trim()
const SENHA = process.env.LOGIN_AUTOMATICO_SENHA || ''
const ORG = process.env.ORG_NOME || 'Imob Easy'
const NOME = process.env.LOGIN_AUTOMATICO_NOME || 'Imob Easy'

if (!EMAIL || !SENHA) {
  console.error('ERRO: LOGIN_AUTOMATICO_EMAIL e LOGIN_AUTOMATICO_SENHA precisam estar no .env')
  process.exit(1)
}

const db = new Client({ connectionString: process.env.DATABASE_URL })
await db.connect()

try {
  await db.query('BEGIN')

  // 1. a organizacao
  let { rows: [org] } = await db.query(
    'SELECT id, name FROM organizations WHERE name = $1 AND deleted_at IS NULL LIMIT 1', [ORG])
  if (!org) {
    ({ rows: [org] } = await db.query(
      `INSERT INTO organizations (name, timezone, subscription_status)
       VALUES ($1, 'America/Manaus', 'active') RETURNING id, name`, [ORG]))
    console.log('organizacao criada:', org.name, org.id)
  } else {
    console.log('organizacao ja existia:', org.name, org.id)
  }

  // 2. o papel com acesso total
  let { rows: [papel] } = await db.query(
    'SELECT id FROM organization_roles WHERE organization_id = $1 AND name = $2 LIMIT 1',
    [org.id, 'Admin'])
  if (!papel) {
    ({ rows: [papel] } = await db.query(
      `INSERT INTO organization_roles (organization_id, name, permissions)
       VALUES ($1, 'Admin', '{"*": true}'::jsonb) RETURNING id`, [org.id]))
    console.log('papel Admin criado:', papel.id)
  } else {
    await db.query(`UPDATE organization_roles SET permissions = '{"*": true}'::jsonb WHERE id = $1`, [papel.id])
    console.log('papel Admin ja existia:', papel.id)
  }

  // 3. o usuario
  const hash = await bcrypt.hash(SENHA, 10)
  let { rows: [user] } = await db.query('SELECT id FROM users WHERE email = $1 LIMIT 1', [EMAIL])
  if (!user) {
    ({ rows: [user] } = await db.query(
      'INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id', [EMAIL, hash]))
    console.log('usuario criado:', EMAIL, user.id)
  } else {
    // A senha do .env e a fonte da verdade: se ela mudou, o hash acompanha,
    // senao a entrada automatica para de funcionar sem dizer por que.
    await db.query('UPDATE users SET password_hash = $1 WHERE id = $2', [hash, user.id])
    console.log('usuario ja existia, senha sincronizada:', EMAIL, user.id)
  }

  // 4. o perfil
  await db.query(
    `INSERT INTO profiles (id, full_name, timezone, is_superadmin, onboarding_completed)
     VALUES ($1, $2, 'America/Manaus', true, true)
     ON CONFLICT (id) DO UPDATE SET full_name = EXCLUDED.full_name, is_superadmin = true`,
    [user.id, NOME])

  // 5. o vinculo
  const { rows: [vinculo] } = await db.query(
    'SELECT id FROM organization_members WHERE organization_id = $1 AND user_id = $2 LIMIT 1',
    [org.id, user.id])
  if (!vinculo) {
    await db.query(
      `INSERT INTO organization_members (organization_id, user_id, role_id, status)
       VALUES ($1, $2, $3, 'active')`, [org.id, user.id, papel.id])
    console.log('vinculo criado')
  } else {
    await db.query(`UPDATE organization_members SET role_id = $1, status = 'active' WHERE id = $2`,
      [papel.id, vinculo.id])
    console.log('vinculo ja existia')
  }

  await db.query('COMMIT')
  console.log('\nPRONTO. Organizacao', org.id, '| usuario', EMAIL)
} catch (e) {
  await db.query('ROLLBACK')
  console.error('FALHOU:', e.message)
  process.exit(1)
} finally {
  await db.end()
}
