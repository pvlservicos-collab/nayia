// "Nay envia esses imoveis para X" + a lista colada, nos dois nos que decidem.
//
// O PROBLEMA QUE ESTE PATCH RESOLVE, medido em 11/09: o no `Comando do Tel`
// faz `split('\n')` e manda ao publicador SO A LINHA que casou. Para a lista
// isso entrega um comando sem imovel nenhum -- os codigos estao justamente
// nas linhas de baixo -- e a resposta real era "nao entendi qual imovel
// mandar para Tel Sobreira". A lista precisa ir INTEIRA.
//
// E a resposta de desambiguacao ("Nay codigo 5719") nao casava cópia
// NENHUMA: iria para o AGENTE de IA, que responderia sobre o imovel em vez
// de envia-lo. Pergunta sem gramatica de volta e laco fechado, nao
// desambiguacao -- o bug 6 deste projeto.
//
// OS DOIS NOS PRECISAM CONCORDAR, por motivos opostos:
//   `Comando do Tel`       -> manda para o publicador (senao o comando morre)
//   `Rotear para o agente` -> DESCARTA (senao o Tel recebe resposta dupla)
//
// Os literais sao LIDOS de `regex_envio_de_lista.js`, nao redigitados aqui.
// Reescrever regex a mao dentro de um patch ja dobrou as barras invertidas
// uma vez e o literal que entrou no no nao casava NADA -- comando morto em
// silencio (ver `patch_liberar_codigo_n8n.js`).
//
//   node patch_envio_de_lista_n8n.js <entrada.json> <saida.json>
const fs = require('fs');
const path = require('path');

const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const fonte = fs.readFileSync(
  path.join(__dirname, 'regex_envio_de_lista.js'), 'utf8');

function literal(nome) {
  const m = fonte.match(new RegExp('const ' + nome + ' =\\s*(/\\^?[\\s\\S]*?/i);'));
  if (!m) throw new Error('nao achei ' + nome + ' em regex_envio_de_lista.js');
  return m[1];
}

function corpoDaFuncao(nome) {
  const m = fonte.match(new RegExp('function ' + nome + '\\([\\s\\S]*?\\n\\}'));
  if (!m) throw new Error('nao achei function ' + nome);
  return m[0];
}

function trecho(re) {
  const m = fonte.match(re);
  if (!m) throw new Error('nao achei o trecho ' + re + ' em regex_envio_de_lista.js');
  return m[0];
}

const ENVIO_RE = literal('ENVIO_RE');
const NAO_PESSOA_RE = literal('NAO_PESSOA_RE');
const ESCOLHER_CODIGO_RE = literal('ESCOLHER_CODIGO_RE');
const FN_LISTA = corpoDaFuncao('ehEnvioDeLista');

// A gramatica das RESPOSTAS NATURAIS ("os dois", "ambos", "o primeiro"), que
// entrou em 12/09 depois de ele responder "os dois" e a frase cair no agente.
// Os literais vao inteiros, lidos do arquivo -- sao construidos por
// concatenacao de string e nao cabem no `literal()`, que le regex crua.
const BLOCO_ESCOLHA = [
  trecho(/const ANTES_DA_ESCOLHA =[\s\S]*?;\n/),
  trecho(/const ESCOLHA_NATURAL_RE =[\s\S]*?'i'\);\n/),
  trecho(/const ESCOLHA_SO_CODIGOS_RE =[\s\S]*?'i'\);\n/),
  trecho(/const CATEGORIA_NA_CAUDA =\n[\s\S]*?;\n/),
  trecho(/const CAUDA_COM_DESTINO = [\s\S]*?;\n/),
  trecho(/const CAUDA_DE_IMOVEL =\n[\s\S]*?;\n/),
  trecho(/const CAUDA_DE_GRUPO =\n[\s\S]*?;\n/),
  corpoDaFuncao('ehEscolhaNatural'),
].join('\n');

// O bloco de declaracoes, identico nos dois nos. `ENVIO_RE_LISTA` tem nome
// proprio porque o `Comando do Tel` ja declara um `ENVIO_RE` dentro do laco,
// e `const` repetido no mesmo escopo derruba o no inteiro em execucao -- o
// `node --check` nao pega isso quando os escopos parecem diferentes.
// MARCADORES, e o motivo e um bug medido. A guarda anterior era
// `c.includes('ehEscolhaNatural')`; quando o no ja tinha a versao de ontem
// (que declara ENVIO_RE_LISTA mas nao conhece a escolha natural), a guarda
// passava e o patch inseria o bloco DE NOVO -- `const ENVIO_RE_LISTA` duas
// vezes no mesmo escopo, que e SyntaxError e derruba o no inteiro.
//
// E a mesma licao que `patch_liberar_codigo_n8n.js` ja registra: guarda de
// bloco esconde a mudanca nova atras da antiga. A saida nao e outra guarda, e
// tornar o bloco SUBSTITUIVEL: delimitado, ele e trocado inteiro a cada
// rodada e o patch fica idempotente de verdade.
const INICIO = '// >>> envio de lista + escolha (patch_envio_de_lista_n8n.js)';
const FIM = '// <<< envio de lista + escolha';

// Troca o bloco entre os marcadores, ou devolve null se ainda nao existe.
// O recorte do bloco, de marcador a marcador. Passar o `ramo` inteiro
// acumulava a linha em branco das pontas a cada rodada, e o patch deixava de
// CONVERGIR -- e "rodar duas vezes da o mesmo resultado" e justamente a
// propriedade que o torna seguro de repetir.
function soOBloco(ramo) {
  return ramo.slice(ramo.indexOf(INICIO), ramo.lastIndexOf(FIM) + FIM.length);
}

function trocarBloco(codigo, novo, qualNo) {
  const i = codigo.indexOf(INICIO);
  if (i < 0) {
    // BLOCO ANTIGO SEM MARCADOR: a primeira versao deste patch inseria um
    // bloco sem delimitar. Inserir outro por cima declara `ENVIO_RE_LISTA`
    // duas vezes no mesmo escopo -- SyntaxError, e o no cai INTEIRO em
    // producao. Aconteceu no deploy de 12/09.
    //
    // RECUSA EM VEZ DE MIGRAR, de proposito: escrever logica para recortar um
    // bloco que nao se delimitou e adivinhar onde ele acaba, e errar ali
    // apaga codigo do no. O backup anterior ao patch existe e e a base certa.
    if (codigo.includes('ENVIO_RE_LISTA')) {
      throw new Error(
        qualNo + ' tem um bloco ANTIGO, sem marcador. Aplicar por cima '
        + 'duplicaria as declaracoes e derrubaria o no. Rode o patch a partir '
        + 'do backup anterior ao primeiro patch (/root/backups-n8n/'
        + 'bk_20260912_antes_envio_de_lista.json), nao do export atual.');
    }
    return null;
  }
  const j = codigo.indexOf(FIM, i);
  if (j < 0) throw new Error('marcador de inicio sem o de fim -- no meio-editado');
  return codigo.slice(0, i) + novo + codigo.slice(j + FIM.length);
}

const DECLARACOES = [
  INICIO,
  '// LIDO de `regex_envio_de_lista.js` pelo patch -- nao editar aqui.',
  'const ENVIO_RE_LISTA = ' + ENVIO_RE + ';',
  'const NAO_PESSOA_LISTA = ' + NAO_PESSOA_RE + ';',
  'const ESCOLHER_CODIGO_RE = ' + ESCOLHER_CODIGO_RE + ';',
  FN_LISTA.replace(/\bENVIO_RE\b/g, 'ENVIO_RE_LISTA')
          .replace(/\bNAO_PESSOA_RE\b/g, 'NAO_PESSOA_LISTA'),
  '',
  BLOCO_ESCOLHA,
  '',
].join('\n');

// ----------------------------------------------------------------
// 1. `Comando do Tel`: a lista vai INTEIRA, antes do laco de linhas.
(function () {
  const node = nos['Comando do Tel'];
  if (!node) throw new Error('Comando do Tel nao encontrado');
  let c = node.parameters.jsCode;

  {
    // O TOKEN NAO PODE ENTRAR NO REPOSITORIO. Em vez de escrever um bloco
    // novo com ele, reaproveito o header que JA esta no no.
    const mAuth = c.match(/'Authorization':\s*'Bearer [^']+'/);
    if (!mAuth) throw new Error('nao achei o header Authorization no no');
    const mUrl = c.match(/url:\s*'(http:\/\/[^']+\/comando)'/);
    if (!mUrl) throw new Error('nao achei a url do publicador no no');

    const ancora = "const linhas = String(j.texto || '').split('\\n');";
    if (!c.includes(ancora)) {
      throw new Error('o laco de linhas mudou de forma; ancora nao encontrada');
    }

    const ramo = [
      DECLARACOES,
      '// A LISTA COLADA VAI INTEIRA (Tel, 11/09). O laco abaixo manda so a',
      '// linha que casou, e para a lista isso entrega ao publicador um comando',
      '// sem imovel nenhum: os codigos estao nas linhas de baixo. Medido, a',
      '// resposta era "nao entendi qual imovel mandar para Tel Sobreira".',
      '//',
      '// A escolha de codigo ("Nay codigo 5719") entra no MESMO ramo porque e',
      '// ela que dispara o envio da lista que ficou segurada -- e por isso',
      '// tambem precisa do tempo longo.',
      '//',
      '// TIMEOUT DE 10 MINUTOS: o envio roda dentro da requisicao e leva ~50-60s',
      '// por imovel com fotos; quatro imoveis passam dos 120s dos outros ramos.',
      '// Estourar aqui faria o Tel nao receber confirmacao e reenviar -- e a',
      '// trava de 12h em `envios` e que segura o imovel de sair duas vezes.',
      'const textoInteiro = String(j.texto || \'\');',
      'if (ehEnvioDeLista(textoInteiro)',
'    || ESCOLHER_CODIGO_RE.test(textoInteiro.trim())',
'    // "os dois" (12/09): ele respondeu isso e a frase caiu no agente,',
'    // que devolveu uma lista sem nexo. A propria pergunta dela dizia',
'    // "ou os dois".',
'    || ehEscolhaNatural(textoInteiro.trim())) {',
      '  try {',
      '    await this.helpers.httpRequest({',
      "      method: 'POST', url: '" + mUrl[1] + "',",
      "      headers: { 'Content-Type': 'application/json', " + mAuth[0] + ' },',
      '      body: { texto: textoInteiro }, json: true, timeout: 600000',
      '    });',
      '  } catch (e) {}',
      '  return [];',
      '}',
      FIM,
      '',
      ancora,
    ].join('\n');

    // JA APLICADO? troca o bloco inteiro, nunca empilha outro.
    const trocado = trocarBloco(c, soOBloco(ramo), 'Comando do Tel');
    if (trocado !== null) {
      node.parameters.jsCode = trocado;
      console.log('  Comando do Tel: bloco atualizado');
      return;
    }

    // `() => ramo` E OBRIGATORIO, nao estilo. Com a string crua, o
    // `String.replace` do JS interpreta `$` no TEXTO DE SUBSTITUICAO: o
    // `[^\\n]*)$', 'i')` da ESCOLHA_NATURAL_RE contem `$'`, que significa
    // "tudo o que vem depois do trecho casado" -- e o literal entrou no no
    // truncado em `'\\b([^\\n]*)`, uma string sem fechar. JavaScript
    // sintaticamente INVALIDO, que derrubaria o no inteiro em producao.
    // Pego pelo `provar_nos_do_envio.js`, nao pelo `node --check`.
    c = c.replace(ancora, () => ramo);
    node.parameters.jsCode = c;
    console.log('  Comando do Tel: + lista colada e + escolha de codigo');
  }
})();

// ----------------------------------------------------------------
// 2. `Rotear para o agente`: DESCARTA a escolha de codigo.
//
// A lista multilinha ja e descartada ali: o teste do `ENVIO_RE` daquele no
// roda no texto INTEIRO e o corpo dele e guloso, entao casa a colagem toda.
// O que faltava era a escolha -- sem ela o Tel receberia resposta do
// publicador E do agente.
(function () {
  const node = nos['Rotear para o agente'];
  if (!node) throw new Error('Rotear para o agente nao encontrado');
  let c = node.parameters.jsCode;

  {
    const ancora = 'const ehTel = ';
    const i = c.indexOf(ancora);
    if (i < 0) throw new Error('nao achei o ehTel no Rotear para o agente');
    const fim = c.indexOf('\n', i) + 1;

    const ramo = [
      '',
      INICIO,
      '// A ESCOLHA DE CODIGO e comando (Tel, 11/09): quem responde e o',
      '// publicador. Sem este descarte o Tel ouve os dois -- a confirmacao do',
      '// envio e uma resposta do agente sobre o mesmo imovel.',
      '// Mesmo literal de `regex_envio_de_lista.js`, exercitado por',
      '// `casos_envio_de_lista.json` nos dois lados.',
      'const ESCOLHER_CODIGO_RE = ' + ESCOLHER_CODIGO_RE + ';',
      BLOCO_ESCOLHA,
      'if (ehTel && (ESCOLHER_CODIGO_RE.test(t) || ehEscolhaNatural(t))) return [];',
      FIM,
      '',
    ].join('\n');

    const trocado = trocarBloco(c, soOBloco(ramo), 'Rotear para o agente');
    if (trocado !== null) {
      node.parameters.jsCode = trocado;
      console.log('  Rotear para o agente: bloco atualizado');
      return;
    }

    node.parameters.jsCode = c.slice(0, fim) + ramo + c.slice(fim);
    console.log('  Rotear para o agente: + descarte da escolha de codigo');
  }
})();

fs.writeFileSync(process.argv[3],
  JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
