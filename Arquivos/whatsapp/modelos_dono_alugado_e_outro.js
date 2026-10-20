// Dois modelos de UTILIDADE para donos (Pedro, 20/10/2026):
//   ainda_alugado_01-10: "perguntando se o imóvel ainda está alugado com 2 botões Está alugado / Está disponível"
//   outro_imovel_01-10:  "perguntando a donos que já têm um imóvel se ele tem mais algum disponível"
// "com imobeasy no rodapé, e com bastante variações; vc criou umas variações muito próximas umas das outras por isso
// não foi aprovado, precisa variar mais mantendo o sentido, muda ordem das palavras, encurta tudo".
// Por isso cada variação tem outra abertura e outra ordem, e algumas levam cabeçalho (os moldes que a Meta já deixou
// em Utilidade para dono: "Atualização do cadastro", "Status do imóvel", "Situação do imóvel", sem cabeçalho também).
// Só {{1}} (o nome; o disparador do nay-captacao manda uma variável).
//
// Conferir (sem token):   node Arquivos/whatsapp/modelos_dono_alugado_e_outro.js conferir
// Dentro do CRM:          docker exec -i crm-imobeasy node - enviar ainda_alugado 1 2 outro_imovel 3 < este arquivo
//                         docker exec -i crm-imobeasy node - enviar tudo                         < este arquivo
//                         docker exec -i crm-imobeasy node - situacao | apagar nome..            < este arquivo
// Criar modelo NÃO manda mensagem a ninguém. A categoria do POST é PROVISÓRIA: conferir com `situacao` depois.
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const GRUPOS = {
  ainda_alugado: {
    prefixo: 'ainda_alugado_',
    botoes: ['Está alugado', 'Está disponível'],
    modelos: {
      1: { corpo: 'Olá, {{1}}! O seu imóvel cadastrado na Imob Easy consta como alugado. Ele continua alugado?' },
      2: { cabecalho: 'Atualização de cadastro', corpo: 'Olá, {{1}}. O imóvel registrado em seu nome está como alugado na Imob Easy. Qual é a situação hoje?' },
      3: { corpo: 'Atualização de cadastro, {{1}}: o seu imóvel aparece como alugado no nosso sistema. Confirme a situação atual:' },
      4: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. O imóvel que o(a) Sr.(a) cadastrou conosco ainda está alugado?' },
      5: { cabecalho: 'Status do imóvel', corpo: 'Olá, {{1}}. No cadastro da Imob Easy o seu imóvel está marcado como alugado. Isso continua valendo?' },
      6: { corpo: 'Confirmação de situação: {{1}}, o imóvel cadastrado conosco segue alugado ou já está disponível?' },
      7: { corpo: 'Olá, {{1}}! Estamos conferindo os imóveis alugados do nosso cadastro. O seu ainda está com inquilino?' },
      8: { cabecalho: 'Situação do imóvel', corpo: 'Olá, {{1}}. A Imob Easy está revisando a situação dos imóveis cadastrados e o seu consta como alugado. Selecione:' },
      9: { corpo: 'Imob Easy | Cadastro de imóveis. {{1}}, o seu imóvel continua alugado? Toque na opção correta:' },
      10: { corpo: 'Olá, {{1}}! Precisamos confirmar uma informação do seu cadastro: o imóvel continua alugado?' },
    },
  },
  outro_imovel: {
    prefixo: 'outro_imovel_',
    botoes: ['Tenho outro imóvel', 'Não tenho outro'],
    modelos: {
      1: { corpo: 'Olá, {{1}}! Estamos atualizando o seu cadastro de proprietário na Imob Easy. Além do imóvel já cadastrado, o(a) Sr.(a) tem outro disponível?' },
      2: { corpo: 'Olá, {{1}}. Atualização de cadastro: há mais algum imóvel seu disponível para incluirmos junto ao que já está na Imob Easy?' },
      3: { cabecalho: 'Cadastro de proprietário', corpo: 'Olá, {{1}}! O seu cadastro na Imob Easy tem um imóvel registrado. Existe outro imóvel seu disponível para cadastrar?' },
      4: { corpo: 'Cadastro de proprietário: {{1}}, o(a) Sr.(a) possui outro imóvel disponível além do que já consta conosco?' },
      5: { corpo: 'Olá, {{1}}. Este é o novo número da Imob Easy. Precisamos completar o seu cadastro: tem mais algum imóvel disponível?' },
      6: { cabecalho: 'Atualização de cadastro', corpo: 'Olá, {{1}}! Para manter o seu cadastro completo, confirme: há outro imóvel seu disponível para venda ou locação?' },
      7: { cabecalho: 'Cadastro de proprietário', corpo: 'Olá, {{1}}. Revisando o cadastro dos proprietários, vimos um imóvel em seu nome. O(a) Sr.(a) tem algum outro disponível?' },
      8: { corpo: 'Olá, {{1}}! A Imob Easy está atualizando o cadastro de imóveis. Além do seu imóvel já registrado, existe mais algum disponível?' },
      9: { corpo: 'Atualização do seu cadastro, {{1}}: tem outro imóvel disponível para incluirmos na Imob Easy?' },
      10: { corpo: 'Olá, {{1}}. Pergunta rápida do cadastro da Imob Easy: o(a) Sr.(a) tem mais um imóvel disponível, além do já cadastrado?' },
    },
  },
}
const nomeDe = (g, n) => GRUPOS[g].prefixo + String(n).padStart(2, '0')
const botoesDe = (g, n) => GRUPOS[g].modelos[n].botoes || GRUPOS[g].botoes
const todos = () => Object.keys(GRUPOS).flatMap((g) => Object.keys(GRUPOS[g].modelos).map((n) => [g, Number(n)]))

function modelo(g, n) {
  const m = GRUPOS[g].modelos[n], b = botoesDe(g, n), comps = []
  if (m.cabecalho) comps.push({ type: 'HEADER', format: 'TEXT', text: m.cabecalho })
  comps.push({ type: 'BODY', text: m.corpo, example: { body_text: [['Carlos']] } })
  comps.push({ type: 'FOOTER', text: RODAPE })
  if (b.length) comps.push({ type: 'BUTTONS', buttons: b.map((t) => ({ type: 'QUICK_REPLY', text: t })) })
  return { name: nomeDe(g, n), language: 'pt_BR', category: 'UTILITY', components: comps }
}

function defeitos(g, n) {
  const m = GRUPOS[g].modelos[n], d = []
  if (m.cabecalho && m.cabecalho.length > 60) d.push('cabeçalho com mais de 60 caracteres')
  if (m.corpo.length > 1024) d.push('corpo com mais de 1024 caracteres')
  if (/^\s*\{\{1\}\}/.test(m.corpo) || /\{\{1\}\}\s*[.!?:]?\s*$/.test(m.corpo)) d.push('variável no começo ou no fim do corpo')
  if ((m.corpo.match(/\{\{/g) || []).length !== 1) d.push('o corpo deve ter exatamente uma variável')
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
    const prefixos = Object.values(GRUPOS).map((x) => x.prefixo)
    for (const nome of process.argv.slice(3)) {
      if (!prefixos.some((p) => nome.startsWith(p))) { console.log(nome, '-> só apago os ' + prefixos.join('* e ') + '*'); continue }
      const r = await meta(`${waba}/message_templates?name=${nome}`, null, 'DELETE')
      console.log(nome, '->', r.error ? 'ERRO: ' + (r.error.error_user_msg || r.error.message) : 'apagado')
    }
    return
  }
  if (modo === 'enviar') {
    const quais = escolhidos(process.argv.slice(3))
    if (!quais.length) { console.log('diga o grupo e os números (enviar ainda_alugado 1 2 outro_imovel 3) ou "enviar tudo"'); return }
    for (const [g, n] of quais) {
      const d = defeitos(g, n)
      if (d.length) { console.log(nomeDe(g, n), '-> NÃO enviado: ' + d.join('; ')); continue }
      if (existe.has(nomeDe(g, n))) { console.log(nomeDe(g, n), '-> já existe na Meta, não mandei de novo'); continue }
      const r = await meta(waba + '/message_templates', modelo(g, n))
      console.log(nomeDe(g, n), '->', r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} (provisória) | id ${r.id}`)
    }
    return
  }
  console.log('modos: conferir | enviar grupo N.. | enviar tudo | situacao | apagar nome..')
}
main().catch((e) => console.log('falhou:', e.message))
