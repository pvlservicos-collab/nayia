// Segundo patch do fluxo, com o que a auditoria de 01/09 achou.
//
// CINCO EDICOES, e o mesmo principio do primeiro patch: quem decide e o
// banco; o n8n so carrega o resultado. Nenhuma regra ganha copia nova.
//
//   1. Filtrar e normalizar  -> captura `referenceMessageId`, o campo que
//                               a Z-API MANDA de verdade
//   2. Gravar na fila        -> devolve `codigos_citados` (valor ja tirado)
//   3. Juntar mensagens      -> propaga os dois
//   4. AI Agent              -> avisa que e resposta a mensagem citada
//   5. Achar codigo na resp. -> usa os codigos do banco, nao a regex crua
//   6. imovel_por_codigo     -> descricao sem numero de unidade
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;

function achar(nome) {
  const n = wf.nodes.find((x) => x.name === nome);
  if (!n) throw new Error('no nao encontrado: ' + nome);
  return n;
}
function trocar(no, campo, de, para, marca, rotulo) {
  const v = no.parameters[campo];
  // A marca e um trecho que SO existe depois da edicao. Comparar pelo
  // inicio do texto novo nao serve: ele quase sempre comeca com o texto
  // antigo, entao "ja aplicado" dava sempre verdadeiro e a edicao era
  // pulada em silencio.
  if (v.includes(marca)) { console.log('  (ja aplicado) ' + rotulo); return; }
  if (!v.includes(de)) throw new Error('ancora mudou em ' + rotulo);
  no.parameters[campo] = v.replace(de, para);
  if (!no.parameters[campo].includes(marca)) throw new Error('a marca nao apareceu em ' + rotulo);
  console.log('  ' + rotulo);
}

// ---------- 1. Filtrar e normalizar: o campo REAL da citacao ----------
// A CAUSA DE UM DIA PERDIDO: o codigo procurava `referencedMessage` e o
// CLAUDE.md registrava "a Z-API nao manda mensagem citada". Os payloads
// capturados em `payload_estrutura` mostram `referenceMessageId` -- outro
// nome. A Z-API manda o ID da mensagem citada, nao o conteudo dela.
//
// Com o ID sozinho ainda nao da para saber QUAL imovel (falta guardar o
// messageId dos cards que a gente manda). Mas da para saber que E uma
// resposta -- e isso ja basta para ela PERGUNTAR em vez de chutar, que e
// o que o Tel pediu.
const filtrar = achar('Filtrar e normalizar');
trocar(filtrar, 'jsCode',
  'const ref = b.referencedMessage || null;',
  'const ref = b.referencedMessage || null;\n' +
  '// `referenceMessageId` e o nome REAL do campo (visto em payload_estrutura,\n' +
  '// 01/09). So o ID chega, nunca o texto -- entao serve para saber que ELE\n' +
  '// respondeu citando algo, e ela perguntar de qual imovel se trata.\n' +
  'const refId = b.referenceMessageId || (ref && ref.messageId) || null;',
  'referenceMessageId', 'Filtrar e normalizar: captura referenceMessageId');

trocar(filtrar, 'jsCode', 'citado: citado,',
  'citado: citado,\n    citadoId: refId,',
  'citadoId: refId', 'Filtrar e normalizar: propaga citadoId');

// ---------- 2. Gravar na fila: codigos ja sem os valores ----------
const grava = achar('Gravar na fila');
trocar(grava, 'query',
  `       nay_pede_localizacao_da_unidade(NULLIF($4,'null')) AS pede_unidade`,
  `       nay_pede_localizacao_da_unidade(NULLIF($4,'null')) AS pede_unidade,\n` +
  `       -- Os codigos que ELE escreveu, com os VALORES ja tirados: "paga\n` +
  `       -- ate 4000" nao e o imovel 4000. A regra mora em\n` +
  `       -- valor_nao_e_codigo.sql e aqui so vem o resultado.\n` +
  `       nay_codigos_citados(coalesce(NULLIF($4,'null'),'')) AS codigos_citados`,
  'nay_codigos_citados', 'Gravar na fila: codigos_citados');

// ---------- 3. Juntar mensagens ----------
const junta = achar('Juntar mensagens');
trocar(junta, 'jsCode',
  'const pedeUnidade = itens.some(m => m.pede_unidade === true);',
  'const pedeUnidade = itens.some(m => m.pede_unidade === true);\n' +
  '// Ele respondeu citando alguma mensagem? So o ID chega, nunca o texto.\n' +
  'const citadoId = (itens.map(m => m.citadoId).filter(Boolean)[0]) || null;\n' +
  '// Uniao dos codigos que ele escreveu, sem os valores.\n' +
  'const codigosDele = [...new Set(itens.flatMap(m => m.codigos_citados || []))];',
  'const codigosDele', 'Juntar mensagens: citadoId e codigosDele');

trocar(junta, 'jsCode',
  'return [{ json: { pedeUnidade: pedeUnidade, telefone: itens[0].telefone,',
  'return [{ json: { pedeUnidade: pedeUnidade, citadoId: citadoId, ' +
  'codigosDele: codigosDele, telefone: itens[0].telefone,',
  'codigosDele: codigosDele', 'Juntar mensagens: propaga no retorno');

// ---------- 4. AI Agent: avisa que e citacao ----------
const agente = achar('AI Agent');
trocar(agente, 'text', ' mensagem do corretor: ',
  " {{ ($('Juntar mensagens').first().json.citadoId && " +
  "!$('Juntar mensagens').first().json.citado) ? " +
  "'ATENCAO: ele respondeu CITANDO uma mensagem anterior, e voce NAO consegue ver " +
  'qual e. Se a pergunta dele depende de saber de qual imovel se trata e ele nao ' +
  'escreveu o codigo agora, PERGUNTE de qual imovel ele fala -- use a ferramenta ' +
  'escalar_ao_tel so depois de saber. NUNCA suponha que e o ultimo imovel que ' +
  "voces conversaram nem o ultimo postado nos grupos. ' : '' }} mensagem do corretor: ",
  'citadoId && ', 'AI Agent: avisa quando e citacao nao resolvida');

// ---------- 5. Achar codigo na resposta: codigo do banco ----------
// O `solto()` pegava qualquer numero de 3 a 5 digitos do que ele escreveu.
// "me manda as fotos, ele paga ate 4000" mandava as 18 fotos do imovel
// 4000, que existe. `codigosDele` ja vem sem os valores.
const fotos = achar('Achar codigo na resposta');
trocar(fotos, 'jsCode',
  'const codigos = todos.length ? [...new Set(todos)]\n' +
  '  : [porRotulo(citou) || solto(citou) || porRotulo(escreveu) || solto(escreveu)].filter(Boolean);',
  '// `codigosDele` vem de `nay_codigos_citados`, que tira os VALORES antes\n' +
  '// de procurar codigo -- "paga ate 4000" nao e o imovel 4000. O `solto()`\n' +
  '// cru fica so para a citacao, onde nao ha alternativa.\n' +
  'const dele = j.codigosDele || [];\n' +
  'const codigos = todos.length ? [...new Set(todos)]\n' +
  '  : [porRotulo(citou) || porRotulo(escreveu) || dele[0] || solto(citou)].filter(Boolean);',
  'const dele = j.codigosDele', 'Achar codigo na resposta: valor deixa de virar alvo de foto');

// ---------- 6. imovel_por_codigo: descricao sem numero de unidade ----------
const tool = achar('imovel_por_codigo');
trocar(tool, 'query',
  `         ' O anuncio deste imovel diz: "' || replace(i.descricao, chr(10), ' ')`,
  `         ' O anuncio deste imovel diz: "' ||\n` +
  `         -- `+'`nay_descricao_segura`'+` tira o numero da unidade do texto do\n` +
  `         -- anuncio. Tres anuncios publicam "apto 801", "apart. 601" -- que\n` +
  `         -- o site publique nao autoriza a Nay a entregar de mao beijada.\n` +
  `         replace(nay_descricao_segura(i.descricao), chr(10), ' ')`,
  'nay_descricao_segura', 'imovel_por_codigo: descricao raspada');

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
