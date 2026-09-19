// Ela para de PROMETER fotos que o sistema não vai mandar.
//
// O CASO, encontrado testando o conserto da Waldyrene em 02/09: com o
// texto real dela ("os dois acquareles locacao é o de 02 e 03 quartos" +
// "me evia os de venda tambem"), a Nay respondeu "vou te enviar as
// informações e **as fotos completas** dos imóveis de locação e venda".
// Medido no mesmo instante: `nay_deve_mandar_fotos` devolve FALSO para
// esse turno -- ele não pediu foto nenhuma. Ou seja, ela anunciou um
// álbum que não sai.
//
// A origem não é o modelo inventando: está escrito no prompt, com todas
// as letras -- "Avise antes em uma linha: vou te enviar as informacoes e
// as fotos completas, segue".
//
// É o padrão que o CLAUDE.md já descreve: CAPACIDADE AUSENTE VIRA
// PROMESSA. Quem manda foto é o nó, e só quando o corretor pediu; o
// modelo não decide isso e não deveria falar como se decidisse.
//
// Duas mudanças:
//   1. a frase do prompt não promete mais foto;
//   2. o turno passa a CARREGAR se as fotos vão sair (`vaoSairFotos`),
//      calculado pela MESMA função que o portão usa. Assim ela oferece
//      quando não vão, em vez de anunciar.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

// ---------- 1. a frase que promete ----------
const ag = nos['AI Agent'];
let sm = ag.parameters.options.systemMessage;
const de = 'Avise antes em uma linha: vou te enviar as informacoes e as fotos completas, segue.';
const para = 'Avise antes em uma linha: vou te enviar as informacoes, segue. ' +
  'NAO prometa foto nessa frase: quem manda foto e o sistema, e so quando ele pede.';
if (sm.includes(para)) {
  console.log('  (ja aplicado) frase do prompt');
} else {
  if (!sm.includes(de)) throw new Error('a frase da promessa mudou');
  ag.parameters.options.systemMessage = sm.replace(de, para);
  console.log('  prompt: a frase deixa de prometer fotos');
}

// ---------- 2. o turno sabe se as fotos vao sair ----------
const rm = nos['Reservar mensagens'];
if (rm.parameters.query.includes('nay_deve_mandar_fotos')) {
  console.log('  (ja aplicado) Reservar mensagens');
} else {
  const ancora = '  nay_pede_visita(texto) AS pede_visita,';
  if (!rm.parameters.query.includes(ancora)) throw new Error('ancora do pede_visita mudou');
  rm.parameters.query = rm.parameters.query.replace(ancora, ancora +
    '\n  -- A MESMA funcao que o portao de fotos usa na hora de enviar.\n' +
    '  -- Sem isso ela anuncia album que nao sai.\n' +
    '  nay_deve_mandar_fotos(telefone, texto) AS manda_fotos,');
  console.log('  Reservar mensagens: + manda_fotos');
}

const jm = nos['Juntar mensagens'];
if (jm.parameters.jsCode.includes('vaoSairFotos')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  const ancora = 'const pedeVisita = itens.some(m => m.pede_visita === true);';
  if (!jm.parameters.jsCode.includes(ancora)) throw new Error('ancora do pedeVisita mudou');
  jm.parameters.jsCode = jm.parameters.jsCode.replace(ancora, ancora + '\n' +
    "// Pedido de foto em QUALQUER mensagem do lote vale para o turno todo --\n" +
    "// e o portao de envio le o texto junto, entao tem que ser OR aqui.\n" +
    "const vaoSairFotos = itens.some(m => m.manda_fotos === true);");
  const saida = 'pedeVisita: pedeVisita,';
  jm.parameters.jsCode = jm.parameters.jsCode.replace(saida, saida + ' vaoSairFotos: vaoSairFotos,');
  console.log('  Juntar mensagens: + vaoSairFotos');
}

if (ag.parameters.text.includes('vaoSairFotos')) {
  console.log('  (ja aplicado) AI Agent');
} else {
  const ancora = ' mensagem do corretor: ';
  ag.parameters.text = ag.parameters.text.replace(ancora,
    " {{ $('Juntar mensagens').first().json.vaoSairFotos ? 'as fotos VAO sair junto com sua resposta -- pode avisar que estao vindo. ' : 'as fotos NAO vao sair neste turno, porque ele nao pediu. Entao NAO diga que vai mandar foto, nem \"segue as fotos\", nem \"vou te enviar as fotos\": OFERECA, perguntando se ele quer. ' }}" +
    ancora);
  console.log('  AI Agent: sabe se as fotos vao sair');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
