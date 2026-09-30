/*
 * Prova que a gramatica do ENVIO POR LISTA no n8n casa EXATAMENTE com a do
 * Python. Os dois lados leem `casos_envio_de_lista.json` -- fonte unica.
 *
 * POR QUE: a gramatica de comando do Tel vive em QUATRO copias (o Python e
 * tres nos do n8n) e elas divergem sozinhas. O CLAUDE.md registra isso como
 * o bug mais caro do projeto. Com o mesmo literal (lido de
 * `regex_envio_de_lista.js`) e a mesma lista de casos, divergencia vira
 * teste vermelho em vez de comando morto.
 *
 * Uso (roda no Mac e dentro do container):
 *   node teste_regex_envio_de_lista.js
 */
const fs = require('fs');
const path = require('path');

function achar(nome) {
  const cands = [path.join(__dirname, nome), '/tmp/' + nome];
  const p = cands.find((x) => fs.existsSync(x));
  if (!p) {
    console.error('nao achei ' + nome + ' em: ' + cands.join(', '));
    process.exit(1);
  }
  return p;
}

const { ehEnvioDeLista, ehEscolhaDeCodigo, ehEscolhaNatural } =
  require(achar('regex_envio_de_lista.js'));
const casos = JSON.parse(fs.readFileSync(achar('casos_envio_de_lista.json'), 'utf8'));

let falhas = 0;
for (const [texto, esperado] of casos) {
  // A ORDEM IMPORTA e e a mesma do dispatch do Python: a escolha de codigo
  // e testada ANTES da lista. Trocar a ordem aqui e no Python faria a
  // mesma frase cair em ramos diferentes nos dois lados.
  let deu = 'nada';
  if (ehEscolhaDeCodigo(texto) || ehEscolhaNatural(texto)) deu = 'escolha';
  else if (ehEnvioDeLista(texto)) deu = 'lista';

  const ok = deu === esperado;
  if (!ok) falhas++;
  const curto = texto.replace(/\n/g, ' | ').slice(0, 62);
  console.log(`${ok ? 'OK  ' : 'FALHOU'}  ${deu.padEnd(7)} ${curto}`);
  if (!ok) console.log(`        esperava ${esperado}`);
}

console.log();
if (falhas) {
  console.log(`${falhas} DE ${casos.length} FALHARAM`);
  process.exit(1);
}
console.log(`TODOS OS ${casos.length} PASSARAM`);
