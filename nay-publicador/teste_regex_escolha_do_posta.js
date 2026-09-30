/*
 * O lado JavaScript de `casos_escolha_do_posta.json`: o PORTAO que deixa a
 * resposta curta do Tel chegar ao publicador quando ha pergunta aberta.
 *
 * O mesmo arquivo de casos roda no Python (`teste_postar_por_nome.py`).
 * Divergencia entre o portao e a gramatica vira teste vermelho aqui.
 */
const fs = require('fs');
const path = require('path');
const { ehEscolhaDoPosta } = require('./regex_escolha_do_posta.js');

const casos = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'casos_escolha_do_posta.json'), 'utf8')).casos;

let falhas = 0;
for (const c of casos) {
  const deu = ehEscolhaDoPosta(c.texto);
  if (deu !== c.escolha) {
    falhas++;
    console.log(`  FALHOU ${JSON.stringify(c.texto)}: esperava ${c.escolha}, veio ${deu}`);
  }
}
if (falhas) {
  console.log(`${falhas} DE ${casos.length} FALHARAM`);
  process.exit(1);
}
console.log(`TODOS OS ${casos.length} PASSARAM`);
