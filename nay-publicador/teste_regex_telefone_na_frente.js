// A regex do TELEFONE NA FRENTE, rodada no Node -- o mesmo motor do n8n.
//
// POR QUE EXISTE: a gramatica vive em SEIS copias, em dois fluxos (ver o
// cabecalho de `patch_telefone_na_frente_n8n.js`). Em 23/09 ela falhou TRES
// vezes seguidas por divergencia entre copias: primeiro so o Python foi
// consertado, depois so os nos da Nay antiga, e a NAI -- que e quem atende os
// comandos do Tel hoje -- ficou para tras nas duas.
//
// `casos_telefone_na_frente.json` e a FONTE UNICA: `teste_enviar_corretor.py`
// le o mesmo arquivo. Divergir vira teste vermelho em vez de comando morto.
//
//   node teste_regex_telefone_na_frente.js
const fs = require('fs');
const src = fs.readFileSync(__dirname + '/patch_telefone_na_frente_n8n.js', 'utf8');
const m = src.match(/const LITERAL =\n([\s\S]*?);\n/);
if (!m) { console.log('FALHOU: nao achei o LITERAL no patch'); process.exit(1); }
const RE = eval(eval(m[1]));

const mAntes = src.match(/const LITERAL_ANTES =\n([\s\S]*?);\n/);
if (!mAntes) { console.log('FALHOU: nao achei o LITERAL_ANTES'); process.exit(1); }
const RE_ANTES = eval(eval(mAntes[1]));

let maus = 0;
function rodar(arquivo, regex) {
  const casos = JSON.parse(fs.readFileSync(__dirname + '/' + arquivo, 'utf8'));
  for (const [t, esp, posta] of casos) {
    // A TERCEIRA COLUNA, quando existe, diz que o ramo de POSTA do no ja pega a
    // frase -- e ai o literal NAO pode casar, senao o publicador e chamado duas
    // vezes. Foi o estrago de 25/09: duas respostas iguais ao Tel e a reserva
    // atomica virando "ja foi postado, quer de novo?" em cadeia.
    const querido = posta === undefined ? esp : (esp && !posta);
    const got = regex.test(t);
    if (got !== querido) {
      maus++;
      console.log('  FALHOU ' + JSON.stringify(t) + ' -> ' + got + ', esperava ' + querido);
    }
  }
  return casos.length;
}

// O telefone ANTES do verbo ("92 9454-0289 envia ...", Tel 24/09): aqui o no
// so DETECTA -- quem reescreve para a forma canonica e o
// `interpretar_comando.py`. Os dois precisam concordar sobre o que E comando.
// O GRUPO ALTO PADRAO (25/09). Terceira gramatica que o `ENVIO_RE` nao pega:
// "Nay envia para o grupo alto padrao 4567". O `NAO_PESSOA_RE` contem
// `grupos?` e descarta de proposito, entao sem este literal o comando morre no
// `Comando do Tel` -- reconhecido no Python e no roteador da NAI, e descartado
// aqui. Foi assim que ele nasceu.
const mAP = src.match(/const LITERAL_ALTO_PADRAO =\n([\s\S]*?);\n/);
if (!mAP) { console.log('FALHOU: nao achei o LITERAL_ALTO_PADRAO'); process.exit(1); }
const RE_AP = eval(eval(mAP[1]));

const n1 = rodar('casos_telefone_na_frente.json', RE);
const n2 = rodar('casos_telefone_antes_do_verbo.json', RE_ANTES);
const n3 = rodar('casos_alto_padrao.json', RE_AP);

if (maus) { console.log(maus + ' CASOS FALHARAM'); process.exit(1); }
console.log('TODOS OS ' + (n1 + n2 + n3) + ' PASSARAM');
