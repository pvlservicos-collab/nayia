/*
 * Prova que o "sim"/"não" do n8n casa EXATAMENTE com o do Python. Os dois lados
 * leem `casos_resposta_ao_tel.json` -- fonte única.
 *
 * POR QUE: a gramática de comando do Tel vive em cópias no Python e nos nós, e
 * elas divergem sozinhas. Aqui a divergência custa caro nos dois sentidos: o
 * nó manda um "sim" que o Python não entende (ele fica sem resposta), ou o
 * Python entende um que o nó não manda (o agente responde no lugar).
 */
const fs = require('fs');
const path = require('path');
function achar(nome) {
  const c = [path.join(__dirname, nome), '/tmp/' + nome];
  const p = c.find((x) => fs.existsSync(x));
  if (!p) { console.error('nao achei ' + nome); process.exit(1); }
  return p;
}
const { respostaAoTel } = require(achar('regex_resposta_ao_tel.js'));
const casos = JSON.parse(fs.readFileSync(achar('casos_resposta_ao_tel.json'), 'utf8'));
let falhas = 0;
for (const [texto, esperado] of casos) {
  const deu = respostaAoTel(texto) || 'nada';
  const ok = deu === esperado;
  if (!ok) falhas++;
  console.log(`${ok ? 'OK  ' : 'FALHOU'}  ${deu.padEnd(5)} ${JSON.stringify(texto)}`);
  if (!ok) console.log(`        esperava ${esperado}`);
}
console.log();
if (falhas) { console.log(`${falhas} DE ${casos.length} FALHARAM`); process.exit(1); }
console.log(`TODOS OS ${casos.length} PASSARAM`);
