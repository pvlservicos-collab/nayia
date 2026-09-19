/*
 * Prova a gramatica dos comandos de PENDENCIA contra os casos reais.
 *
 * POR QUE EXISTE (01/09): o Tel escreveu "descarta 47" e a gramatica so
 * conhecia "DESCARTAR". A mensagem caiu no agente, que leu o 47 como
 * codigo de imovel e respondeu "o 47 tem so dois digitos". Ele repetiu
 * tres vezes sem entender o que estava acontecendo.
 *
 * As DUAS metades importam: reconhecer o que E comando, e nao reconhecer
 * o que nao e. Um "descarta" solto ou com cauda muda a intencao.
 *
 * Uso: node teste_regex_pendencia.js
 */
const fs = require('fs');
const path = require('path');

const candidatos = [path.join(__dirname, 'casos_comando_pendencia.json'),
                    '/tmp/casos_comando_pendencia.json'];
const arquivo = candidatos.find((p) => fs.existsSync(p));
if (!arquivo) { console.error('nao achei casos_comando_pendencia.json'); process.exit(1); }
const casos = JSON.parse(fs.readFileSync(arquivo, 'utf8'));

const mods = [path.join(__dirname, 'regex_pendencia.js'), '/tmp/regex_pendencia.js'];
const mod = mods.find((p) => fs.existsSync(p));
const { interpretarPendencia, ehComandoDePendencia } = require(mod);

let falhas = 0;
function checar(ok, rotulo, detalhe) {
  if (!ok) { falhas++; console.log('FALHOU ' + rotulo + (detalhe ? '  -> ' + detalhe : '')); }
  else { console.log('OK     ' + rotulo); }
}

for (const c of casos.descartar) {
  const r = interpretarPendencia(c.texto);
  checar(r && r.acao === 'DESCARTAR' && r.p_id === c.id,
    JSON.stringify(c.texto), JSON.stringify(r));
}
for (const c of casos.resposta) {
  const r = interpretarPendencia(c.texto);
  checar(r && r.acao === 'RESPOSTA' && r.p_id === c.id && r.p_texto === c.corpo,
    JSON.stringify(c.texto), JSON.stringify(r));
}
for (const c of casos.listar) {
  const r = interpretarPendencia(c.texto);
  checar(r && r.acao === 'PENDENCIAS', JSON.stringify(c.texto), JSON.stringify(r));
}
for (const c of casos.descartar_tudo) {
  const r = interpretarPendencia(c.texto);
  const esperado = c.confirma ? 'DESCARTAR TUDO SIM' : 'DESCARTAR TUDO';
  checar(r && r.acao === esperado, JSON.stringify(c.texto), JSON.stringify(r));
}
for (const t of casos.nao_e_comando) {
  checar(interpretarPendencia(t) === null && !ehComandoDePendencia(t),
    'NAO e comando: ' + JSON.stringify(t), JSON.stringify(interpretarPendencia(t)));
}

// As duas copias tem que concordar: o que o `Comando do Tel` EXECUTA e
// exatamente o que o `Rotear para o agente` DESCARTA. Se divergirem, ou o
// Tel recebe resposta dupla, ou o comando morre em silencio.
const todos = [].concat(casos.descartar, casos.resposta, casos.listar, casos.descartar_tudo)
  .map((c) => c.texto);
for (const t of todos) {
  checar(ehComandoDePendencia(t) === (interpretarPendencia(t) !== null),
    'as duas copias concordam: ' + JSON.stringify(t));
}

console.log('');
console.log(falhas === 0 ? 'TODOS OS ' + (todos.length + casos.nao_e_comando.length) + ' PASSARAM'
                         : falhas + ' FALHARAM');
process.exit(falhas ? 1 : 0);
