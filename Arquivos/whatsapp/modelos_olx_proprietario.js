// Roda DENTRO do container do CRM:  docker exec -i crm-imobeasy node - conferir | enviar 1 2 | situacao
// Pedro, 14/10/2026 (SCRIPT APÓS OLX): a primeira mensagem da "Nay proprietários da OLX", no número oficial:
// "Olá, seu (nome), aqui é a Nay da imob easy, conversamos no olx sobre o seu imóvel, e gostaria de tirar uma dúvida
// com o Sr. (a)". Fora da janela de 24 h só modelo aprovado abre conversa. O nay-captacao usa o primeiro aprovado da
// lista captacao_config.olx_abertura_modelos. Criar modelo NÃO manda mensagem a ninguém.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const MODELOS = {
  1: { corpo: 'Olá, {{1}}! Aqui é a Nay, da Imob Easy. Conversamos na OLX sobre o seu imóvel e gostaria de tirar uma dúvida com o(a) Sr.(a).' },
  2: { corpo: 'Atendimento Imob Easy: {{1}}, aqui é a Nay, sobre o imóvel que o(a) Sr.(a) anunciou na OLX. Posso tirar uma dúvida rápida sobre ele?' },
}
const nomeDe = (n) => 'olx_proprietario_abertura_' + String(n).padStart(2, '0')

function modelo(n) {
  const m = MODELOS[n]
  const comps = [
    { type: 'BODY', text: m.corpo, example: { body_text: [['Carlos']] } },
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
