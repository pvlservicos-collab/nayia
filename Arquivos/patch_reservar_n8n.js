// A segunda camada estava MORTA, e o red team de 01/09 mostrou por que.
//
// `Juntar mensagens` le de `Reservar mensagens`, nao de `Gravar na fila`.
// E o RETURNING do Reservar traz so:
//     id, telefone, nome, origem, texto, citado, criada_em
// Entao `pede_unidade`, `codigos_citados` e `citadoId` -- os tres campos
// que acrescentei hoje no Gravar -- chegavam como `undefined`:
//   * pedeUnidade sempre falso  -> o aviso no turno do agente NUNCA saiu
//   * codigosDele sempre vazio  -> o no de fotos voltava a usar a regex crua
//   * citadoId sempre nulo      -> o aviso de citacao NUNCA saiu
//
// `pede_unidade` e `codigos_citados` sao funcao pura do texto, entao dao
// para calcular no proprio RETURNING. `citado_id` vem do payload e
// precisa de coluna -- criada agora em `mensagens`.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const achar = (n) => { const x = wf.nodes.find((y) => y.name === n); if (!x) throw new Error(n); return x; };

// ---------- Reservar mensagens: devolve o que o Juntar precisa ----------
const res = achar('Reservar mensagens');
if (res.parameters.query.includes('pede_unidade')) {
  console.log('  (ja aplicado) Reservar mensagens');
} else {
  const de = 'RETURNING id, telefone, nome, origem, texto, citado, criada_em;';
  if (!res.parameters.query.includes(de)) throw new Error('ancora do Reservar mudou');
  res.parameters.query = res.parameters.query.replace(de,
    'RETURNING id, telefone, nome, origem, texto, citado, citado_id, criada_em,\n' +
    '  -- Calculados AQUI, e nao no `Gravar na fila`: e deste no que o\n' +
    '  -- `Juntar mensagens` le. Ficando so la, chegavam como undefined e\n' +
    '  -- a segunda camada inteira era letra morta.\n' +
    '  nay_pede_localizacao_da_unidade(texto) AS pede_unidade,\n' +
    "  nay_codigos_citados(coalesce(texto,'')) AS codigos_citados;");
  console.log('  Reservar mensagens: devolve pede_unidade, codigos_citados e citado_id');
}

// ---------- Gravar na fila: grava o citado_id ----------
const gr = achar('Gravar na fila');
if (gr.parameters.query.includes('citado_id')) {
  console.log('  (ja aplicado) Gravar na fila');
} else {
  const de = 'INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, citado)';
  if (!gr.parameters.query.includes(de)) throw new Error('ancora do INSERT mudou');
  gr.parameters.query = gr.parameters.query
    .replace(de, 'INSERT INTO mensagens (telefone, nome, direcao, origem, texto, status, citado, citado_id)')
    .replace("          NULLIF($5, 'null'))", "          NULLIF($5, 'null'), NULLIF($9, 'null'))");
  const o = gr.parameters.options.queryReplacement;
  gr.parameters.options.queryReplacement = o.replace(
    '$json.dbg_estrutura ?? null] }}',
    '$json.dbg_estrutura ?? null, $json.citadoId ?? null] }}');
  console.log('  Gravar na fila: grava citado_id');
}

// ---------- Juntar mensagens: le o nome da coluna ----------
const ju = achar('Juntar mensagens');
if (ju.parameters.jsCode.includes('m.citado_id')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  ju.parameters.jsCode = ju.parameters.jsCode.replace(
    'const citadoId = (itens.map(m => m.citadoId).filter(Boolean)[0]) || null;',
    '// `citado_id` (snake) e o nome que vem do RETURNING do Postgres.\n' +
    'const citadoId = (itens.map(m => m.citado_id).filter(Boolean)[0]) || null;');
  console.log('  Juntar mensagens: le citado_id');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
