/*
 * De QUAL imovel sao as fotos -- no `Achar codigo na resposta`.
 *
 * ATENCAO, isto mudou em 01/09. Este arquivo testava um `pediuFoto` que
 * NAO EXISTE MAIS no no: o portao "deve mandar foto?" virou a funcao SQL
 * `nay_deve_mandar_fotos`, chamada dentro da query do `Buscar fotos do
 * agente`. Os dez casos antigos passavam verdes e nao provavam nada sobre
 * producao -- foi essa cegueira que deixou passar, por 20 suites verdes, o
 * bug do envelope de audio (o portao abria para 100% dos audios).
 *
 * Quem prova o portao agora e `teste_consentimento_fotos.sql`.
 * O que sobra AQUI, e continua sendo JavaScript no no, e a escolha do
 * CODIGO: de qual imovel sao as fotos que vao sair.
 *
 * As duas regras que vieram de caso real:
 *
 * 1) O codigo se le primeiro na RESPOSTA DELA, e todos, nao so o
 *    primeiro. Em 30/08 o Gustavo pediu "me passa as informacoes dos 3":
 *    ela mandou tres cards e so as fotos do primeiro sairiam.
 *
 * 2) "Codigo: NNNN" ganha de numero solto, e numero colado a ponto ou
 *    virgula nao conta. A Sebastiana pediu foto do 3210 citando um card
 *    com "valor: 900.000" -- o 900 virava o codigo e nao vinha foto
 *    nenhuma.
 *
 * As regex aqui sao COPIA das do no. Divergiram? o teste passa e a
 * producao quebra (Parte 4.3 do HISTORICO). Ao mexer no no, mexer aqui.
 *
 * Uso (precisa do Node do container):
 *   scp teste_gatilho_fotos.js root@SERVIDOR:/tmp/f.js
 *   ssh root@SERVIDOR 'docker cp /tmp/f.js n8n-viux-n8n-1:/tmp/f.js \
 *     && docker exec n8n-viux-n8n-1 node /tmp/f.js'
 */
const porRotulo = t => { const m = String(t||'').match(/C[óo]digo:\s*(\d{3,5})/i); return m ? m[1] : null; };
const solto     = t => { const m = String(t||'').match(/(?<![\d.,])(\d{3,5})(?![\d.,])/); return m ? m[1] : null; };

// Copia do no. `dele` vem de `nay_codigos_citados`, que tira os VALORES
// antes de procurar codigo -- "paga ate 4000" nao e o imovel 4000.
function decidir(saida, citou, escreveu, dele) {
  const todos = [...String(saida||'').matchAll(/C[óo]digo:\s*(\d{3,5})/gi)].map(m => m[1]);
  const codigos = todos.length ? [...new Set(todos)]
    : [porRotulo(citou) || porRotulo(escreveu) || (dele||[])[0] || solto(citou)].filter(Boolean);
  return { codigo: codigos[0] || '0', codigos: codigos.length ? codigos : ['0'] };
}

const CARD_CITADO = 'Morada dos Passaros\nvalor: 900.000\nlocacao: 10.000\nCodigo: 3210\n\nquer que eu mande as fotos?';
const CARD_DELA   = 'Codigo: 1327';
const TRES_CARDS  = 'Codigo: 1327\n---\nCodigo: 2943\n---\nCodigo: 5750';
const SO_TEXTO    = 'vou te mandar';

//        rotulo                              resposta DELA  citacao      texto dele                 codigos dele  esperado
const casos = [
  ['CASO REAL Sebastiana: card citado',       SO_TEXTO,      CARD_CITADO, 'Manda fotos',             [],           ['3210']],
  ['ela repetiu o card: o dela ganha',        CARD_DELA,     CARD_CITADO, 'Manda fotos',             [],           ['1327']],
  ['CASO REAL Gustavo: os TRES cards',        TRES_CARDS,    null,        'me passa os 3',           [],           ['1327','2943','5750']],
  ['card repetido nao vira dois',             'Codigo: 1327\nCodigo: 1327', null, 'manda',           [],           ['1327']],
  ['valor com ponto na citacao nao vira codigo', SO_TEXTO,   'valor: 900.000', 'tem foto?',          [],           ['0']],
  ['codigo que ELE escreveu',                 SO_TEXTO,      null,        'manda as fotos do 3210',  ['3210'],     ['3210']],
  ['valor que parece codigo nao entra',       SO_TEXTO,      null,        'paga ate 4000, tem foto?',[],           ['0']],
  ['sem codigo em lugar nenhum',              SO_TEXTO,      null,        'manda as fotos',          [],           ['0']],
  ['rotulo ganha de numero solto na citacao', SO_TEXTO,      CARD_CITADO, 'tem a frente?',           [],           ['3210']],
];

let falhas = 0;
for (const [rotulo, saida, cit, esc, dele, esperado] of casos) {
  const obtido = decidir(saida, cit, esc, dele).codigos;
  const ok = JSON.stringify(obtido) === JSON.stringify(esperado);
  if (!ok) falhas++;
  console.log(`${ok ? 'OK  ' : 'FALHOU'}  ${rotulo.padEnd(44)} -> ${obtido} (esperava ${esperado})`);
}
console.log();
console.log(falhas === 0 ? `TODOS OS ${casos.length} PASSARAM` : `${falhas} FALHARAM`);
process.exit(falhas ? 1 : 0);
