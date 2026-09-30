/*
 * Prova que a regex de ENVIO PRIVADO no n8n casa EXATAMENTE com a do
 * Python. As duas leem `casos_comando_envio.json` -- fonte unica.
 *
 * POR QUE: os verbos de comando vivem em QUATRO copias (o Python e tres
 * nos do n8n). Divergiram sozinhas antes, e o CLAUDE.md registra isso como
 * o bug mais caro do projeto. Com o mesmo literal e a mesma lista de
 * casos, divergencia vira teste vermelho em vez de comando morto.
 *
 * Uso (precisa do Node do container):
 *   scp teste_regex_envio.js casos_comando_envio.json root@SERVIDOR:/tmp/
 *   ssh root@SERVIDOR 'docker cp /tmp/teste_regex_envio.js n8n-viux-n8n-1:/tmp/ \
 *     && docker cp /tmp/casos_comando_envio.json n8n-viux-n8n-1:/tmp/ \
 *     && docker exec n8n-viux-n8n-1 node /tmp/teste_regex_envio.js'
 */
const fs = require('fs');

// O MESMO literal das quatro copias.
const ENVIO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)(?:a|ar|e|ei|ou|o)?\b([\s\S]*)(?:\bpara\b|\bpra\b|\bpro\b|\bp\/)\s*([\s\S]+?)\s*$/i;

// Procura ao lado do script primeiro e so depois em /tmp: assim a mesma
// suite roda no Mac (repositorio) e dentro do container (onde o scp poe
// os dois arquivos em /tmp). Caminho fixo fazia ela so falhar no Mac.
const path = require("path");
const candidatos = [path.join(__dirname, "casos_comando_envio.json"),
                    "/tmp/casos_comando_envio.json"];
const arquivo = candidatos.find((p) => fs.existsSync(p));
if (!arquivo) {
  console.error("nao achei casos_comando_envio.json em: " + candidatos.join(", "));
  process.exit(1);
}
const casos = JSON.parse(fs.readFileSync(arquivo, "utf8"));
let falhas = 0;
for (const [texto, esperado] of casos) {
  const casou = ENVIO_RE.test(texto);
  const ok = casou === esperado;
  if (!ok) falhas++;
  console.log(`${ok ? 'OK  ' : 'FALHOU'}  ${casou ? 'casa ' : 'nao  '} ${texto}`);
}
console.log();
console.log(falhas === 0 ? `TODOS OS ${casos.length} PASSARAM` : `${falhas} FALHARAM`);
process.exit(falhas ? 1 : 0);
