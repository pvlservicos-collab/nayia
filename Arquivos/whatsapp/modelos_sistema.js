// Roda DENTRO do container do CRM:  docker exec -i crm-imobeasy node - conferir | enviar 1 2 3 | situacao
// Pedro, 14/10/2026, depois de a Meta rebaixar para Marketing 8 dos 10 "confirmar_disponivel" e os "Oi, está por aí?":
// "tenta variações que pareçam uma mensagem de sistema". Aviso de cadastro (para dono que TEM imóvel cadastrado
// conosco) e aviso de atendimento em aberto (para quem já conversa com a gente e passou das 24 h).
// Criar modelo NÃO manda mensagem a ninguém. A categoria do POST é PROVISÓRIA: conferir com `situacao` depois.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const TRES = ['Disponível', 'Alugado', 'Vendido']
const MODELOS = {
  // aviso de cadastro
  1: { corpo: 'Atualização de cadastro: o imóvel de {{1}} cadastrado na Imob Easy está com a disponibilidade pendente de confirmação. Responda esta mensagem para confirmar se ele continua disponível.' },
  2: { corpo: 'Aviso de cadastro: precisamos confirmar a disponibilidade do imóvel cadastrado em nome de {{1}} na Imob Easy. Selecione a situação atual:', botoes: TRES },
  3: { corpo: 'Imob Easy | Cadastro de imóveis. Sr.(a) {{1}}, a disponibilidade do imóvel cadastrado conosco precisa ser confirmada para manter o anúncio atualizado no site. Ele continua disponível?' },
  4: { corpo: 'Confirmação pendente: o cadastro do imóvel de {{1}} na Imob Easy está aguardando a confirmação de disponibilidade. Selecione uma opção:', botoes: ['Continua disponível', 'Não está disponível'] },
  5: { corpo: 'Notificação de cadastro: o anúncio do imóvel de {{1}} no site da Imob Easy será atualizado. Confirme, por favor, se o imóvel continua disponível respondendo esta mensagem.' },
  // atendimento em aberto (reabrir a janela de 24 h)
  6: { corpo: 'Atendimento em aberto: a conversa de {{1}} com a Imob Easy está aguardando retorno. Responda esta mensagem para continuar o atendimento.' },
  7: { corpo: 'Sr.(a) {{1}}, o seu atendimento com a Imob Easy está pausado. Responda esta mensagem para retomar a conversa.' },
  8: { corpo: 'Aviso de atendimento: a conversa de {{1}} com a Imob Easy ficou sem resposta. Para continuar, é só responder esta mensagem.' },
  9: { corpo: 'Lembrete de atendimento: o atendimento de {{1}} com a Imob Easy continua aberto. Toque abaixo para continuar.', botoes: ['Continuar atendimento'] },
  10: { corpo: 'Imob Easy | Atendimento. Sr.(a) {{1}}, ficou uma pendência na nossa conversa. Responda esta mensagem para darmos continuidade.' },
}
const nomeDe = (n) => 'sistema_aviso_' + String(n).padStart(2, '0')

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
