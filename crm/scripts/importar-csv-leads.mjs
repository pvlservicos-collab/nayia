// Importa uma planilha de leads exportada da Agenda para a fonte
// `agenda_antigos` (aba "Agenda — lista antiga" em Configurações → Leads).
//
// Uso:
//   node scripts/importar-csv-leads.mjs "Listas de leads/leads-antigos agenda 0709.csv"
//   node scripts/importar-csv-leads.mjs <arquivo> --dry    (só mostra, não grava)
//
// Idempotente: reexecutar atualiza as linhas pelo ID da planilha em vez de
// duplicar — mesma regra de deduplicação do webhook.
//
// Duas coisas que este script NÃO faz, as duas de propósito:
//
// 1. Não dispara funil de mensagem. É lista histórica: disparar mandaria a
//    mensagem de boas-vindas pra centenas de pessoas cadastradas meses atrás,
//    de uma vez. Quem garante isso é o `agenda_antigos: null` em
//    src/lib/funnel-triggers.ts — aqui a gente nem chama o funil.
//
// 2. Não coloca o lead em etapa do Kanban. O board é sobre o atendimento de
//    agora; a base histórica vive na aba Leads.
import { config } from 'dotenv'
import pg from 'pg'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'

config({ path: fileURLToPath(new URL('../.env.local', import.meta.url)), quiet: true })

const connectionString = process.env.DATABASE_URL
if (!connectionString) {
  console.error('DATABASE_URL não encontrada em .env.local')
  process.exit(1)
}

const arquivo = process.argv[2]
const dryRun = process.argv.includes('--dry')
if (!arquivo) {
  console.error('Uso: node scripts/importar-csv-leads.mjs <arquivo.csv> [--dry]')
  process.exit(1)
}

/**
 * Parser de CSV que respeita aspas.
 *
 * Não dá pra usar split(';'): a exportação tem campos entre aspas com vírgula e
 * parênteses dentro ("09:00–18:00 (Seg,Ter,Qua)"), e aspas duplicadas escapam
 * uma aspa literal. Split simples cortaria no meio desses campos.
 */
function parseCsv(texto, separador = ';') {
  const linhas = []
  let campo = ''
  let linha = []
  let dentroDeAspas = false

  for (let i = 0; i < texto.length; i++) {
    const c = texto[i]

    if (dentroDeAspas) {
      if (c === '"') {
        if (texto[i + 1] === '"') { campo += '"'; i++ }  // "" = aspa literal
        else dentroDeAspas = false
      } else campo += c
      continue
    }

    if (c === '"') { dentroDeAspas = true; continue }
    if (c === separador) { linha.push(campo); campo = ''; continue }
    if (c === '\n') { linha.push(campo); linhas.push(linha); linha = []; campo = ''; continue }
    if (c === '\r') continue
    campo += c
  }
  if (campo !== '' || linha.length > 0) { linha.push(campo); linhas.push(linha) }
  return linhas.filter((l) => l.some((v) => v.trim() !== ''))
}

/** Cabeçalho da planilha → chave que a fonte `agenda_antigos` entende. */
const COLUNAS = {
  'id': 'id',
  'nome': 'nome',
  'whatsapp': 'whatsapp',
  'instagram': 'instagram',
  'e-mail': 'email',
  'data de cadastro': 'criado_em',
  'fase': 'fase',
  'área de atuação': 'area',
  'aumento esperado (6m)': 'aumento',
  'já investiu': 'investimento',
  'sono': 'sono',
  'trabalho': 'trabalho',
  'deslocamento': 'deslocamento',
  'reuniões': 'reunioes',
  'café da manhã': 'cafe',
  'almoço': 'almoco',
  'jantar': 'jantar',
  'treino': 'treino',
  'pessoas importantes': 'pessoas',
  'procrastinação': 'procrastinacao',
}

/**
 * Telefone pronto pro WhatsApp: só dígitos, com DDI do Brasil.
 *
 * A planilha traz "49998148884" — DDD + número, sem o 55. O WhatsApp Cloud API
 * precisa de DDI+DDD+número, então sem isso a mensagem simplesmente não sai.
 * Só acrescenta em número de 10 ou 11 dígitos que ainda não comece com 55, pra
 * não estragar um contato internacional que já venha completo.
 */
function normalizarTelefone(valor) {
  const digitos = String(valor ?? '').replace(/\D/g, '')
  if (!digitos) return null
  if ((digitos.length === 10 || digitos.length === 11) && !digitos.startsWith('55')) {
    return '55' + digitos
  }
  return digitos
}

const texto = readFileSync(arquivo, 'utf8').replace(/^﻿/, '')  // tira o BOM
const linhas = parseCsv(texto)
if (linhas.length < 2) {
  console.error('Planilha vazia ou sem linhas de dados.')
  process.exit(1)
}

const cabecalho = linhas[0].map((h) => h.trim().toLowerCase())
const desconhecidas = cabecalho.filter((h) => h && !COLUNAS[h])
if (desconhecidas.length) {
  console.warn('Colunas ignoradas (sem mapeamento): ' + desconhecidas.join(', '))
}

const registros = []
for (const linha of linhas.slice(1)) {
  const bruto = {}
  cabecalho.forEach((h, i) => {
    const chave = COLUNAS[h]
    if (chave) bruto[chave] = (linha[i] ?? '').trim()
  })
  if (!bruto.id && !bruto.nome && !bruto.whatsapp) continue
  registros.push(bruto)
}

console.log(`Planilha: ${registros.length} lead(s) lidos de ${linhas.length - 1} linha(s).`)

if (dryRun) {
  console.log('\n--dry: mostrando os 3 primeiros, nada será gravado.\n')
  registros.slice(0, 3).forEach((r) => {
    console.log('  id=' + r.id + ' | ' + r.nome + ' | ' + normalizarTelefone(r.whatsapp) + ' | ' + (r.instagram || '-'))
  })
  process.exit(0)
}

const client = new pg.Client({ connectionString })
await client.connect()

try {
  const { rows: orgs } = await client.query('SELECT id, name FROM organizations ORDER BY created_at LIMIT 2')
  if (orgs.length === 0) { console.error('Nenhuma organização no banco.'); process.exit(1) }
  if (orgs.length > 1) { console.error('Mais de uma organização — ajuste o script pra escolher.'); process.exit(1) }
  const organizationId = orgs[0].id

  // Os leads importados entram SEM etapa, de proposito.
  //
  // O Kanban mostra por onde o atendimento esta andando agora; uma base
  // historica de centenas de contatos enterraria os leads do dia numa coluna
  // com 600 cards. Sem stage_id, o lead nao pertence a coluna nenhuma e some do
  // board — sem sair do banco, entao a aba Leads e o botao "Enviar mensagem"
  // continuam funcionando normalmente (os dois so precisam da linha existir).
  //
  // Quando alguem trabalhar um desses leads, e so arrastar pra uma coluna.
  const stageId = null

  let novos = 0, atualizados = 0, semTelefone = 0, leadsCriados = 0, leadsExistentes = 0

  for (const r of registros) {
    const phone = normalizarTelefone(r.whatsapp)
    if (!phone) semTelefone++

    const instagram = r.instagram && r.instagram !== '—'
      ? '@' + r.instagram.replace(/^https?:\/\/(www\.)?instagram\.com\//i, '').replace(/^@/, '').replace(/\/+$/, '')
      : null
    const email = r.email && r.email !== '—' ? r.email : null

    const payload = {}
    for (const k of ['criado_em','fase','area','aumento','investimento','sono','trabalho','deslocamento','reunioes','cafe','almoco','jantar','treino','pessoas','procrastinacao']) {
      if (r[k] && r[k] !== '—') payload[k] = r[k]
    }

    // 1) Lead do CRM — é ele que faz o botão "Enviar mensagem" ter pra onde ir.
    let leadId = null
    if (phone) {
      const { rows: existente } = await client.query(
        `SELECT id FROM leads WHERE organization_id = $1 AND phone = $2 AND deleted_at IS NULL LIMIT 1`,
        [organizationId, phone]
      )
      if (existente.length) { leadId = existente[0].id; leadsExistentes++ }
      else {
        const { rows: criado } = await client.query(
          `INSERT INTO leads (organization_id, title, phone, email, stage_id, custom_attributes, last_activity_at)
           VALUES ($1,$2,$3,$4,$5,$6,NOW()) RETURNING id`,
          [organizationId, r.nome || 'Sem nome', phone, email, stageId,
           JSON.stringify({ lead_source: 'agenda_antigos', ...payload })]
        )
        leadId = criado[0].id
        leadsCriados++
      }
    }

    // 2) Linha do log de fontes — ON CONFLICT no mesmo índice do webhook, então
    // reimportar a planilha atualiza em vez de duplicar.
    const { rows: gravado } = await client.query(
      `INSERT INTO lead_source_submissions
         (organization_id, source, external_id, name, email, phone, instagram, payload, lead_id)
       VALUES ($1,'agenda_antigos',$2,$3,$4,$5,$6,$7,$8)
       ON CONFLICT (organization_id, source, external_id) WHERE external_id IS NOT NULL
       DO UPDATE SET name = EXCLUDED.name, email = EXCLUDED.email, phone = EXCLUDED.phone,
                     instagram = EXCLUDED.instagram, payload = EXCLUDED.payload,
                     lead_id = COALESCE(lead_source_submissions.lead_id, EXCLUDED.lead_id),
                     updated_at = NOW()
       RETURNING (xmax = 0) AS inseriu`,
      [organizationId, r.id || null, r.nome || 'Sem nome', email, phone, instagram,
       JSON.stringify(payload), leadId]
    )
    if (gravado[0]?.inseriu) novos++; else atualizados++
  }

  console.log('')
  console.log(`  linhas novas       : ${novos}`)
  console.log(`  linhas atualizadas : ${atualizados}`)
  console.log(`  leads criados      : ${leadsCriados}`)
  console.log(`  leads já existentes: ${leadsExistentes}`)
  if (semTelefone) console.log(`  sem telefone       : ${semTelefone} (não viram lead, mas ficam no log)`)
  console.log('')
} catch (err) {
  console.error('Falhou:', err.message)
  process.exitCode = 1
} finally {
  await client.end()
}
