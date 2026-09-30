// O turno carrega o que ficou pendente: dois negócios, visita, e quantas
// mensagens ele mandou.
//
// OS DOIS CASOS (01/09 à noite), o mesmo formato nos dois -- duas
// mensagens do corretor caem no mesmo turno e ela responde só a última:
//   * Waldyrene: "os dois acquareles locacao é o de 02 e 03 quartos" +
//     "me evia os de venda tambem" -> mandou 4 cards de VENDA, nenhum de
//     locação (medido na execução 3768);
//   * Alice: "Cliente gostaria de agendar uma visita" + "Está
//     disponível?" -> pediu o código, mandou o card, não falou da visita.
//
// É o mesmo caminho do `pedeUnidade`: o que estava implícito no texto
// vira campo que o turno carrega, para o modelo não ter que perceber
// sozinho. São AVISOS, não paredes -- não existe ferramenta que force uma
// resposta a cobrir dois assuntos.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const rm = nos['Reservar mensagens'];
if (rm.parameters.query.includes('nay_pede_visita')) {
  console.log('  (ja aplicado) Reservar mensagens');
} else {
  const ancora = '  nay_pede_localizacao_da_unidade(texto) AS pede_unidade,';
  if (!rm.parameters.query.includes(ancora)) throw new Error('ancora do RETURNING mudou');
  rm.parameters.query = rm.parameters.query.replace(ancora, ancora +
    '\n  -- O que ele pediu neste turno, por mensagem. O `Juntar mensagens`\n' +
    '  -- combina: locacao numa linha + venda na outra vira "ambos".\n' +
    '  nay_pede_visita(texto) AS pede_visita,\n' +
    '  nay_negocio_pedido(texto) AS negocio_pedido,');
  console.log('  Reservar mensagens: + pede_visita, negocio_pedido');
}

const jm = nos['Juntar mensagens'];
if (jm.parameters.jsCode.includes('negocioPedido')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  const ancora = 'const pedeUnidade = itens.some(m => m.pede_unidade === true);';
  if (!jm.parameters.jsCode.includes(ancora)) throw new Error('ancora do pedeUnidade mudou');
  jm.parameters.jsCode = jm.parameters.jsCode.replace(ancora, ancora + '\n' +
    "// Visita pedida em QUALQUER mensagem do lote vale para o turno todo.\n" +
    "const pedeVisita = itens.some(m => m.pede_visita === true);\n" +
    "// E os negocios se SOMAM: 'locacao' numa linha e 'venda' na outra e o\n" +
    "// caso que quebrou -- ela mandou so os de venda.\n" +
    "const negs = new Set();\n" +
    "for (const m of itens) {\n" +
    "  const x = m.negocio_pedido;\n" +
    "  if (x === 'ambos') { negs.add('venda'); negs.add('locacao'); }\n" +
    "  else if (x) negs.add(x);\n" +
    "}\n" +
    "const negocioPedido = negs.size > 1 ? 'ambos' : (negs.values().next().value || null);");

  const saida = 'nome: nomeItem ? nomeItem.nome : null,';
  jm.parameters.jsCode = jm.parameters.jsCode.replace(saida, saida +
    ' pedeVisita: pedeVisita, negocioPedido: negocioPedido,');
  console.log('  Juntar mensagens: + pedeVisita, negocioPedido');
}

const ag = nos['AI Agent'];
if (ag.parameters.text.includes('negocioPedido')) {
  console.log('  (ja aplicado) AI Agent');
} else {
  const ancora = ' mensagem do corretor: ';
  if (!ag.parameters.text.includes(ancora)) throw new Error('a frase final do AI Agent mudou');
  const avisos =
    " {{ $('Juntar mensagens').first().json.qtd > 1 ? 'ATENCAO: ele mandou ' + $('Juntar mensagens').first().json.qtd + ' mensagens neste intervalo e elas vieram JUNTAS abaixo, uma por linha. Responda TODAS antes de encerrar, inclusive a primeira -- responder so a ultima e o erro mais comum aqui. ' : '' }}" +
    " {{ $('Juntar mensagens').first().json.negocioPedido === 'ambos' ? 'ATENCAO: ele falou de VENDA e de LOCACAO na mesma mensagem. Responda os DOIS: chame a ferramenta uma vez para cada negocio. Se de um deles nao houver nada, diga isso com todas as letras -- calar sobre um dos dois faz ele achar que voce esqueceu, e foi o que aconteceu em 01/09. ' : '' }}" +
    " {{ $('Juntar mensagens').first().json.pedeVisita ? 'ATENCAO: ele esta falando de VISITA. Mandar o card NAO responde isso. Use avaliar_visita (e como_funciona_a_visita quando precisar) e diga claramente se pode agendar, o que ele precisa fazer e o que voce precisa saber. Nao encerre o turno sem falar da visita. ' : '' }}" +
    ancora;
  ag.parameters.text = ag.parameters.text.replace(ancora, avisos);
  console.log('  AI Agent: avisos de turno (varias mensagens, dois negocios, visita)');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
