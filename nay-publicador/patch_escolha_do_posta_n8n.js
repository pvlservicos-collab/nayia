/*
 * A resposta a pergunta do `posta <nome do condominio>`, nos TRES nos que
 * decidem o que acontece com ela.
 *
 * O QUE ACONTECE SEM ISTO, medido em 15/09: "locacao" sozinho vai para o
 * AGENTE de IA (que responde qualquer coisa sobre locacao) e a pergunta da
 * Nay fica aberta para sempre; e "5725" sozinho cai no `Achar codigo`, que
 * manda o card no privado do Tel em vez de postar nos grupos.
 *
 *   `Comando do Tel`       -> manda ao publicador
 *   `Rotear para o agente` -> DESCARTA, senao o agente responde por cima
 *   `Achar codigo`         -> nao busca o card; os ramos rodam em PARALELO,
 *                             e ele receberia o card no privado ao mesmo
 *                             tempo em que o imovel sai nos grupos
 *
 * So com PERGUNTA ABERTA (`nay_pergunta_aberta_do_tel`, calculado no
 * `Reservar mensagens` e propagado pelo `Juntar mensagens`): sem ela, "5725"
 * continua sendo o codigo puro de sempre e "venda" continua sendo conversa.
 *
 * O literal e LIDO de `regex_escolha_do_posta.js`, nunca redigitado: barra
 * invertida a mais dentro de um patch ja gerou literal que nao casava NADA,
 * com o comando morrendo em silencio.
 *
 *   node patch_escolha_do_posta_n8n.js <entrada.json> <saida.json>
 */
const fs = require('fs');
const path = require('path');

const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const fonte = fs.readFileSync(
  path.join(__dirname, 'regex_escolha_do_posta.js'), 'utf8');

function trecho(re) {
  const m = fonte.match(re);
  if (!m) throw new Error('nao achei o trecho ' + re + ' em regex_escolha_do_posta.js');
  return m[0];
}

const DECLARACOES = [
  trecho(/const PREFIXO_DA_ESCOLHA =[\s\S]*?;\n/),
  trecho(/const ESCOLHA_DO_POSTA_RE = new RegExp\([\s\S]*?'i'\);\n/),
].join('\n');

const INICIO = '// >>> escolha do posta (patch_escolha_do_posta_n8n.js)';
const FIM = '// <<< escolha do posta';

function trocarOuInserir(codigo, bloco, ancora, qualNo) {
  const i = codigo.indexOf(INICIO);
  if (i >= 0) {
    const j = codigo.indexOf(FIM, i);
    if (j < 0) throw new Error(qualNo + ': marcador de inicio sem o de fim');
    return codigo.slice(0, i) + bloco + codigo.slice(j + FIM.length);
  }
  if (codigo.includes('ESCOLHA_DO_POSTA_RE')) {
    throw new Error(qualNo + ' tem um bloco sem marcador -- aplicar por cima '
                    + 'duplicaria a declaracao. Rode a partir do backup.');
  }
  if (!codigo.includes(ancora)) {
    throw new Error(qualNo + ': ancora nao encontrada -- o no mudou de forma');
  }
  return codigo.replace(ancora, () => bloco + '\n' + ancora);
}

// O TELEFONE DO TEL sai do no que ja o tem -- nao redigitado aqui.
const telTel = (nos['Rotear para o agente'].parameters.jsCode
  .match(/'(\d{12,13})'/) || [])[1];
if (!telTel) throw new Error('nao achei o telefone do Tel no `Rotear para o agente`');

// ----------------------------------------------------------------
// 1. `Comando do Tel`: manda a resposta ao publicador.
(function () {
  const node = nos['Comando do Tel'];
  if (!node) throw new Error('Comando do Tel nao encontrado');
  const c = node.parameters.jsCode;

  const mAuth = c.match(/'Authorization':\s*'Bearer [^']+'/);
  if (!mAuth) throw new Error('nao achei o header Authorization no no');
  const mUrl = c.match(/url:\s*'(http:\/\/[^']+\/comando)'/);
  if (!mUrl) throw new Error('nao achei a url do publicador no no');

  // DEPOIS do ramo da lista colada e da escolha natural (que ja pegaram
  // "codigo 5725" e "os dois"), ANTES do laco de linhas.
  const ancora = "const linhas = String(j.texto || '').split('\\n');";
  const bloco = [
    INICIO,
    '// LIDO de `regex_escolha_do_posta.js` pelo patch -- nao editar aqui.',
    DECLARACOES.trim(),
    '// TIMEOUT LONGO: a resposta dele DISPARA a postagem nos grupos, com',
    '// foto -- e o ramo de comando curto (8s) estouraria no meio.',
    "const respostaDoPosta = String(j.texto || '').trim();",
    'if (j.perguntaAberta === true && ESCOLHA_DO_POSTA_RE.test(respostaDoPosta)) {',
    '  try {',
    '    await this.helpers.httpRequest({',
    "      method: 'POST', url: '" + mUrl[1] + "',",
    "      headers: { 'Content-Type': 'application/json', " + mAuth[0] + ' },',
    '      body: { texto: respostaDoPosta }, json: true, timeout: 600000',
    '    });',
    '  } catch (e) {}',
    '  return [];',
    '}',
    FIM,
  ].join('\n');

  node.parameters.jsCode = trocarOuInserir(c, bloco, ancora, 'Comando do Tel');
  console.log('  Comando do Tel: + escolha do posta');
})();

// ----------------------------------------------------------------
// 2. `Rotear para o agente`: DESCARTA.
(function () {
  const node = nos['Rotear para o agente'];
  const c = node.parameters.jsCode;
  const ancora = 'if (ehTel && ehComandoDePendencia(t)) return [];';
  const bloco = [
    INICIO,
    '// LIDO de `regex_escolha_do_posta.js` pelo patch -- nao editar aqui.',
    DECLARACOES.trim(),
    '// So do Tel e so com pergunta aberta: a mesma palavra vinda de um',
    '// corretor, ou sem pergunta nenhuma, segue para o agente como sempre.',
    'if (ehTel && j.perguntaAberta === true && ESCOLHA_DO_POSTA_RE.test(t)) return [];',
    FIM,
  ].join('\n');
  node.parameters.jsCode = trocarOuInserir(c, bloco, ancora, 'Rotear para o agente');
  console.log('  Rotear para o agente: descarta a escolha do posta');
})();

// ----------------------------------------------------------------
// 3. `Achar codigo`: com pergunta aberta, o numero e RESPOSTA, nao pedido.
(function () {
  const node = nos['Achar codigo'];
  if (!node) throw new Error('Achar codigo nao encontrado');
  const c = node.parameters.jsCode;
  const ancora = "if (!/^\\d{3,5}$/.test(t)) return [];";
  const bloco = [
    INICIO,
    '// Com pergunta aberta ao Tel, o numero sozinho e a RESPOSTA dela -- e',
    '// quem a resolve e o publicador. Sem esta parede ele recebe o card no',
    '// privado ao mesmo tempo em que o imovel sai nos grupos: os ramos do',
    '// fluxo rodam em PARALELO.',
    '//',
    '// So para o TEL: o mesmo numero vindo de um corretor continua pedindo',
    '// o card, que e o caminho dele desde sempre.',
    "if (j.perguntaAberta === true && String(j.telefone) === '" + telTel + "') return [];",
    FIM,
  ].join('\n');
  node.parameters.jsCode = trocarOuInserir(c, bloco, ancora, 'Achar codigo');
  console.log('  Achar codigo: nao busca card com pergunta aberta');
})();

fs.writeFileSync(process.argv[3], JSON.stringify(wf, null, 2));
console.log('gravado em ' + process.argv[3]);
