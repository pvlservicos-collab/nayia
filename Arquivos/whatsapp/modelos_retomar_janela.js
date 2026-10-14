// Roda DENTRO do container do CRM:  docker exec -i crm-imobeasy node - conferir | enviar 1 2 3 | situacao
// Pedro, 14/10/2026: "faz uns modelos de recuperação para reabrir janela, utilidade: Oi, está por aí? Boa tarde, está
// por aí? Boa noite, bom dia, essas expressões". Servem para voltar a falar com quem passou das 24 h da janela da Meta.
// Criar modelo NÃO manda mensagem a ninguém. A categoria do POST é PROVISÓRIA: conferir com `situacao` depois.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const MODELOS = {
  1: { corpo: 'Oi, está por aí?', semNome: true },
  2: { corpo: 'Bom dia, está por aí?', semNome: true },
  3: { corpo: 'Boa tarde, está por aí?', semNome: true },
  4: { corpo: 'Boa noite, está por aí?', semNome: true },
  5: { corpo: 'Oi, {{1}}, está por aí?' },
  6: { corpo: 'Bom dia, {{1}}, está por aí?' },
  7: { corpo: 'Boa tarde, {{1}}, está por aí?' },
  8: { corpo: 'Boa noite, {{1}}, está por aí?' },
}
const nomeDe = (n) => 'retomar_janela_' + String(n).padStart(2, '0')

function modelo(n) {
  const m = MODELOS[n]
  const comps = [
    m.semNome ? { type: 'BODY', text: m.corpo } : { type: 'BODY', text: m.corpo, example: { body_text: [['Carlos']] } },
    { type: 'FOOTER', text: RODAPE },
  ]
  if (m.botoes) comps.push({ type: 'BUTTONS', buttons: m.botoes.map((t) => ({ type: 'QUICK_REPLY', text: t })) })
  return { name: nomeDe(n), language: 'pt_BR', category: 'UTILITY', components: comps }
}

async function meta(caminho, corpo) {
  const r = await fetch('https://graph.facebook.com/v23.0/' + caminho, {
    method: corpo ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: corpo ? JSON.stringify(corpo) : undefined,
  })
  return r.json()
}

async function main() {
  const modo = process.argv[2] || 'conferir'
  const ja = await meta(waba + '/message_templates?limit=200&fields=name,status,category')
  const existe = new Map((ja.data || []).map((t) => [t.name, t]))
  if (modo === 'situacao') {
    for (const n of Object.keys(MODELOS)) {
      const t = existe.get(nomeDe(n))
      console.log(nomeDe(n), t ? `${t.status} | ${t.category}` : '(não enviado)')
    }
    return
  }
  const quais = modo === 'enviar' ? process.argv.slice(3).map(Number) : Object.keys(MODELOS).map(Number)
  for (const n of quais) {
    const m = modelo(n)
    const b = MODELOS[n].botoes ? ' | botões: ' + MODELOS[n].botoes.join(' / ') : ' | sem botões'
    console.log(`${m.name}${b}\n   ${MODELOS[n].corpo}`)
    if (modo !== 'enviar') continue
    if (existe.has(m.name)) { console.log('   -> já existe na Meta, não mandei de novo'); continue }
    const r = await meta(waba + '/message_templates', m)
    console.log('   -> ' + (r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} | id ${r.id}`))
  }
}
main().catch((e) => console.log('falhou:', e.message))
