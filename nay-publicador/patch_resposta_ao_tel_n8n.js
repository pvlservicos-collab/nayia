// "sim" e "não" do Tel viram comando QUANDO ELA FEZ UMA PERGUNTA (14/09).
//
// O PEDIDO: o Tel pediu "Posta no grupo anunciar easy 1885", ela recusou
// porque já tinha postado, ele escreveu "Pode postar novamente" -- que caiu no
// AGENTE (não sabia de qual imóvel) -- e depois "1885", que caiu no ramo de
// código puro e mandou o card para o chat DELE. Ele quer: ela pergunta, ele diz
// "sim", ela posta.
//
// QUATRO NÓS, e cada um por um motivo:
//   `Reservar mensagens`   calcula `nay_pergunta_aberta_do_tel()` UMA vez, antes
//                          da divisão -- os ramos rodam em paralelo e precisam do
//                          mesmo retrato (é como o `pede_visita` já faz)
//   `Juntar mensagens`     passa `perguntaAberta` adiante
//   `Comando do Tel`       manda o "sim" ao publicador SÓ com pergunta aberta
//   `Rotear para o agente` DESCARTA o mesmo "sim" -- senão ele ouve os dois
//
// Sem a pergunta aberta, "sim" continua indo para o agente como sempre foi.
//
// Os literais são LIDOS de `regex_resposta_ao_tel.js`. Blocos delimitados por
// marcadores e trocados inteiros, e `() => bloco` em todo replace -- as duas
// lições de 12/09 (`$'` truncando o literal, bloco empilhado duplicando `const`).
//
//   node patch_resposta_ao_tel_n8n.js <entrada.json> <saida.json>
const fs = require('fs');
const path = require('path');

const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));
function no(nome) {
  if (!nos[nome]) throw new Error('no nao encontrado: ' + nome);
  return nos[nome];
}

const fonte = fs.readFileSync(path.join(__dirname, 'regex_resposta_ao_tel.js'), 'utf8');
function literal(nome) {
  const m = fonte.match(new RegExp('const ' + nome + ' = (/\\^[\\s\\S]*?/i);'));
  if (!m) throw new Error('nao achei ' + nome + ' em regex_resposta_ao_tel.js');
  return m[1];
}
const SIM = literal('RESPOSTA_SIM_RE');
const NAO = literal('RESPOSTA_NAO_RE');

const INICIO = '// >>> resposta a pergunta (patch_resposta_ao_tel_n8n.js)';
const FIM = '// <<< resposta a pergunta';

function trocarOuInserir(codigo, ancora, bloco, qualNo) {
  const i = codigo.indexOf(INICIO);
  if (i >= 0) {
    const f = codigo.indexOf(FIM, i);
    if (f < 0) throw new Error(qualNo + ': marcador de inicio sem o de fim');
    return codigo.slice(0, i) + bloco + codigo.slice(f + FIM.length);
  }
  const a = codigo.indexOf(ancora);
  if (a < 0) throw new Error(qualNo + ': ancora nao encontrada: ' + ancora);
  const fimDaLinha = codigo.indexOf('\n', a) + 1;
  return codigo.slice(0, fimDaLinha) + bloco + '\n' + codigo.slice(fimDaLinha);
}

const DECLARACOES = [
  '// LIDO de `regex_resposta_ao_tel.js` pelo patch -- nao editar aqui.',
  'const RESPOSTA_SIM_RE = ' + SIM + ';',
  'const RESPOSTA_NAO_RE = ' + NAO + ';',
  'function respostaAoTel(texto) {',
  "  const s = String(texto || '').trim();",
  "  if (RESPOSTA_SIM_RE.test(s)) return 'sim';",
  "  if (RESPOSTA_NAO_RE.test(s)) return 'nao';",
  '  return null;',
  '}',
].join('\n');

// 1. Reservar mensagens: o sinal nasce antes da divisão
{
  const n = no('Reservar mensagens');
  let q = n.parameters.query;
  if (!q.includes('nay_pergunta_aberta_do_tel')) {
    const ancora = 'nay_opcoes_da_citacao(citado_id) AS opcoes_citacao;';
    if (!q.includes(ancora)) throw new Error('Reservar mensagens: fim da consulta mudou');
    q = q.replace(ancora, () =>
      'nay_opcoes_da_citacao(citado_id) AS opcoes_citacao,\n' +
      '  -- A Nay fez uma pergunta ao Tel e espera "sim"/"nao" (14/09). Calculado\n' +
      '  -- AQUI, uma vez, porque o `Comando do Tel` (manda) e o `Rotear para o\n' +
      '  -- agente` (descarta) rodam em paralelo e precisam do mesmo retrato.\n' +
      '  nay_pergunta_aberta_do_tel() AS pergunta_aberta;');
    n.parameters.query = q;
    console.log('  Reservar mensagens: + pergunta_aberta');
  } else {
    console.log('  Reservar mensagens: (ja tem)');
  }
}

// 2. Juntar mensagens: passa adiante
{
  const n = no('Juntar mensagens');
  let c = n.parameters.jsCode;
  if (!c.includes('perguntaAberta')) {
    const ancora = 'return [{ json: { pedeUnidade: pedeUnidade,';
    if (!c.includes(ancora)) throw new Error('Juntar mensagens: return mudou');
    c = c.replace(ancora, () =>
      'return [{ json: { perguntaAberta: itens.some(m => m.pergunta_aberta === true), ' +
      'pedeUnidade: pedeUnidade,');
    n.parameters.jsCode = c;
    console.log('  Juntar mensagens: + perguntaAberta');
  } else {
    console.log('  Juntar mensagens: (ja tem)');
  }
}

// 3. Comando do Tel: manda o "sim" SÓ com pergunta aberta
{
  const n = no('Comando do Tel');
  const c = n.parameters.jsCode;
  const mAuth = c.match(/'Authorization':\s*'Bearer [^']+'/);
  const mUrl = c.match(/url:\s*'(http:\/\/[^']+\/comando)'/);
  if (!mAuth || !mUrl) throw new Error('Comando do Tel: nao achei url/Authorization');
  const bloco = [
    INICIO,
    DECLARACOES,
    '// Só vale com PERGUNTA ABERTA. Sem ela, "sim" é conversa e segue o caminho',
    '// de sempre. Timeout longo: o "sim" pode postar no Easy com todas as fotos.',
    "if (j.perguntaAberta === true && respostaAoTel(j.texto)) {",
    '  try {',
    '    await this.helpers.httpRequest({',
    "      method: 'POST', url: '" + mUrl[1] + "',",
    "      headers: { 'Content-Type': 'application/json', " + mAuth[0] + ' },',
    "      body: { texto: String(j.texto || '').trim() }, json: true, timeout: 600000",
    '    });',
    '  } catch (e) {}',
    '  return [];',
    '}',
    FIM,
  ].join('\n');
  n.parameters.jsCode = trocarOuInserir(c, "if (String(j.telefone) !== TEL) return [];",
                                        bloco, 'Comando do Tel');
  console.log('  Comando do Tel: bloco da resposta');
}

// 4. Rotear para o agente: descarta o mesmo "sim" -- e SÓ do Tel
{
  const n = no('Rotear para o agente');
  const bloco = [
    INICIO,
    DECLARACOES,
    '// O "sim" que o `Comando do Tel` mandou ao publicador não vai ao agente. Só',
    '// do TEL: o "sim" de um corretor continua sendo conversa (o bug de 27/08).',
    'if (ehTel && j.perguntaAberta === true && respostaAoTel(t)) return [];',
    FIM,
  ].join('\n');
  n.parameters.jsCode = trocarOuInserir(n.parameters.jsCode, 'const ehTel = ',
                                        bloco, 'Rotear para o agente');
  console.log('  Rotear para o agente: bloco da resposta');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
