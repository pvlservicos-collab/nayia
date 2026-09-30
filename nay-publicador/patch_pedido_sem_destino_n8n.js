/*
 * "Nay envia locacao de 3k a 6k nos bairros parque dez" -- o pedido COM VALOR
 * e SEM destinatario, nos dois nos que decidem.
 *
 * O QUE ESTE PATCH RESOLVE, medido em 15/09: a frase nao tem "para" nenhum,
 * entao nao casa o ENVIO_RE; e "locacao" nao esta na lista de substantivos do
 * ramo de categoria. Ela ia inteira para o AGENTE de IA, que respondia sobre
 * imoveis em vez de mandar -- foi o "mandei para a Nay isso e ela nao soube
 * enviar" que o Tel relatou.
 *
 * OS DOIS NOS PRECISAM CONCORDAR, por motivos opostos:
 *   `Comando do Tel`       -> manda para o publicador (senao o comando morre)
 *   `Rotear para o agente` -> DESCARTA (senao ele recebe resposta dupla)
 *
 * O literal e LIDO de `regex_envio_de_lista.js`, nunca redigitado aqui: uma
 * barra invertida a mais dentro de um patch ja produziu literal que nao casava
 * NADA, com o comando morrendo em silencio.
 *
 *   node patch_pedido_sem_destino_n8n.js <entrada.json> <saida.json>
 */
const fs = require('fs');
const path = require('path');

const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const fonte = fs.readFileSync(
  path.join(__dirname, 'regex_envio_de_lista.js'), 'utf8');

function trecho(re) {
  const m = fonte.match(re);
  if (!m) throw new Error('nao achei o trecho ' + re + ' em regex_envio_de_lista.js');
  return m[0];
}

const DECLARACOES = [
  trecho(/const VALOR_ESCRITO = [\s\S]*?;\n/),
  trecho(/const PEDIDO_SEM_DESTINO_RE = new RegExp\([\s\S]*?'i'\);\n/),
].join('\n');

const INICIO = '// >>> pedido sem destinatario (patch_pedido_sem_destino_n8n.js)';
const FIM = '// <<< pedido sem destinatario';

// Bloco DELIMITADO, trocado inteiro a cada rodada. A alternativa (guarda por
// `includes`) ja duplicou uma declaracao `const` no mesmo escopo e derrubou o
// no inteiro em producao -- ver `patch_envio_de_lista_n8n.js`.
function trocarOuInserir(codigo, bloco, ancora, qualNo) {
  const i = codigo.indexOf(INICIO);
  if (i >= 0) {
    const j = codigo.indexOf(FIM, i);
    if (j < 0) throw new Error(qualNo + ': marcador de inicio sem o de fim');
    return codigo.slice(0, i) + bloco + codigo.slice(j + FIM.length);
  }
  if (codigo.includes('PEDIDO_SEM_DESTINO_RE')) {
    throw new Error(qualNo + ' tem um bloco sem marcador -- aplicar por cima '
                    + 'duplicaria a declaracao. Rode a partir do backup.');
  }
  if (!codigo.includes(ancora)) {
    throw new Error(qualNo + ': ancora nao encontrada -- o no mudou de forma');
  }
  return codigo.replace(ancora, () => bloco + '\n' + ancora);
}

// ----------------------------------------------------------------
// 1. `Comando do Tel`: manda a linha ao publicador.
(function () {
  const node = nos['Comando do Tel'];
  if (!node) throw new Error('Comando do Tel nao encontrado');
  const c = node.parameters.jsCode;

  // O TOKEN NAO ENTRA NO REPOSITORIO: reaproveita o header que ja esta no no.
  const mAuth = c.match(/'Authorization':\s*'Bearer [^']+'/);
  if (!mAuth) throw new Error('nao achei o header Authorization no no');
  const mUrl = c.match(/url:\s*'(http:\/\/[^']+\/comando)'/);
  if (!mUrl) throw new Error('nao achei a url do publicador no no');

  // DEPOIS do ENVIO_RE e ANTES do ramo de categoria: o ramo de categoria pega
  // "Nay envia casa ..." com 8s de timeout, e um pedido resolvido contra o
  // catalogo pode passar disso.
  const ancora = '  if (/^(@?NAY\\b[\\s,:;.!\\-]*)?((POSTA|POSTAR|PUBLICA|';
  const bloco = [
    INICIO,
    '  // LIDO de `regex_envio_de_lista.js` pelo patch -- nao editar aqui.',
    '  ' + DECLARACOES.trim().replace(/\n/g, '\n  '),
    '  if (PEDIDO_SEM_DESTINO_RE.test(linha)) {',
    '    try {',
    '      await this.helpers.httpRequest({',
    "        method: 'POST', url: '" + mUrl[1] + "',",
    "        headers: { 'Content-Type': 'application/json', " + mAuth[0] + ' },',
    '        body: { texto: linha }, json: true, timeout: 120000',
    '      });',
    '    } catch (e) {}',
    '    return [];',
    '  }',
    FIM,
  ].join('\n');

  node.parameters.jsCode = trocarOuInserir(c, bloco, ancora, 'Comando do Tel');
  console.log('  Comando do Tel: + pedido sem destinatario');
})();

// ----------------------------------------------------------------
// 2. `Rotear para o agente`: DESCARTA, para o Tel nao receber resposta dupla.
(function () {
  const node = nos['Rotear para o agente'];
  if (!node) throw new Error('Rotear para o agente nao encontrado');
  const c = node.parameters.jsCode;

  const ancora = 'if (ehTel && ehComandoDePendencia(t)) return [];';
  const bloco = [
    INICIO,
    '// LIDO de `regex_envio_de_lista.js` pelo patch -- nao editar aqui.',
    DECLARACOES.trim(),
    '// So do Tel: a MESMA frase vinda de um corretor segue para o agente --',
    '// foi o bug de 27/08, em que o corretor nao recebia nada.',
    'if (ehTel && PEDIDO_SEM_DESTINO_RE.test(t)) return [];',
    FIM,
  ].join('\n');

  node.parameters.jsCode = trocarOuInserir(c, bloco, ancora, 'Rotear para o agente');
  console.log('  Rotear para o agente: descarta o pedido sem destinatario');
})();

fs.writeFileSync(process.argv[3], JSON.stringify(wf, null, 2));
console.log('gravado em ' + process.argv[3]);
