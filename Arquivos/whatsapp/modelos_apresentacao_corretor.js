// Cadastro Imobeasy para corretores (Pedro, 19/10/2026): "o que eu quero é algo mais sobre cadastro: pode pôr assim
// no título 'Cadastro Imobeasy', aí explica embaixo quem somos, e embaixo o botão, mas de forma que seja aprovado
// como Utilidade". Botões: Pedir imóvel por número / Grupo de corretores. Rodapé Imobeasy.
//
// O que a conta tem hoje (foto de 19/10, 75 modelos): NENHUM de apresentação ao corretor. Com esses botões só o
// l1_util_12 ("Atualização de cadastro: novo número para corretores parceiros"), que mente para quem não tem
// cadastro. Os 10 de apresentação honesta (l5_util_01-10) caíram para Marketing. O que a revisão da Meta deixou em
// Utilidade sempre tinha a cara de aviso de conta: cabeçalho de cadastro, "pendente", "para concluir, selecione".
// Por isso o desenho aqui é fixo: CABEÇALHO "Cadastro Imobeasy" + corpo com quem somos (imobiliária em Manaus,
// parceria com corretores, imóvel da nossa carteira para o cliente dele) amarrado a um cadastro de parceiro EM
// ANDAMENTO ("iniciado", "em andamento", "pendente", "para concluir"), sem dizer que ele já tinha cadastro.
// As variações mudam só a ordem (cadastro antes ou depois do quem somos) e as palavras do cadastro.
//
// Conferir (sem token, só mostra e valida):   node Arquivos/whatsapp/modelos_apresentacao_corretor.js conferir
// Dentro do CRM (quem tem o token):           docker exec -i crm-imobeasy node - enviar 1 2 3 < este arquivo
//                                             docker exec -i crm-imobeasy node - situacao        < este arquivo
//                                             docker exec -i crm-imobeasy node - apagar nome ... < este arquivo
// Criar modelo NÃO manda mensagem a ninguém. A categoria que o POST devolve é PROVISÓRIA: a revisão muda minutos
// depois; conferir com `situacao` (ou na aba WhatsApp › Mensagens do admin, que lê a cada 10 min).
const token = process.env.META_TOKEN, waba = process.env.META_WABA_ID
const CABECALHO = 'Cadastro Imobeasy'
const RODAPE = 'Imobeasy'
const BOTOES = ['Pedir imóvel por número', 'Grupo de corretores']
const PREFIXO = 'cadastro_imobeasy_'
const MODELOS = {
  // 01-05: quem somos primeiro, o cadastro fecha
  1: { corpo: 'Olá, {{1}}! A Imob Easy é uma imobiliária em Manaus que trabalha em parceria com corretores: os imóveis da nossa carteira ficam disponíveis para você fechar com o seu cliente. O seu cadastro de corretor parceiro está em andamento. Para concluir, selecione uma opção:' },
  2: { corpo: 'Olá, {{1}}. Somos a Imob Easy, imobiliária em Manaus. Trabalhamos em parceria com corretores: o imóvel é nosso, o cliente é seu e a comissão é dividida. O seu cadastro de parceiro aguarda uma confirmação. Selecione como prefere ser atendido:' },
  3: { corpo: 'Olá, {{1}}. A Imob Easy, imobiliária em Manaus, atende corretores parceiros por este número: você pede o imóvel da nossa carteira pelo código e recebe a ficha e as fotos para o seu cliente. O seu cadastro de parceiro está em andamento. Para concluir, selecione uma opção:' },
  4: { corpo: 'Olá, {{1}}! Este é o número de cadastro e atendimento a corretores parceiros da Imob Easy, imobiliária em Manaus. Na parceria, os imóveis da nossa carteira ficam disponíveis para você fechar com o seu cliente. Para concluir o seu cadastro, selecione uma opção:' },
  5: { corpo: 'Olá, {{1}}! A Imob Easy é uma imobiliária em Manaus e trabalha em formato de parceria: você atende o seu cliente com os imóveis da nossa carteira e a comissão é dividida. Falta uma escolha para concluir o seu cadastro de corretor parceiro. Selecione uma opção:' },
  // 06-10: o cadastro primeiro, quem somos explica
  6: { corpo: 'Olá, {{1}}. O seu cadastro de corretor parceiro na Imob Easy foi iniciado. Somos uma imobiliária em Manaus e os imóveis da nossa carteira são liberados para os parceiros fecharem com os seus clientes. Para concluir o cadastro, selecione uma opção:' },
  7: { corpo: 'Olá, {{1}}! Cadastro de corretor parceiro pendente de confirmação. A Imob Easy é uma imobiliária em Manaus que divide os imóveis da sua carteira com corretores parceiros, com ficha, fotos e comissão dividida. Selecione a forma de atendimento:' },
  8: { corpo: 'Olá, {{1}}! O seu cadastro de corretor parceiro na Imob Easy está pendente. Somos uma imobiliária em Manaus que trabalha em formato de parceria: você atende o seu cliente com os imóveis da nossa carteira e a comissão é dividida. Selecione como prefere ser atendido:' },
  9: { corpo: 'Olá, {{1}}. Confirmação de cadastro: a Imob Easy, imobiliária em Manaus, trabalha em parceria com corretores e libera os imóveis da sua carteira para os parceiros fecharem com os seus clientes. Para ativar o seu cadastro de parceiro, selecione uma opção:' },
  10: { corpo: 'Olá, {{1}}. O seu número foi incluído no cadastro de corretores parceiros da Imob Easy, imobiliária em Manaus. Na parceria, o imóvel é nosso, o cliente é seu e a comissão é dividida. Para concluir o cadastro, selecione como prefere receber os imóveis:' },
  // 11-20 (2ª leva, Pedro: "pode encurtar contanto que mantenha a ideia"): mais curtas, cadastro na frente
  11: { corpo: 'Olá, {{1}}! O seu cadastro de corretor parceiro na Imob Easy, imobiliária em Manaus, está pendente. Na parceria, os imóveis da nossa carteira ficam disponíveis para o seu cliente. Para concluir, selecione uma opção:' },
  12: { corpo: 'Olá, {{1}}. Cadastro de parceiro em andamento na Imob Easy, imobiliária em Manaus que trabalha em parceria com corretores. Para concluir, selecione como prefere receber os imóveis da nossa carteira:' },
  13: { corpo: 'Olá, {{1}}! Para concluir o seu cadastro de corretor parceiro na Imob Easy (imobiliária em Manaus, imóveis da nossa carteira em parceria com corretores), selecione uma opção:' },
  14: { corpo: 'Olá, {{1}}. O seu cadastro de parceiro na Imob Easy aguarda uma escolha. Somos uma imobiliária em Manaus e os imóveis da nossa carteira ficam disponíveis para você fechar com o seu cliente. Selecione:' },
  15: { corpo: 'Olá, {{1}}! Cadastro pendente: a Imob Easy, imobiliária em Manaus, trabalha em parceria com corretores. Para concluir o seu cadastro de parceiro e receber os imóveis da nossa carteira, selecione uma opção:' },
  16: { corpo: 'Olá, {{1}}. Falta uma etapa no seu cadastro de corretor parceiro da Imob Easy, imobiliária em Manaus. Na parceria, o imóvel é nosso e o cliente é seu. Selecione como prefere ser atendido:' },
  17: { corpo: 'Olá, {{1}}! O seu cadastro de corretor parceiro na Imob Easy foi iniciado. Somos uma imobiliária em Manaus e trabalhamos em parceria: imóveis da nossa carteira para o seu cliente. Para concluir, selecione:' },
  18: { corpo: 'Olá, {{1}}. Confirmação de cadastro de parceiro na Imob Easy, imobiliária em Manaus. Os imóveis da nossa carteira ficam disponíveis para você fechar com o seu cliente. Para ativar, selecione uma opção:' },
  19: { corpo: 'Olá, {{1}}! Etapa pendente do seu cadastro de corretor parceiro na Imob Easy, imobiliária em Manaus. Os imóveis da nossa carteira são liberados em parceria para o seu cliente. Selecione como prefere ser atendido:' },
  20: { corpo: 'Olá, {{1}}. O seu cadastro de parceiro na Imob Easy, imobiliária em Manaus, está em andamento. Em parceria, você fecha os imóveis da nossa carteira com o seu cliente. Para concluir, selecione uma opção:' },
  // 21-30 (3ª leva): o molde das que seguraram Utilidade na revisão (02, 06, 08, 10): 1ª frase é o cadastro
  // ("foi iniciado" / "está pendente" / "aguarda uma confirmação"), 2ª o quem somos curto, 3ª "selecione".
  // Caíram as que abriam com a apresentação, "número de atendimento", "receber ficha e fotos" ou "ativar".
  21: { corpo: 'Olá, {{1}}. O seu cadastro de corretor parceiro na Imob Easy foi iniciado. Somos uma imobiliária em Manaus e trabalhamos em parceria: o imóvel é nosso, o cliente é seu e a comissão é dividida. Para concluir o cadastro, selecione uma opção:' },
  22: { corpo: 'Olá, {{1}}! O seu cadastro de parceiro na Imob Easy está pendente. Somos uma imobiliária em Manaus e os imóveis da nossa carteira são liberados para os corretores parceiros. Selecione como prefere ser atendido:' },
  23: { corpo: 'Olá, {{1}}. O seu cadastro de corretor parceiro na Imob Easy aguarda uma confirmação. Somos uma imobiliária em Manaus que trabalha em parceria com corretores. Para concluir, selecione uma opção:' },
  24: { corpo: 'Olá, {{1}}! O seu cadastro de parceiro na Imob Easy, imobiliária em Manaus, foi iniciado. Na parceria, o imóvel é nosso, o cliente é seu e a comissão é dividida. Selecione como prefere ser atendido:' },
  25: { corpo: 'Olá, {{1}}. O seu número foi incluído no cadastro de corretores parceiros da Imob Easy. Somos uma imobiliária em Manaus e os imóveis da nossa carteira são liberados para os parceiros. Para concluir o cadastro, selecione uma opção:' },
  26: { corpo: 'Olá, {{1}}! O seu cadastro de corretor parceiro na Imob Easy está pendente de uma escolha. Somos uma imobiliária em Manaus e trabalhamos em parceria com corretores. Selecione como prefere ser atendido:' },
  27: { corpo: 'Olá, {{1}}. O seu cadastro de parceiro na Imob Easy foi iniciado. Somos uma imobiliária em Manaus: o imóvel é nosso, o cliente é seu e a comissão é dividida. Para concluir o cadastro, selecione uma opção:' },
  28: { corpo: 'Olá, {{1}}! O seu cadastro de corretor parceiro na Imob Easy aguarda uma confirmação. Somos uma imobiliária em Manaus e os imóveis da nossa carteira são liberados em parceria. Selecione como prefere ser atendido:' },
  29: { corpo: 'Olá, {{1}}. O seu cadastro de corretor parceiro na Imob Easy está em andamento. Somos uma imobiliária em Manaus que trabalha em parceria com os corretores da cidade. Para concluir o cadastro, selecione uma opção:' },
  30: { corpo: 'Olá, {{1}}! O seu cadastro de parceiro na Imob Easy está pendente. Somos uma imobiliária em Manaus e trabalhamos em parceria: o imóvel é nosso e o cliente é seu. Para concluir, selecione como prefere ser atendido:' },
  // 31-40 (4ª leva, Pedro 20/10: "vc criou umas variações muito próximas umas das outras ... precisa variar mais mantendo
  // o sentido, muda ordem das palavras, encurta tudo"): mesmo sentido (cadastro de parceiro em aberto + quem somos +
  // escolha), mas cada uma com outra abertura, outra ordem e bem mais curta.
  31: { corpo: 'Cadastro de parceiro pendente, {{1}}. Somos a Imob Easy, imobiliária em Manaus que trabalha com corretores. Escolha uma opção para concluir:' },
  32: { corpo: 'Oi, {{1}}. Seu cadastro como corretor parceiro ainda não foi concluído. A Imob Easy, de Manaus, divide a carteira de imóveis com parceiros. Escolha abaixo:' },
  33: { corpo: 'Prezado(a) {{1}}, o seu cadastro de parceiro na Imob Easy, imobiliária de Manaus, foi aberto. Para finalizar, toque em uma das opções:' },
  34: { corpo: 'Olá, {{1}}. Para finalizar o seu cadastro de corretor parceiro, escolha como quer receber os imóveis da Imob Easy, imobiliária em Manaus:' },
  35: { corpo: 'Seu cadastro na rede de parceiros da Imob Easy está quase pronto, {{1}}. Somos de Manaus e trabalhamos com imóveis em parceria. Falta só escolher:' },
  36: { corpo: 'Olá, {{1}}! Etapa final do cadastro de corretor parceiro. Imob Easy, imobiliária em Manaus: imóveis para você fechar com os seus clientes. Selecione:' },
  37: { corpo: 'Aviso de cadastro para {{1}}: o acesso de corretor parceiro da Imob Easy, em Manaus, aguarda a sua escolha. Toque em uma opção:' },
  38: { corpo: 'Olá, {{1}}. O seu cadastro de parceiro na Imob Easy, imobiliária em Manaus, está em aberto. Imóvel nosso, cliente seu. Conclua tocando abaixo:' },
  39: { corpo: 'Status do cadastro de {{1}}: em andamento. Imob Easy, imobiliária de Manaus que atende corretores parceiros. Para concluir, escolha uma opção:' },
  40: { corpo: 'Olá, {{1}}! Confirme o seu cadastro de corretor parceiro na Imob Easy. Somos de Manaus e a nossa carteira fica liberada para parceiros. Escolha:' },
}
const nomeDe = (n) => PREFIXO + String(n).padStart(2, '0')

function modelo(n) {
  const m = MODELOS[n]
  return {
    name: nomeDe(n), language: 'pt_BR', category: 'UTILITY',
    components: [
      { type: 'HEADER', format: 'TEXT', text: m.cabecalho || CABECALHO },
      { type: 'BODY', text: m.corpo, example: { body_text: [['Carlos']] } },
      { type: 'FOOTER', text: RODAPE },
      { type: 'BUTTONS', buttons: BOTOES.map((t) => ({ type: 'QUICK_REPLY', text: t })) },
    ],
  }
}

function defeitos(n) {
  const m = MODELOS[n], d = []
  if ((m.cabecalho || CABECALHO).length > 60) d.push('cabeçalho com mais de 60 caracteres')
  if (m.corpo.length > 1024) d.push('corpo com mais de 1024 caracteres')
  if (/^\s*\{\{1\}\}/.test(m.corpo) || /\{\{1\}\}\s*$/.test(m.corpo)) d.push('variável no começo ou no fim do corpo')
  if ((m.corpo.match(/\{\{/g) || []).length !== 1) d.push('o corpo deve ter exatamente uma variável')
  if (RODAPE.length > 60) d.push('rodapé com mais de 60 caracteres')
  for (const b of BOTOES) if (b.length > 25) d.push('botão com mais de 25 caracteres: ' + b)
  if (!/^[a-z0-9_]+$/.test(nomeDe(n))) d.push('nome com caractere fora de a-z, 0-9 e _')
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

async function main() {
  const modo = process.argv[2] || 'conferir'
  if (modo === 'conferir') {
    for (const n of Object.keys(MODELOS)) {
      const m = MODELOS[n], d = defeitos(n)
      console.log(`${nomeDe(n)} | ${m.corpo.length} letras${d.length ? ' | DEFEITO: ' + d.join('; ') : ''}\n   *${m.cabecalho || CABECALHO}*\n   ${m.corpo}\n   ${RODAPE}\n   [${BOTOES.join('] [')}]\n`)
    }
    return
  }
  if (!token || !waba) { console.log('sem META_TOKEN/META_WABA_ID no ambiente: rode dentro do container do CRM'); return }
  const ja = await meta(waba + '/message_templates?limit=200&fields=id,name,status,category')
  const existe = new Map((ja.data || []).map((t) => [t.name, t]))
  if (modo === 'situacao') {
    for (const n of Object.keys(MODELOS)) {
      const t = existe.get(nomeDe(n))
      console.log(nomeDe(n), t ? `${t.status} | ${t.category}` : '(não enviado)')
    }
    return
  }
  if (modo === 'apagar') {
    for (const nome of process.argv.slice(3)) {
      if (!nome.startsWith(PREFIXO)) { console.log(nome, '-> só apago os ' + PREFIXO + '*'); continue }
      const r = await meta(`${waba}/message_templates?name=${nome}`, null, 'DELETE')
      console.log(nome, '->', r.error ? 'ERRO: ' + (r.error.error_user_msg || r.error.message) : 'apagado')
    }
    return
  }
  if (modo === 'enviar') {
    const quais = process.argv.slice(3).map(Number).filter((n) => MODELOS[n])
    if (!quais.length) { console.log('diga os números: enviar 1 2 3'); return }
    for (const n of quais) {
      const d = defeitos(n)
      if (d.length) { console.log(nomeDe(n), '-> NÃO enviado: ' + d.join('; ')); continue }
      if (existe.has(nomeDe(n))) { console.log(nomeDe(n), '-> já existe na Meta, não mandei de novo'); continue }
      const r = await meta(waba + '/message_templates', modelo(n))
      console.log(nomeDe(n), '->', r.error ? 'RECUSADO: ' + (r.error.error_user_msg || r.error.message) : `enviado: ${r.status} | ${r.category} (provisória) | id ${r.id}`)
    }
    return
  }
  console.log('modos: conferir | enviar N.. | situacao | apagar nome..')
}
main().catch((e) => console.log('falhou:', e.message))
