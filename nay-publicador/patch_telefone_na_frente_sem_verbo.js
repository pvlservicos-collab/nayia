/*
 * TELEFONE NA FRENTE + UM CODIGO E ENVIO, mesmo sem verbo (Tel, 28/09).
 *
 * O CASO: ele escreveu "92 8192-5962 **evia** o 964" -- faltou o "n". Nenhuma
 * gramatica casou, a frase foi ao agente, e a Nay respondeu A ELE como se
 * fosse um corretor pedindo o imovel: "Bom dia, Imob! Claro, ja te mando!",
 * com o card e as 13 fotos. O imovel nunca chegou a corretora.
 *
 * A PALAVRA DELE: "toda vez que vier mensagem da imob easy e do Tel e um
 * comando para enviar o imovel e nao para receber, para ela nao poder
 * confundir e fazer isso".
 *
 * OS TRES NOS COMPARTILHAM `EH_ENVIO_TEL`, e cada um o usa para uma coisa:
 *   Comando do Tel        -> manda ao publicador
 *   Rotear para o agente  -> DESCARTA, para ela nao responder como corretora
 *   Achar codigo na resp. -> nao deixa o texto DELE virar gatilho de fotos
 * Por isso a mudanca e uma so, espelhada nos tres -- e e o terceiro que
 * teria mandado as fotos de volta para ele.
 *
 * AS TRES EXIGENCIAS, cada uma tirando um falso positivo MEDIDO no historico
 * dele (as mensagens de 22 e 23/09):
 *   * COMECA com o telefone -- "DEVOLVER (92) 99511-8525 estou verificando"
 *     e "NAO CORRETOR (92) 98427-1973" comecam com a palavra de comando.
 *   * UM codigo so, de 3 a 5 digitos -- sem o piso, "temos uma casa de 4 mil"
 *     colhia o "4".
 *   * so vale para o TEL: os tres pontos ja estao atras de `ehTel` /
 *     `ehTelDoTel` / do texto dele.
 *
 *   node patch_telefone_na_frente_sem_verbo.js <workflow.json> <saida.json>
 */
const fs = require('fs');

const ENTRADA = process.argv[2];
const SAIDA = process.argv[3];
if (!ENTRADA || !SAIDA) {
  console.error('uso: node patch_telefone_na_frente_sem_verbo.js <entrada.json> <saida.json>');
  process.exit(2);
}

const INICIO = '// >>> telefone na frente sem verbo (28/09)';
const FIM = '// <<< telefone na frente sem verbo';

const BLOCO = [
  INICIO,
  'const _UM_CODIGO_DEPOIS_DO_TEL = (x) => {',
  "  const s = String(x == null ? '' : x);",
  "  const m = /^\\s*(?:@?nay\\b[\\s,;:.!?-]*)?((?:55[\\s.-]*)?\\(?\\d{2}\\)?[\\s.-]*9?\\d{4}[\\s.-]*\\d{4})\\b/i.exec(s);",
  '  if (!m) return false;',
  '  const resto = s.slice(m.index + m[0].length);',
  // OUTRO COMANDO FECHA A PORTA: "92 9951-9275 posta o 5737" tem telefone e
  // codigo, mas `posta` manda para os GRUPOS -- e a regra de 31/08 e que
  // postar e enviar para uma pessoa nunca se misturam. Espelha o
  // `_OUTRO_COMANDO_RE` do interpretar_comando.py.
  '  if (/\\b(post|public|dispar|solt|tir|remov|retir|vende|vendid|aluga|alugad|vaga|lista|agenda|resposta|descart|pendencia|corretor|devolv)\\w*\\b/i.test(resto)) return false;',
  "  const semTel = resto.replace(/(?:55[\\s.-]*)?\\(?\\d{2}\\)?[\\s.-]*9?\\d{4}[\\s.-]*\\d{4}/g, ' ');",
  '  const cods = semTel.match(/(?<![\\d.,])\\d{3,5}(?![\\d.,])/g) || [];',
  '  return cods.length === 1;',
  '};',
  FIM,
  '',
].join('\n');

// A linha do EH_ENVIO_TEL, identica nos tres nos.
const VELHA = 'const EH_ENVIO_TEL = (x) => ENVIO_TEL_FRENTE.test(x) || ENVIO_TEL_ANTES.test(x) || ALTO_PADRAO_GRUPO.test(x);';
const NOVA = 'const EH_ENVIO_TEL = (x) => ENVIO_TEL_FRENTE.test(x) || ENVIO_TEL_ANTES.test(x) || ALTO_PADRAO_GRUPO.test(x) || _UM_CODIGO_DEPOIS_DO_TEL(x);';

const NOS = ['Rotear para o agente', 'Achar codigo na resposta', 'Comando do Tel'];

function comBloco(codigo) {
  const i = codigo.indexOf(INICIO);
  if (i === -1) return BLOCO + codigo;
  const f = codigo.indexOf(FIM, i);
  if (f === -1) throw new Error('marcador de inicio sem o de fim -- nao mexo');
  return codigo.slice(0, i) + BLOCO + codigo.slice(f + FIM.length + 1);
}

const bruto = JSON.parse(fs.readFileSync(ENTRADA, 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const erros = [];
let mexidos = 0;

for (const nome of NOS) {
  const no = wf.nodes.find((x) => x.name === nome);
  if (!no) { erros.push('no ' + nome + ' nao existe'); continue; }
  let c = no.parameters.jsCode;
  if (c.indexOf(VELHA) !== -1) {
    c = c.split(VELHA).join(NOVA);
  } else if (c.indexOf(NOVA) === -1) {
    erros.push(nome + ': nao achei a linha do EH_ENVIO_TEL');
    continue;
  }
  no.parameters.jsCode = comBloco(c);
  mexidos++;
}

if (erros.length) {
  console.error('ABORTADO:\n  ' + erros.join('\n  '));
  process.exit(1);
}

// SINTAXE de cada no mexido. `node --check` nao basta (a licao de 12/09),
// mas pegar o que ele pega ja evita importar lixo.
for (const nome of NOS) {
  const no = wf.nodes.find((x) => x.name === nome);
  try {
    new Function('return (async function(){' + no.parameters.jsCode + '\n});')();
  } catch (e) {
    console.error('SINTAXE QUEBRADA no no ' + nome + ': ' + e.message);
    process.exit(1);
  }
}

// E O COMPORTAMENTO, contra os casos reais -- o que `node --check` nao ve.
// A MESMA definicao do BLOCO, avaliada a partir dele -- nao uma copia. Copiar
// aqui faria o teste provar um codigo diferente do que vai para o no, que e o
// jeito mais silencioso de um teste mentir.
const fn = new Function(BLOCO + '\nreturn _UM_CODIGO_DEPOIS_DO_TEL;')();
const DEVE = ['92 8192-5962 evia o 964', 'Nay 92 8192-5962 evia o 964',
  '(92) 98192-5962 evia o 964', '92 8192-5962 manda 964', '92981925962 964'];
const NAO_DEVE = ['NAO CORRETOR (92) 98427-1973  - ela nunca responde',
  'DEVOLVER (92) 99511-8525 estou verificando com a proprietaria',
  'RESPOSTA (92) 99515-1318 WLYSSES apenas uma vaga',
  '(92) 99515-1318 apenas uma vaga mesmo', 'CORRETOR (92) 99277-3833',
  'Devolver (92) 98644-8395 temos uma casa na ponta negra de 4 mil',
  'Nay posta o 5750', 'bom dia Nay',
  '92 9951-9275 posta o 5737',   // posta vai para GRUPO, nunca envio privado
  '92 9951-9275 bom dia', '92 9951-9275 e o numero dela'];
let maus = 0;
for (const t of DEVE) if (!fn(t)) { maus++; console.error('  FALHOU (devia casar): ' + t); }
for (const t of NAO_DEVE) if (fn(t)) { maus++; console.error('  FALHOU (nao devia casar): ' + t); }
if (maus) { console.error(maus + ' casos de comportamento falharam'); process.exit(1); }

fs.writeFileSync(SAIDA, JSON.stringify(Array.isArray(bruto) ? bruto : wf, null, 2));
console.log(mexidos + ' nos mexidos, sintaxe e ' + (DEVE.length + NAO_DEVE.length) +
            ' casos de comportamento ok -> ' + SAIDA);
