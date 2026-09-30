/*
 * O SEGUNDO NUMERO DO TEL nos nos do n8n (Tel, 28/09).
 *
 * "todo comando que o Tel tem, voce repassa tambem para este numero como se
 * fosse ele 92 98595-6408 ... nestes dois numeros". E, perguntado, ele
 * escolheu que o numero novo RECEBE tudo tambem.
 *
 * O NUMERO ESTAVA CODIFICADO EM SEIS NOS, cada um com sua redacao:
 * `TESTE`, `TEL_DO_TEL`, `TEL`, e tres comparacoes cruas. Este patch poe a
 * mesma definicao nos seis e troca as comparacoes por ela.
 *
 * COMPARA PELOS 8 ULTIMOS DIGITOS, nunca pelo numero inteiro: a Z-API entrega
 * brasileiro ora com o 9 na frente (13 digitos) ora sem (12), e igualdade
 * crua nao serve. E o mesmo criterio do `nay_e_da_equipe`, de 29/08.
 *
 * O QUE **NAO** VIRA LISTA: os lugares onde o numero e um VALOR, nao uma
 * pergunta. `tel_tel` vai para uma funcao do banco que identifica o Tel, e
 * ali o canonico continua sendo o primeiro numero. So o `phone` da cortesia
 * vira leque, porque ali e uma mensagem PARA ele -- e ele pediu que os dois
 * recebam.
 *
 * O BLOCO E DELIMITADO por marcadores e trocado INTEIRO. A licao de 12/09:
 * "bloco inserido por patch tem que ser DELIMITADO, para ser trocado em vez
 * de empilhado -- guarda por mudanca nao substitui delimitador".
 *
 *   node patch_segundo_numero_do_tel.js <workflow.json> <saida.json>
 */
const fs = require('fs');

const ENTRADA = process.argv[2];
const SAIDA = process.argv[3];
if (!ENTRADA || !SAIDA) {
  console.error('uso: node patch_segundo_numero_do_tel.js <entrada.json> <saida.json>');
  process.exit(2);
}

const INICIO = '// >>> segundo numero do Tel (28/09)';
const FIM = '// <<< segundo numero do Tel';

// A DEFINICAO, identica nos seis nos. `TELS_DO_TEL` guarda os numeros
// inteiros (para MANDAR) e `ehTelDoTel` compara pelos 8 finais (para SABER).
const BLOCO = [
  INICIO,
  "const TELS_DO_TEL = ['559294717316', '5592985956408'];",
  "const _finalDoTel = (x) => String(x == null ? '' : x).replace(/\\D/g, '').slice(-8);",
  'const _FINAIS_DO_TEL = TELS_DO_TEL.map(_finalDoTel);',
  'const ehTelDoTel = (x) => _FINAIS_DO_TEL.indexOf(_finalDoTel(x)) !== -1;',
  FIM,
  '',
].join('\n');

function comBloco(codigo) {
  const i = codigo.indexOf(INICIO);
  if (i === -1) return BLOCO + codigo;
  const f = codigo.indexOf(FIM, i);
  if (f === -1) throw new Error('marcador de inicio sem o de fim -- nao mexo');
  return codigo.slice(0, i) + BLOCO + codigo.slice(f + FIM.length + 1);
}

// As trocas, no. `de` e literal; `para` passa por `() =>` porque o $ do
// replace e padrao especial -- a licao de 12/09 que truncou um literal.
const TROCAS = {
  'Achar codigo': [
    ["String(j.telefone) === '559294717316'", 'ehTelDoTel(j.telefone)'],
  ],
  'Preparar envio': [
    ["String(tel) !== '559294717316'", '!ehTelDoTel(tel)'],
  ],
  'Montar lista': [
    ["const TESTE = '559294717316';", '// TESTE virou pergunta: ver ehTelDoTel.'],
    ['if (tel !== TESTE) return [];', 'if (!ehTelDoTel(tel)) return [];'],
  ],
  'Rotear para o agente': [
    ["String(j.telefone) !== '559294717316'", '!ehTelDoTel(j.telefone)'],
    ["const ehTel = String(j.telefone) === '559294717316';",
     'const ehTel = ehTelDoTel(j.telefone);'],
  ],
  'Preparar envio do agente': [
    ["const TEL_DO_TEL = '559294717316';", 'const TEL_DO_TEL = TELS_DO_TEL[0];'],
    ['if (pausado && String(tel) !== TEL_DO_TEL) return [];',
     'if (pausado && !ehTelDoTel(tel)) return [];'],
    // O AVISO DE NUMERO FORA DO CADASTRO vai para os DOIS: ele pediu que o
    // segundo numero receba tudo. Um item por numero, em vez de um so.
    ["    { json: { rota: 'send-text', pausa: 3, corpo: { phone: TEL_DO_TEL, message:",
     "    ...TELS_DO_TEL.map((_t) => ({ json: { rota: 'send-text', pausa: 3, corpo: { phone: _t, message:"],
  ],
  'Comando do Tel': [
    // `TEL` continua sendo o canonico: ele vai como VALOR para o banco
    // (`tel_tel`), onde identifica o Tel. So a pergunta vira leque.
    ["const TEL = '559294717316';", 'const TEL = TELS_DO_TEL[0];'],
    ["if (String(j.telefone) !== TEL) return [];", 'if (!ehTelDoTel(j.telefone)) return [];'],
  ],
};

const bruto = JSON.parse(fs.readFileSync(ENTRADA, 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
let mexidos = 0;
const erros = [];

for (const [nome, trocas] of Object.entries(TROCAS)) {
  const no = wf.nodes.find((x) => x.name === nome);
  if (!no) { erros.push('no ' + nome + ' nao existe'); continue; }
  let c = no.parameters.jsCode;
  for (const [de, para] of trocas) {
    if (c.indexOf(de) === -1) {
      // Ja aplicado? Entao o destino tem que estar la. Se nao estiver, o no
      // mudou por baixo e eu PARO -- reescrever as cegas e o que quebra nos.
      if (c.indexOf(para) === -1) erros.push(nome + ': nao achei ' + JSON.stringify(de.slice(0, 48)));
      continue;
    }
    c = c.split(de).join(para);
  }
  c = comBloco(c);
  no.parameters.jsCode = c;
  mexidos++;
}

// O FECHAMENTO do map da cortesia: a linha seguinte termina em `} },` e
// precisa de mais um parentese. Feito a parte porque depende do texto exato.
const cortesia = wf.nodes.find((x) => x.name === 'Preparar envio do agente');
if (cortesia && cortesia.parameters.jsCode.includes('...TELS_DO_TEL.map((_t)')) {
  const c = cortesia.parameters.jsCode;
  const alvo = "' + String(j.texto || '').slice(0, 300) + '\"' } } },";
  if (c.includes(alvo)) {
    cortesia.parameters.jsCode = c.split(alvo).join(
      "' + String(j.texto || '').slice(0, 300) + '\"' } } })),");
  } else if (!c.includes("} } })),")) {
    erros.push('Preparar envio do agente: nao achei o fim do item da cortesia');
  }
}

if (erros.length) {
  console.error('ABORTADO:\n  ' + erros.join('\n  '));
  process.exit(1);
}

// SINTAXE de cada no mexido, antes de gravar. `node --check` nao basta (a
// licao de 12/09), mas pegar o que ele pega ja evita importar lixo.
for (const nome of Object.keys(TROCAS)) {
  const no = wf.nodes.find((x) => x.name === nome);
  try {
    // ASYNC: o `Comando do Tel` faz `await this.helpers.httpRequest`, e um
    // `new Function` comum recusa o await -- recusaria o no bom.
    new Function('return (async function(){' + no.parameters.jsCode + '\n});')();
  } catch (e) {
    console.error('SINTAXE QUEBRADA no no ' + nome + ': ' + e.message);
    process.exit(1);
  }
}

fs.writeFileSync(SAIDA, JSON.stringify(Array.isArray(bruto) ? bruto : wf, null, 2));
console.log(mexidos + ' nos mexidos, sintaxe ok -> ' + SAIDA);
