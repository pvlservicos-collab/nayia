// Modelos de UTILIDADE para duas listas da tela Captação › Modelos WhatsApp (Pedro, 19/10/2026):
//   lista 4 "Donos que só têm imóvel vendido" (974): "mandar se tem algum imóvel para adicionar, estamos com uma
//     demanda alta de imóveis e queremos saber se você tem imóveis para vender"
//   lista 5 "Donos com imóvel alugado" (169): "confirma se não foi enviado antes, depois pergunta da data de
//     expiração e se ele não tem outro imóvel, ou [só] a data de expiração do aluguel dele"
// Medido 19/10 (site_publicos_disparo + captacao_mensagens/captacao_leads): dos 974 e dos 169, NENHUM recebeu
// disparo nosso. Os "disparados" da tela (47 e 259) são gente que a lista já tirou pelo corte dos 60 dias.
//
// O molde que a Meta deixa em Utilidade para dono (foto de 19/10, 105 modelos): "Este é o novo número da Imob Easy.
// Precisamos atualizar/confirmar ... do seu imóvel cadastrado conosco ... selecione" (situacao_imovel_cadastrado_1/3/4/5,
// situacao_condominio_1-3, sistema_aviso_01-05). Pedido direto ("tem imóvel para vender?", "demanda alta") sem o
// cadastro na frente cai para Marketing (confirmar_disponivel_01-08, captacao_*). Por isso cada texto abre com o
// cadastro ("consta como vendido/alugado", "precisamos atualizar") e só depois faz a pergunta do Pedro.
// A "demanda alta" entra em poucas variações (vendido 06-10), de propósito: é a parte com mais cara de Marketing.
//
// Só {{1}} (tratamento + nome, "Sr. Carlos"): o disparador do nay-captacao manda UMA variável (disparo.py, [quem]).
// Uma segunda variável (condomínio) pediria mudança lá; não pus.
//
// Conferir (sem token, só mostra e valida):   node Arquivos/whatsapp/modelos_vendido_e_alugado.js conferir
// Dentro do CRM (quem tem o token):           docker exec -i crm-imobeasy node - enviar vendido 1 2 alugado 3 < este arquivo
//                                             docker exec -i crm-imobeasy node - situacao        < este arquivo
//                                             docker exec -i crm-imobeasy node - apagar nome ... < este arquivo
// Criar modelo NÃO manda mensagem a ninguém. A categoria que o POST devolve é PROVISÓRIA: a revisão muda minutos
// depois; conferir com `situacao` (ou na aba WhatsApp › Mensagens do admin, que lê a cada 10 min).
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const RODAPE = 'Imobeasy'
const BOTOES_VENDIDO = ['Tenho para vender', 'Tenho para alugar', 'Não tenho']
const BOTOES_ALUGADO = ['Informar a data', 'Tenho outro imóvel', 'Não tenho outro']
const GRUPOS = {
  vendido: {
    prefixo: 'dono_vendido_',
    botoes: BOTOES_VENDIDO,
    modelos: {
      // 01-05: só o cadastro ("consta como vendido", "tem outro para incluir?"), sem falar em demanda
      1: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. O seu imóvel cadastrado conosco consta como vendido e precisamos atualizar o seu cadastro: o(a) Sr.(a) tem outro imóvel para incluir? Selecione uma opção:' },
      2: { corpo: 'Olá, {{1}}. Este é o novo número da Imob Easy. No seu cadastro conosco o imóvel consta como vendido. Para atualizar o cadastro, precisamos saber se há outro imóvel seu para incluir. Selecione a opção que corresponde à sua situação atual:' },
      3: { corpo: 'Olá, {{1}}! Atualização de cadastro: este é o novo número da Imob Easy. O imóvel do seu cadastro consta como vendido. O(a) Sr.(a) tem outro imóvel para cadastrar conosco? Toque em uma das opções abaixo.' },
      4: { corpo: 'Olá, {{1}}. O seu cadastro na Imob Easy está com o imóvel marcado como vendido e sem outro imóvel ativo. Este é o nosso novo número de atendimento. Para atualizar o cadastro, selecione a situação atual:' },
      5: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. Precisamos atualizar o seu cadastro: o imóvel registrado consta como vendido. Se o(a) Sr.(a) tiver outro imóvel para incluir, selecione uma opção abaixo:' },
      // 06-10: o cadastro na frente e a demanda alta do Pedro depois (mais risco de Marketing)
      6: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. O seu imóvel cadastrado conosco consta como vendido e precisamos atualizar o seu cadastro. Estamos com uma demanda alta de imóveis: o(a) Sr.(a) tem outro imóvel para incluir? Selecione uma opção:' },
      7: { corpo: 'Olá, {{1}}. Este é o novo número da Imob Easy. No seu cadastro conosco o imóvel consta como vendido. Como estamos com uma demanda alta de imóveis, precisamos saber se há outro imóvel seu para incluir no cadastro. Selecione a situação atual:' },
      8: { corpo: 'Olá, {{1}}! Atualização de cadastro: este é o novo número da Imob Easy. O imóvel do seu cadastro consta como vendido e a procura por imóveis está alta. O(a) Sr.(a) tem outro imóvel para cadastrar conosco? Toque em uma das opções abaixo.' },
      9: { corpo: 'Olá, {{1}}. O seu cadastro na Imob Easy está com o imóvel marcado como vendido. Este é o nosso novo número de atendimento e estamos com uma demanda alta de imóveis. Para atualizar o cadastro, selecione a situação atual:' },
      10: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. Precisamos atualizar o seu cadastro: o imóvel registrado consta como vendido. Estamos com uma demanda alta e, se o(a) Sr.(a) tiver outro imóvel para incluir, é só selecionar uma opção abaixo:' },
    },
  },
  alugado: {
    prefixo: 'dono_alugado_',
    botoes: BOTOES_ALUGADO,
    modelos: {
      // 01-05: data do fim do contrato + outro imóvel, SEM botões (a resposta é a data, em texto)
      1: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. O seu imóvel cadastrado conosco consta como alugado e precisamos atualizar o cadastro: até quando vai o contrato de locação? Se o(a) Sr.(a) tiver outro imóvel para incluir, pode responder por aqui também.', botoes: [] },
      2: { corpo: 'Olá, {{1}}. Este é o novo número da Imob Easy. No seu cadastro conosco o imóvel consta como alugado. Para atualizar o cadastro, precisamos da data de término do contrato de locação e saber se há outro imóvel seu para incluir. Pode responder esta mensagem.', botoes: [] },
      3: { corpo: 'Olá, {{1}}! Atualização de cadastro: este é o novo número da Imob Easy. O imóvel do seu cadastro consta como alugado. Poderia nos informar a data em que o contrato de locação termina e se o(a) Sr.(a) tem outro imóvel para cadastrar?', botoes: [] },
      4: { corpo: 'Olá, {{1}}. O seu cadastro na Imob Easy está com o imóvel marcado como alugado e sem a data de término do contrato. Este é o nosso novo número de atendimento. Para atualizar o cadastro, responda com a data de término e, se houver, outro imóvel para incluir.', botoes: [] },
      5: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. Precisamos atualizar o seu cadastro: o imóvel registrado consta como alugado. Qual é a data de término do contrato de locação? E o(a) Sr.(a) tem outro imóvel para incluir no cadastro?', botoes: [] },
      // 06-08: SÓ a data do fim do contrato, sem botões
      6: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. O seu imóvel cadastrado conosco consta como alugado e precisamos atualizar o cadastro: até quando vai o contrato de locação? Pode responder esta mensagem com a data.', botoes: [] },
      7: { corpo: 'Olá, {{1}}. Atualização de cadastro: este é o novo número da Imob Easy. O imóvel do seu cadastro consta como alugado e falta a data de término do contrato de locação. Poderia nos informar?', botoes: [] },
      8: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. Precisamos atualizar o seu cadastro: o imóvel registrado consta como alugado. Qual é a data de término do contrato de locação?', botoes: [] },
      // 09-10: com botões (Informar a data / Tenho outro imóvel / Não tenho outro); a data vem na conversa
      9: { corpo: 'Olá, {{1}}! Este é o novo número da Imob Easy. O seu imóvel cadastrado conosco consta como alugado e precisamos atualizar o cadastro com a data de término do contrato e se há outro imóvel seu para incluir. Selecione uma opção:' },
      10: { corpo: 'Olá, {{1}}. Atualização de cadastro: este é o novo número da Imob Easy. O imóvel do seu cadastro consta como alugado, sem a data de término do contrato de locação. Para atualizar, toque em uma das opções abaixo.' },
    },
  },
}
const nomeDe = (g, n) => GRUPOS[g].prefixo + String(n).padStart(2, '0')
const botoesDe = (g, n) => GRUPOS[g].modelos[n].botoes || GRUPOS[g].botoes
const todos = () => Object.keys(GRUPOS).flatMap((g) => Object.keys(GRUPOS[g].modelos).map((n) => [g, Number(n)]))

function modelo(g, n) {
  const m = GRUPOS[g].modelos[n], b = botoesDe(g, n)
  const comps = [
    { type: 'BODY', text: m.corpo, example: { body_text: [['Sr. Carlos']] } },
    { type: 'FOOTER', text: RODAPE },
  ]
  if (b.length) comps.push({ type: 'BUTTONS', buttons: b.map((t) => ({ type: 'QUICK_REPLY', text: t })) })
  return { name: nomeDe(g, n), language: 'pt_BR', category: 'UTILITY', components: comps }
}

function defeitos(g, n) {
  const m = GRUPOS[g].modelos[n], d = []
  if (m.corpo.length > 1024) d.push('corpo com mais de 1024 caracteres')
  if (/^\s*\{\{1\}\}/.test(m.corpo) || /\{\{1\}\}\s*$/.test(m.corpo)) d.push('variável no começo ou no fim do corpo')
  if ((m.corpo.match(/\{\{/g) || []).length !== 1) d.push('o corpo deve ter exatamente uma variável')
  if (RODAPE.length > 60) d.push('rodapé com mais de 60 caracteres')
  for (const b of botoesDe(g, n)) if (b.length > 25) d.push('botão com mais de 25 caracteres: ' + b)
  if (botoesDe(g, n).length > 3) d.push('mais de 3 botões')
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

// "enviar vendido 1 2 alugado 3 6": a palavra muda o grupo, o número escolhe o modelo
function escolhidos(args) {
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
      const m = GRUPOS[g].modelos[n], d = defeitos(g, n), b = botoesDe(g, n)
      console.log(`${nomeDe(g, n)} | ${m.corpo.length} letras${d.length ? ' | DEFEITO: ' + d.join('; ') : ''}\n   ${m.corpo}\n   ${RODAPE}${b.length ? `\n   [${b.join('] [')}]` : '\n   (sem botões)'}\n`)
    }
    return
  }
  if (!token || !waba) { console.log('sem META_TOKEN/META_WABA_ID no ambiente: rode dentro do container do CRM'); return }
  const ja = await meta(waba + '/message_templates?limit=200&fields=id,name,status,category')
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
    if (!quais.length) { console.log('diga o grupo e os números: enviar vendido 1 2 alugado 3'); return }
    for (const [g, n] of quais) {
      const d = defeitos(g, n)
      if (d.length) { console.log(nomeDe(g, n), '-> NÃO enviado: ' + d.join('; ')); continue }
      if (existe.has(nomeDe(g, n))) { console.log(nomeDe(g, n), '-> já existe na Meta, não mandei de novo'); continue }
      const r = await meta(waba + '/message_templates', modelo(g, n))
      console.log(nomeDe(g, n), '->', r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} (provisória) | id ${r.id}`)
    }
    return
  }
  console.log('modos: conferir | enviar vendido N.. alugado N.. | situacao | apagar nome..')
}
main().catch((e) => console.log('falhou:', e.message))
