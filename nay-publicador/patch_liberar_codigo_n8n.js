// "5712 Alugado" passa a ser comando, nos dois nós que decidem isso.
//
// O Tel pediu em 09/09: é como ele escreve olhando a grade, que desde ontem
// lista o código primeiro. Sem esta mudança o texto cai no AGENTE -- ela
// responderia alguma coisa simpática e o imóvel continuaria na grade,
// continuaria sendo oferecido, e ninguém no grupo Easy saberia.
//
// OS DOIS NÓS PRECISAM DA MESMA REGRA, e por motivos opostos:
//   `Comando do Tel`      -> manda para o publicador (senão o comando morre)
//   `Rotear para o agente` -> DESCARTA (senão o Tel recebe resposta dupla)
//
// O literal é o mesmo de `regex_liberar.js`, que `teste_regex_liberar.js` e
// `teste_interpretar_comando.py` exercitam contra os MESMOS casos
// (`casos_comando_liberar.json`). Divergiu, fica vermelho.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

// Copiado de `regex_liberar.js` -- o código no começo e o verbo COLADO nele.
// Sem essa exigência, "o imovel 5712 foi alugado ontem" (conversa) viraria
// comando, e comando aqui posta no grupo sem desfazer.
// LIDO de `regex_liberar.js`, não redigitado. Reescrever a regex à mão aqui
// foi o primeiro erro desta mudança: as barras invertidas saíram dobradas e o
// literal que entrou no nó não casava NADA -- o comando teria morrido em
// silêncio. Ler do arquivo elimina a classe inteira de erro, e é o mesmo
// princípio do `casos_comando_liberar.json` ser fonte única.
const fonte = fs.readFileSync(
  require('path').join(__dirname, 'regex_liberar.js'), 'utf8');
const achado = fonte.match(/const CODIGO_NA_FRENTE =\s*(\/\^[\s\S]*?\/i);/);
if (!achado) throw new Error('nao achei CODIGO_NA_FRENTE em regex_liberar.js');
const CODIGO_NA_FRENTE = achado[1];

// O literal de VERBOS tambem vem do modulo, inteiro. A versao anterior deste
// patch fazia cirurgia de texto nele ('|VAGAS|VAGA)' -> '|VAGAS|VAGA|LISTA)'),
// e cada verbo novo pedia uma cirurgia diferente. Trocar o literal INTEIRO
// pelo do modulo faz o no acompanhar o arquivo sozinho.
const achadoVerbo = fonte.match(/const VERBO_NA_FRENTE =\s*(\/\^[\s\S]*?\/i);/);
if (!achadoVerbo) throw new Error('nao achei VERBO_NA_FRENTE em regex_liberar.js');
const VERBO_NA_FRENTE = achadoVerbo[1];

// Acha o literal de verbos que esta HOJE no no, seja qual for a versao.
const LITERAL_NO_NO = /\/\^\(@\?NAY\\b\[\\s,:;\.!\\-\]\*\)\?[\s\S]*?\/i/;

// A funcao inteira da taxa vai junto -- ela olha a FRASE, nao a ordem das
// palavras, entao nao cabe numa regex so. Copiar o corpo daqui seria a
// quinta copia da regra; ler do arquivo mantem uma.
const pedaco = fonte.match(
  /const TAXA_CODIGO =[\s\S]*?\n\}/);
if (!pedaco) throw new Error('nao achei o bloco da taxa em regex_liberar.js');
const BLOCO_TAXA = pedaco[0];

const ALVOS = [
  { no: 'Comando do Tel', variavel: 'up' },
  { no: 'Rotear para o agente', variavel: 't' },
];

for (const alvo of ALVOS) {
  const node = nos[alvo.no];
  if (!node) throw new Error(alvo.no + ' nao encontrado');
  let c = node.parameters.jsCode;
  const antes = c;

  // CADA MUDANCA TEM A SUA PROPRIA GUARDA. A primeira versao usava UMA guarda
  // para o bloco inteiro e, quando a taxa ja estava aplicada, ela pulava tudo
  // -- o LISTA nunca entrou e o patch disse "(ja aplicado)". Guarda de bloco
  // esconde a mudanca nova atras da antiga.

  // 1. o literal de verbos, INTEIRO, como esta em `regex_liberar.js`.
  //    Em 09/09 entrou ali o "MANDA/ENVIA + LISTA": sozinhos esses verbos
  //    viram conversa comum do Tel, mas colados em LISTA sao a forma que ele
  //    usa -- e sem isto "Nay manda a lista de salas comerciais" nao casa
  //    NADA (nem este literal, nem a regex de envio, que exige preposicao no
  //    fim) e o comando morre em silencio.
  if (!c.includes(VERBO_NA_FRENTE)) {
    const atual = c.match(LITERAL_NO_NO);
    if (!atual) throw new Error('nao achei o literal de verbos em ' + alvo.no);
    c = c.split(atual[0]).join(VERBO_NA_FRENTE);
    console.log('  ' + alvo.no + ': literal de verbos atualizado');
  }

  // 2. "5712 Alugado" -- o codigo na frente
  const ancora = VERBO_NA_FRENTE + '.test(' + alvo.variavel + ')';
  if (!c.includes(ancora)) {
    throw new Error('ancora da gramatica mudou em ' + alvo.no + ': ' + ancora);
  }
  if (!c.includes('|| ' + CODIGO_NA_FRENTE + '.test(' + alvo.variavel + ')')) {
    c = c.replace(ancora,
      ancora + '\n' +
      '      // "5712 Alugado" -- o codigo na frente (Tel, 09/09). Mesmo literal\n' +
      '      // de `regex_liberar.js`, exercitado por `casos_comando_liberar.json`.\n' +
      '      || ' + CODIGO_NA_FRENTE + '.test(' + alvo.variavel + ')\n' +
      '      || ehComandoDeTaxa(' + alvo.variavel + ')');
    console.log('  ' + alvo.no + ': + "5712 Alugado" e a taxa');
  }

  // 3. a funcao da taxa, no topo, uma vez so
  if (!c.includes('function ehComandoDeTaxa')) {
    c = '// LIDO de `regex_liberar.js` pelo patch -- nao editar aqui.\n'
      + BLOCO_TAXA + '\n\n' + c;
  }

  if (c === antes) console.log('  (nada a fazer) ' + alvo.no);
  node.parameters.jsCode = c;
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
