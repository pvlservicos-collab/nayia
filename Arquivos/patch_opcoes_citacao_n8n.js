// Quando a mensagem citada fala de MAIS DE UM imóvel, a pergunta vem com
// a lista -- em vez de "de qual imóvel você fala?".
//
// O CASO (Alice, 21h57): ela marcou a mensagem em que a Nay tinha listado
// dois imóveis do Acquarelle e perguntou "então está disponível? certo?".
// A Nay respondeu "não consigo identificar qual imóvel foi citado. me
// manda o código". A informação estava na mensagem que ela apontou.
//
// Perguntar continua certo -- dois códigos ali dentro é ambiguidade de
// verdade, e o Tel foi explícito: nunca supor. O que muda é perguntar
// COM as opções, que é uma pergunta que se responde num toque.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const rm = nos['Reservar mensagens'];
if (rm.parameters.query.includes('nay_opcoes_da_citacao')) {
  console.log('  (ja aplicado) Reservar mensagens');
} else {
  const ancora = '  nay_imovel_da_citacao(citado_id) AS codigo_citado;';
  if (!rm.parameters.query.includes(ancora)) throw new Error('ancora da citacao mudou');
  rm.parameters.query = rm.parameters.query.replace(ancora,
    '  nay_imovel_da_citacao(citado_id) AS codigo_citado,\n' +
    '  -- Quando a mensagem citada fala de mais de um imovel, a lista dela.\n' +
    '  nay_opcoes_da_citacao(citado_id) AS opcoes_citacao;');
  console.log('  Reservar mensagens: + opcoes_citacao');
}

const jm = nos['Juntar mensagens'];
if (jm.parameters.jsCode.includes('opcoesCitacao')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  const ancora = "nome: nomeItem ? nomeItem.nome : null,";
  if (!jm.parameters.jsCode.includes(ancora)) throw new Error('a saida do nome mudou');
  jm.parameters.jsCode = jm.parameters.jsCode.replace(ancora, ancora +
    " opcoesCitacao: (itens.map(m => m.opcoes_citacao).filter(Boolean)[0]) || null,");
  console.log('  Juntar mensagens: + opcoesCitacao');
}

const ag = nos['AI Agent'];
const marca = 'opcoesCitacao';
if (ag.parameters.text.includes(marca)) {
  console.log('  (ja aplicado) AI Agent');
} else {
  const de = "{{ ($('Juntar mensagens').first().json.citadoId && !$('Juntar mensagens').first().json.citado) ? 'ATENCAO: ele respondeu CITANDO uma mensagem anterior, e voce NAO consegue ver qual e.";
  if (!ag.parameters.text.includes(de)) throw new Error('o aviso de citacao mudou no AI Agent');
  ag.parameters.text = ag.parameters.text.replace(de,
    "{{ $('Juntar mensagens').first().json.opcoesCitacao ? 'ATENCAO: ele MARCOU uma mensagem sua que falava de MAIS DE UM imovel. Nao da para saber qual -- entao PERGUNTE qual deles, mostrando esta lista exatamente como veio:' + String.fromCharCode(10) + $('Juntar mensagens').first().json.opcoesCitacao + String.fromCharCode(10) + 'NAO escolha um por conta propria e NAO peca o codigo de novo sem mostrar a lista. ' : '' }} " +
    de);
  console.log('  AI Agent: pergunta com a lista quando a citacao tem varios');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
