// Roda DENTRO do container do CRM:  docker exec -i crm-imobeasy node - conferir        (só mostra, não envia nada)
//                                    docker exec -i crm-imobeasy node - enviar 1 2 3     (cria na Meta os números marcados)
//                                    docker exec -i crm-imobeasy node - situacao         (a categoria e a aprovação DEPOIS da revisão)
// Pedro, 22/10/2026, depois que a Meta pausou o outro_imovel_04 e travou a conta (131031) por denúncia: "aprova um modelo
// igual esse, na verdade aprova vários, e põe um botão Excluir meu contato, quem clica nisso a Nay não responde mais,
// como uma opção do cliente desligar sem ele precisar denunciar para a Meta".
// O botão "Excluir meu contato" é tratado no nay-captacao (atender.py, EXCLUIR_CONTATO): opt_out, sai da fila, sem resposta.
// Criar modelo NÃO manda mensagem a ninguém: ele entra na fila de aprovação da Meta. O token fica no ambiente.
// A categoria que o POST devolve é PROVISÓRIA (11/10): a revisão da Meta pode rebaixar para Marketing. Conferir com `situacao`.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const BOTOES = ['Tenho outro imóvel', 'Não tenho outro', 'Excluir meu contato']
const MODELOS = {
  1: { corpo: 'Cadastro de proprietário: {{1}}, o(a) Sr.(a) possui outro imóvel disponível além do que já consta conosco?' },
  2: { corpo: 'Cadastro de proprietário: {{1}}, além do imóvel que já consta conosco, o(a) Sr.(a) possui outro disponível?' },
  3: { corpo: 'Atualização de cadastro: {{1}}, o(a) Sr.(a) possui outro imóvel disponível além do que já está cadastrado conosco?' },
  4: { corpo: 'Cadastro de proprietário: {{1}}, existe outro imóvel do(a) Sr.(a) disponível, além do que já consta na Imob Easy?' },
  5: { corpo: 'Cadastro de proprietário: {{1}}, o(a) Sr.(a) tem mais algum imóvel disponível além do que já consta conosco?' },
  6: { corpo: 'Atualização de cadastro: {{1}}, consta um imóvel do(a) Sr.(a) conosco. Possui outro imóvel disponível?' },
  7: { corpo: 'Cadastro de proprietário: {{1}}, para atualizar o seu cadastro, o(a) Sr.(a) possui outro imóvel disponível além do que já consta conosco?' },
  8: { corpo: 'Cadastro de proprietário na Imob Easy: {{1}}, o(a) Sr.(a) possui outro imóvel disponível além do já cadastrado?' },
}
const nomeDe = (n) => 'outro_imovel_sair_' + String(n).padStart(2, '0')

function modelo(n) {
  const m = MODELOS[n]
  return {
    name: nomeDe(n), language: 'pt_BR', category: 'UTILITY',
    components: [
      { type: 'BODY', text: m.corpo, example: { body_text: [['Sr. Carlos']] } },
      { type: 'FOOTER', text: RODAPE },
      { type: 'BUTTONS', buttons: BOTOES.map((t) => ({ type: 'QUICK_REPLY', text: t })) },
    ],
  }
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
  if (ja.error) console.log('a Meta respondeu à lista de modelos com erro:', ja.error.message)
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
    console.log(`${m.name} | botões: ${BOTOES.join(' / ')}\n   ${MODELOS[n].corpo}`)
    if (modo !== 'enviar') continue
    if (existe.has(m.name)) { console.log('   -> já existe na Meta, não mandei de novo'); continue }
    const r = await meta(waba + '/message_templates', m)
    console.log('   -> ' + (r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} | id ${r.id}`))
  }
}
main().catch((e) => console.log('falhou:', e.message))
