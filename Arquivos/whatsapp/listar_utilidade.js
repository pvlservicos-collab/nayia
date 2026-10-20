// Lista os modelos da Meta APROVADOS como Utilidade, com o texto e os botões (só leitura; nunca imprime o token).
//   docker exec -i crm-imobeasy node - [filtro] < Arquivos/whatsapp/listar_utilidade.js
// `filtro` (opcional) é um pedaço do nome. Pedro, 20/10/2026: achar os que servem para perguntar ao dono se ele tem
// imóvel para vender ou adicionar.
const token = process.env.META_TOKEN || process.env.WHATSAPP_TOKEN || ''
const waba = process.env.META_WABA_ID || process.env.WHATSAPP_WABA_ID || ''

async function main() {
  if (!token || !waba) { console.log('sem META_TOKEN/META_WABA_ID no ambiente: rode dentro do container do CRM'); return }
  const filtro = (process.argv[2] || '').toLowerCase()
  let url = `https://graph.facebook.com/v23.0/${waba}/message_templates?limit=200&fields=name,status,category,language,components`
  const todos = []
  while (url) {
    const r = await fetch(url, { headers: { Authorization: 'Bearer ' + token } }).then((x) => x.json())
    if (r.error) { console.log('erro da Meta:', r.error.message); return }
    todos.push(...(r.data || []))
    url = r.paging && r.paging.next ? r.paging.next : null
  }
  // 2º argumento "qualquer": mostra todas as situações e categorias (com a situação na linha do nome)
  const qualquer = process.argv[3] === 'qualquer'
  const util = todos.filter((t) => (qualquer || (t.status === 'APPROVED' && t.category === 'UTILITY')) &&
    t.name.toLowerCase().includes(filtro))
  if (qualquer) {
    for (const t of util.sort((a, b) => a.name.localeCompare(b.name))) console.log(`${t.name} | ${t.status} | ${t.category}`)
    return
  }
  console.log(`total ${todos.length} modelos; aprovados como Utilidade: ${util.length}\n`)
  for (const t of util.sort((a, b) => a.name.localeCompare(b.name))) {
    const c = t.components || []
    const cab = (c.find((x) => x.type === 'HEADER') || {}).text
    const corpo = ((c.find((x) => x.type === 'BODY') || {}).text || '').replace(/\s+/g, ' ')
    const botoes = ((c.find((x) => x.type === 'BUTTONS') || {}).buttons || []).map((b) => b.text)
    console.log(`${t.name} (${t.language})${cab ? ' *' + cab + '*' : ''}\n   ${corpo}${botoes.length ? '\n   [' + botoes.join('] [') + ']' : ''}\n`)
  }
}
main()
