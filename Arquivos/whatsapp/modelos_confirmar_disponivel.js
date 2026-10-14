// Roda DENTRO do container do CRM:  docker exec -i crm-imobeasy node - conferir        (só mostra, não envia nada)
//                                    docker exec -i crm-imobeasy node - enviar 1 2 3     (cria na Meta os números marcados)
//                                    docker exec -i crm-imobeasy node - situacao         (a categoria e a aprovação DEPOIS da revisão)
// Pedro, 14/10/2026: "põe 10 mensagens como essa para aprovar, umas sem e umas com botões, todas com imobeasy no
// rodapé: Olá Sr. (a) (nome), poderia me confirmar por gentileza se está disponível? gostaria de atualizar aqui no
// nosso site o seu imóvel. quero todas como utilidade".
// Criar modelo NÃO manda mensagem a ninguém: ele entra na fila de aprovação da Meta. O token fica no ambiente.
// A categoria que o POST devolve é PROVISÓRIA (11/10): a revisão da Meta pode rebaixar para Marketing. Conferir com `situacao`.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const TRES = ['Disponível', 'Alugado', 'Vendido']
const MODELOS = {
  1: { corpo: 'Olá, Sr.(a) {{1}}! Poderia me confirmar, por gentileza, se o seu imóvel ainda está disponível? Gostaria de atualizá-lo aqui no nosso site.' },
  2: { corpo: 'Olá, Sr.(a) {{1}}! Poderia me confirmar, por gentileza, se o seu imóvel ainda está disponível? Gostaria de atualizá-lo aqui no nosso site.', botoes: TRES },
  3: { corpo: 'Olá, Sr.(a) {{1}}, tudo bem? Poderia me confirmar, por gentileza, se o seu imóvel continua disponível? Quero deixar o cadastro dele atualizado no nosso site.' },
  4: { corpo: 'Olá, Sr.(a) {{1}}, tudo bem? Poderia me confirmar, por gentileza, se o seu imóvel continua disponível? Quero deixar o cadastro dele atualizado no nosso site.', botoes: ['Sim, está disponível', 'Não está mais'] },
  5: { corpo: 'Olá, Sr.(a) {{1}}! Estamos atualizando os imóveis do nosso site. Poderia me confirmar, por gentileza, se o seu ainda está disponível?' },
  6: { corpo: 'Olá, Sr.(a) {{1}}! Estamos atualizando os imóveis do nosso site. Poderia me confirmar, por gentileza, se o seu ainda está disponível?', botoes: TRES },
  7: { corpo: 'Olá, Sr.(a) {{1}}! O seu imóvel ainda está disponível? Poderia me confirmar, por gentileza? Gostaria de atualizar aqui no nosso site.' },
  8: { corpo: 'Olá, Sr.(a) {{1}}! O seu imóvel ainda está disponível? Poderia me confirmar, por gentileza? Gostaria de atualizar aqui no nosso site.', botoes: ['Sim', 'Não'] },
  9: { corpo: 'Olá, Sr.(a) {{1}}! Por gentileza, poderia me confirmar se o imóvel do(a) Sr.(a) cadastrado conosco está disponível? Gostaria de atualizar aqui no nosso site.' },
  10: { corpo: 'Olá, Sr.(a) {{1}}! Por gentileza, poderia me confirmar se o imóvel do(a) Sr.(a) cadastrado conosco está disponível? Gostaria de atualizar aqui no nosso site.', botoes: TRES },
}
const nomeDe = (n) => 'confirmar_disponivel_' + String(n).padStart(2, '0')

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
