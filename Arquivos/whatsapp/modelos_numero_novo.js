// Modelos de UTILIDADE do número novo (Pedro, 20/10/2026): "suba essas mensagens como utilidade nos modelos ... com
// Imobeasy no rodapé, e crie 5 variações reais, ou seja mudando várias palavras sem mudar o objetivo da mensagem".
// Cinco blocos (os três textos dele; os dois primeiros com os dois jogos de botões). Em cada bloco o 01 é o texto dele
// (só pontuação e acento) e 02-06 são as variações, cada uma com outra abertura e outra ordem.
// O botão "tenho imóvel p/ vender/alugar" tem 29 letras e a Meta aceita 25: ficou "Tenho p/ vender ou alugar".
// Sem variável: o corpo não leva nome.
//
// Conferir (sem token):   node Arquivos/whatsapp/modelos_numero_novo.js conferir
// Dentro do CRM:          docker exec -i crm-imobeasy node - enviar tudo                    < este arquivo
//                         docker exec -i crm-imobeasy node - enviar nay_a 1 2 texto3 4       < este arquivo
//                         docker exec -i crm-imobeasy node - situacao | apagar nome..       < este arquivo
// Criar modelo NÃO manda mensagem a ninguém. A categoria do POST é PROVISÓRIA: conferir com `situacao` depois.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const BOTOES_A = ['Tenho p/ vender ou alugar', 'Estou buscando imóvel', 'Estou sem no momento']
const BOTOES_B = ['Quero vender ou alugar', 'Estou buscando imóvel', 'Estou sem no momento']
const GRUPOS = {
  texto1_a: {
    prefixo: 'numero_novo_1a_',
    botoes: BOTOES_A,
    modelos: {
      1: { corpo: 'Olá, este é o novo número da Imob Easy. Caso tenha um imóvel para venda e locação, estamos com uma demanda alta de busca.' },
      2: { cabecalho: 'Novo número', corpo: 'A Imob Easy agora atende por este WhatsApp. Se você tem imóvel para vender ou alugar, temos muita gente procurando.' },
      3: { corpo: 'Salve este contato: é o novo WhatsApp da Imob Easy. A procura por imóveis está alta. Você tem algum para venda ou locação?' },
      4: { corpo: 'Oi! Mudamos de número, e a Imob Easy fala com você por aqui agora. Muitos clientes estão buscando imóvel para comprar ou alugar.' },
      5: { cabecalho: 'Aviso da Imob Easy', corpo: 'Este é o nosso número novo. Estamos recebendo muitas buscas por imóveis à venda e para alugar; se tiver um, responda abaixo.' },
      6: { corpo: 'Imob Easy de número novo! Hoje a busca por imóveis está grande. Se o seu imóvel está para vender ou alugar, fale com a gente.' },
    },
  },
  texto1_b: {
    prefixo: 'numero_novo_1b_',
    botoes: BOTOES_B,
    modelos: {
      1: { corpo: 'Olá, este é o novo número da Imob Easy. Caso tenha um imóvel para venda e locação, estamos com uma demanda alta de busca.' },
      2: { corpo: 'Olá! A Imob Easy está com número novo, é este aqui. A demanda por imóveis para venda e locação está alta neste momento.' },
      3: { cabecalho: 'Número atualizado', corpo: 'Passamos a atender neste número. Se pensa em vender ou alugar um imóvel, há muitos clientes da Imob Easy procurando.' },
      4: { corpo: 'Este WhatsApp agora é o da Imob Easy. Estamos com várias buscas em aberto de imóveis para vender e para alugar.' },
      5: { corpo: 'Olá, tudo bem? Trocamos de número e a Imob Easy segue por aqui. Quem tem imóvel para venda ou aluguel encontra muita procura agora.' },
      6: { corpo: 'Novo contato da Imob Easy: este número. A procura por imóveis à venda e para locação cresceu muito nas últimas semanas.' },
    },
  },
  nay_a: {
    prefixo: 'numero_novo_nay_a_',
    botoes: BOTOES_A,
    modelos: {
      1: { corpo: 'Olá, me chamo Nay, e este é o novo número da imobiliária Imob Easy. Caso tenha um imóvel para venda ou locação, estamos com uma demanda alta de busca.' },
      2: { corpo: 'Oi, aqui é a Nay, da Imob Easy! Estou falando pelo nosso número novo. Tem imóvel para vender ou alugar? A procura está alta.' },
      3: { cabecalho: 'Novo número da Imob Easy', corpo: 'Sou a Nay e passo a atender você por aqui. Temos muitos clientes buscando imóveis à venda e para locação.' },
      4: { corpo: 'Olá! Nay falando, da imobiliária Imob Easy, agora neste número. Se você tem algum imóvel disponível para venda ou aluguel, a demanda está grande.' },
      5: { corpo: 'Prazer, sou a Nay! A Imob Easy mudou de número e este é o novo. Estamos com muitas buscas por imóveis; tem algum para vender ou alugar?' },
      6: { corpo: 'Olá, aqui quem fala é a Nay. Salve este número: é o novo da Imob Easy. A busca por imóveis para venda e locação não para de crescer.' },
    },
  },
  nay_b: {
    prefixo: 'numero_novo_nay_b_',
    botoes: BOTOES_B,
    modelos: {
      1: { corpo: 'Olá, me chamo Nay, e este é o novo número da imobiliária Imob Easy. Caso tenha um imóvel para venda ou locação, estamos com uma demanda alta de busca.' },
      2: { corpo: 'Olá, sou a Nay, da Imob Easy, e este é o nosso novo número. Muitos clientes estão à procura de imóveis para comprar ou alugar.' },
      3: { corpo: 'Aqui é a Nay! A imobiliária Imob Easy agora atende por este WhatsApp. Quem quer vender ou alugar um imóvel tem bastante procura hoje.' },
      4: { cabecalho: 'Nay | Imob Easy', corpo: 'Este é o novo número da imobiliária. Está pensando em vender ou alugar algum imóvel? Temos uma demanda alta de busca.' },
      5: { corpo: 'Oi, tudo bem? Me chamo Nay e falo pela Imob Easy, com número novo. Estamos com várias buscas abertas de imóveis à venda e para locação.' },
      6: { corpo: 'Olá! A Nay da Imob Easy está neste número agora. Se tiver imóvel para venda ou locação, conte com a gente: a procura está grande.' },
    },
  },
  texto3: {
    prefixo: 'numero_novo_3_',
    botoes: BOTOES_B,
    modelos: {
      1: { corpo: 'Olá, a imobiliária Imob Easy está de número novo. Temos muitos clientes em busca de imóveis, caso tenha imóvel para venda e locação.' },
      2: { cabecalho: 'Imob Easy de número novo', corpo: 'Temos muitos clientes procurando imóveis. Se você tiver um para vender ou alugar, responda aqui.' },
      3: { corpo: 'A Imob Easy trocou de número, e é por aqui que seguimos. São muitos clientes em busca de imóveis à venda e para alugar.' },
      4: { corpo: 'Olá! Muitos clientes da Imob Easy estão buscando imóvel, e agora atendemos neste número novo. Tem algum para venda ou locação?' },
      5: { corpo: 'Novo número da imobiliária Imob Easy. A nossa lista de clientes em busca de imóveis está grande; se você tem um para vender ou alugar, fale com a gente.' },
      6: { corpo: 'Oi, tudo certo? A Imob Easy está com contato novo. Clientes procurando imóvel para comprar ou alugar não faltam: o seu pode ser o próximo.' },
    },
  },
}
const nomeDe = (g, n) => GRUPOS[g].prefixo + String(n).padStart(2, '0')
const botoesDe = (g, n) => GRUPOS[g].modelos[n].botoes || GRUPOS[g].botoes
const todos = () => Object.keys(GRUPOS).flatMap((g) => Object.keys(GRUPOS[g].modelos).map((n) => [g, Number(n)]))

function modelo(g, n) {
  const m = GRUPOS[g].modelos[n], b = botoesDe(g, n), comps = []
  if (m.cabecalho) comps.push({ type: 'HEADER', format: 'TEXT', text: m.cabecalho })
  comps.push({ type: 'BODY', text: m.corpo })
  comps.push({ type: 'FOOTER', text: RODAPE })
  if (b.length) comps.push({ type: 'BUTTONS', buttons: b.map((t) => ({ type: 'QUICK_REPLY', text: t })) })
  return { name: nomeDe(g, n), language: 'pt_BR', category: 'UTILITY', components: comps }
}

function defeitos(g, n) {
  const m = GRUPOS[g].modelos[n], d = []
  if (m.cabecalho && m.cabecalho.length > 60) d.push('cabeçalho com mais de 60 caracteres')
  if (m.corpo.length > 1024) d.push('corpo com mais de 1024 caracteres')
  if (/\{\{/.test(m.corpo)) d.push('este bloco não leva variável')
  for (const b of botoesDe(g, n)) if (b.length > 25) d.push('botão com mais de 25 caracteres: ' + b)
  if (!/^[a-z0-9_]+$/.test(nomeDe(g, n))) d.push('nome com caractere fora de a-z, 0-9 e _')
  return d
}

async function meta(caminho, corpo, metodo) {
  const r = await fetch('https://graph.facebook.com/v23.0/' + caminho, {
    method: metodo || (corpo ? 'POST' : 'GET'),
    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
    body: corpo ? JSON.stringify(corpo) : undefined,
  })
  return r.json()
}

function escolhidos(args) {
  if (args[0] === 'tudo') return todos()
  const q = []
  let g = null
  for (const a of args) {
    if (GRUPOS[a]) { g = a; continue }
    const n = Number(a)
    if (g && GRUPOS[g].modelos[n]) q.push([g, n])
  }
  return q
}

async function main() {
  const modo = process.argv[2] || 'conferir'
  if (modo === 'conferir') {
    for (const [g, n] of todos()) {
      const m = GRUPOS[g].modelos[n], d = defeitos(g, n)
      console.log(`${nomeDe(g, n)} | ${m.corpo.length} letras${d.length ? ' | DEFEITO: ' + d.join('; ') : ''}\n` +
        (m.cabecalho ? `   *${m.cabecalho}*\n` : '') + `   ${m.corpo}\n   ${RODAPE}\n   [${botoesDe(g, n).join('] [')}]\n`)
    }
    return
  }
  if (!token || !waba) { console.log('sem META_TOKEN/META_WABA_ID no ambiente: rode dentro do container do CRM'); return }
  const ja = await meta(waba + '/message_templates?limit=250&fields=id,name,status,category')
  const existe = new Map((ja.data || []).map((t) => [t.name, t]))
  if (modo === 'situacao') {
    for (const [g, n] of todos()) {
      const t = existe.get(nomeDe(g, n))
      console.log(nomeDe(g, n), t ? `${t.status} | ${t.category}` : '(não enviado)')
    }
    return
  }
  if (modo === 'apagar') {
    for (const nome of process.argv.slice(3)) {
      if (!nome.startsWith('numero_novo_')) { console.log(nome, '-> só apago os numero_novo_*'); continue }
      const r = await meta(`${waba}/message_templates?name=${nome}`, null, 'DELETE')
      console.log(nome, '->', r.error ? 'ERRO: ' + (r.error.error_user_msg || r.error.message) : 'apagado')
    }
    return
  }
  if (modo === 'enviar') {
    const quais = escolhidos(process.argv.slice(3))
    if (!quais.length) { console.log('diga o bloco e os números (enviar nay_a 1 2 texto3 4) ou "enviar tudo"'); return }
    for (const [g, n] of quais) {
      const d = defeitos(g, n)
      if (d.length) { console.log(nomeDe(g, n), '-> NÃO enviado: ' + d.join('; ')); continue }
      if (existe.has(nomeDe(g, n))) { console.log(nomeDe(g, n), '-> já existe na Meta, não mandei de novo'); continue }
      const r = await meta(waba + '/message_templates', modelo(g, n))
      console.log(nomeDe(g, n), '->', r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} (provisória) | id ${r.id}`)
    }
    return
  }
  console.log('modos: conferir | enviar bloco N.. | enviar tudo | situacao | apagar nome..')
}
main().catch((e) => console.log('falhou:', e.message))
