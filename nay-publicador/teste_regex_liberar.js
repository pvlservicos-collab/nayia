/*
 * Roda `casos_comando_liberar.json` contra a regex que os nos do n8n usam.
 *
 * O teste Python (`teste_interpretar_comando.py`) roda os MESMOS casos contra
 * o `interpretar_comando.py`. Se as duas gramaticas divergirem, um dos dois
 * fica vermelho -- em vez de o Tel escrever "5712 Alugado" e nada acontecer.
 *
 *   scp teste_regex_liberar.js regex_liberar.js casos_comando_liberar.json root@SERVIDOR:/tmp/
 *   ssh root@SERVIDOR 'docker exec n8n-viux-n8n-1 node /tmp/teste_regex_liberar.js'
 */
const fs = require('fs');
const path = require('path');

const candidatos = [path.join(__dirname, 'casos_comando_liberar.json'),
                    '/tmp/casos_comando_liberar.json'];
const arquivo = candidatos.find((p) => fs.existsSync(p));
if (!arquivo) { console.error('nao achei casos_comando_liberar.json'); process.exit(1); }
const { casos } = JSON.parse(fs.readFileSync(arquivo, 'utf8'));

const mods = [path.join(__dirname, 'regex_liberar.js'), '/tmp/regex_liberar.js'];
const mod = mods.find((p) => fs.existsSync(p));
if (!mod) { console.error('nao achei regex_liberar.js'); process.exit(1); }
const { ehComandoDoTel, lerCodigoNaFrente } = require(mod);

let falhas = 0;
for (const caso of casos) {
  const deu = ehComandoDoTel(caso.texto);
  let ok = deu === caso.comando;
  let detalhe = `comando=${deu}`;

  // Quando e comando pela forma "codigo na frente", o codigo e o motivo tem
  // que sair certos -- dizer "vendido" de um imovel alugado sai para dezenas
  // de corretores sem desfazer.
  if (ok && caso.comando && caso.acao_python === 'marcar_taxa') {
    // O SENTIDO importa mais que o reconhecimento: marcar taxa inclusa num
    // imovel que nao tem faz o corretor levar cliente com a conta errada.
    const nega = /\b(nao|não|sem)\b/i.test(caso.texto);
    ok = (!nega) === caso.incluso;
    detalhe = `incluso=${!nega}`;
  } else if (ok && caso.comando && caso.motivo) {
    const lido = lerCodigoNaFrente(caso.texto);
    if (lido) {
      ok = lido.codigo === caso.codigo && lido.motivo === caso.motivo;
      detalhe = `codigo=${lido.codigo} motivo=${lido.motivo}`;
    }
  }

  if (!ok) { falhas++; console.log(`FALHOU  ${JSON.stringify(caso.texto)} -> ${detalhe}`); }
  else { console.log(`OK      ${JSON.stringify(caso.texto)}`); }
}
console.log();
console.log(falhas === 0 ? `TODOS OS ${casos.length} PASSARAM` : `${falhas} FALHARAM`);
process.exit(falhas ? 1 : 0);
