// Prova os SEIS nós que carregam a gramática do comando do Tel, executando.
//
// POR QUE EXISTE: `node --check` passa em coisas que derrubam o nó inteiro
// (medido duas vezes em 12/09), e passa também em literal DECLARADO E NUNCA
// USADO -- que foi o bug de 24/09: o caminho "bloco já existe" do patch trocou
// as declarações e não religou os pontos de uso, e os seis nós ficaram
// declarando uma regex morta.
//
// Ao consertar aquilo com uma função nomeada, a contagem `/EH_ENVIO_TEL\(/`
// não casava com a definição `const EH_ENVIO_TEL = (x) =>` -- espaço antes do
// parêntese --, o patch achou "sem uso", religou um nó já ligado e DUPLICOU
// `const mTelFrente`. Declaração duplicada derruba o nó e passa no `--check`.
//
// Por isso este arquivo afirma as duas coisas: o que TEM que existir, e o que
// NÃO pode existir.
//
//   node provar_seis_nos.js <nay.json> <nai.json> <pasta-dos-casos>
const fs = require('fs');
const path = require('path');

const [, , ARQ_NAY, ARQ_NAI, PASTA] = process.argv;
if (!ARQ_NAY || !ARQ_NAI) {
  console.error('uso: node provar_seis_nos.js <nay.json> <nai.json> [pasta-dos-casos]');
  process.exit(2);
}
const base = PASTA || __dirname;
const casos = (arq) => JSON.parse(fs.readFileSync(path.join(base, arq), 'utf8'));

// As três gramáticas que o `ENVIO_RE` não pega, cada uma com sua fonte única.
const FONTES = [
  ['telefone na FRENTE do código', /const ENVIO_TEL_FRENTE = (\/.*\/i);/,
   'casos_telefone_na_frente.json'],
  ['telefone ANTES do verbo', /const ENVIO_TEL_ANTES = (\/.*\/i);/,
   'casos_telefone_antes_do_verbo.json'],
  ['grupo ALTO PADRÃO', /const ALTO_PADRAO_GRUPO = (\/.*\/i);/,
   'casos_alto_padrao.json'],
];
const FIM_MARCA = '// <<< telefone na frente';

let falhas = 0;
function ok(t, cond, det) {
  if (!cond) falhas++;
  console.log('  ' + (cond ? 'OK  ' : 'FALHOU') + ' ' + t +
              (cond || !det ? '' : '  <- ' + det));
}

for (const [rot, arq] of [['NAY', ARQ_NAY], ['NAI', ARQ_NAI]]) {
  const j = JSON.parse(fs.readFileSync(arq, 'utf8'));
  const w = Array.isArray(j) ? j[0] : j;
  const nos = Object.fromEntries(w.nodes.map((x) => [x.name, x]));
  console.log('==== ' + rot + ' (' + w.name + ')');

  for (const nome of ['Comando do Tel', 'Rotear para o agente',
                      'Rotear pelo cabeçalho', 'Achar codigo na resposta']) {
    if (!nos[nome]) continue;
    const c = nos[nome].parameters.jsCode;

    // 1. COMPILA? O `Comando do Tel` é async (faz `await httpRequest`), então
    //    compilar com `new Function` acusaria erro que não existe.
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    const Compilar = /\bawait\b/.test(c) ? AsyncFunction : Function;
    let erro = '';
    try { new Compilar('$input', '$', 'items', c); } catch (e) { erro = e.message; }
    ok(nome + ': compila', !erro, erro);

    // 2. cada literal declarado UMA vez (bloco delimitado, não empilhado)
    //    e RODANDO contra a sua fonte única.
    for (const [rotulo, padrao, arqCasos] of FONTES) {
      const decl = (c.match(new RegExp(padrao.source.split(' = ')[0] + ' =', 'g')) || []).length;
      ok(nome + ': declara ' + rotulo + ' uma vez', decl === 1, 'achei ' + decl);
      const m = c.match(padrao);
      if (!m) { falhas++; console.log('  FALHOU ' + nome + ': sem ' + rotulo); continue; }
      const RE = eval(m[1]);
      let maus = 0, qual = '';
      for (const [t, esp, posta] of casos(arqCasos)) {
        // A terceira coluna, quando existe, marca o que o ramo de POSTA do no
        // ja pega: ali o literal NAO pode casar, senao o publicador e chamado
        // duas vezes (o estrago de 25/09).
        const querido = posta === undefined ? esp : (esp && !posta);
        if (RE.test(t) !== querido) { maus++; qual = qual || t; }
      }
      ok(nome + ': os casos de ' + rotulo + ' batem', maus === 0,
         maus + ' divergem, ex: ' + JSON.stringify(qual));
    }

    // 3. A FUNÇÃO É USADA. A definição é `const EH_ENVIO_TEL = (x) =>`, com
    //    espaço antes do parêntese: ela NÃO casa com `EH_ENVIO_TEL\(`. Esta
    //    contagem é de usos puros.
    const usos = (c.match(/EH_ENVIO_TEL\(/g) || []).length;
    ok(nome + ': a função é USADA', usos >= 1, usos + ' uso(s)');

    // 4. e o que NÃO pode existir
    const dup = (c.match(/const mTelFrente/g) || []).length;
    ok(nome + ': sem const duplicada', dup <= 1, dup + ' declarações');
    const depois = c.slice(c.indexOf(FIM_MARCA));
    ok(nome + ': nenhum uso solto da forma antiga',
       !/ENVIO_TEL_(FRENTE|ANTES)\.test/.test(depois), 'sobrou .test fora do bloco');
  }
  console.log();
}

if (falhas) { console.log(falhas + ' FALHARAM'); process.exit(1); }
console.log('OS SEIS NOS PASSARAM');
