// A mensagem marcada passa a dizer QUAL imovel, em vez de virar pergunta.
//
// O CASO (01/09, 09h51): o Victor marcou o card do Rio Amazonas que saiu
// no grupo e escreveu "Me manda esse". A Nay perguntou de qual imovel se
// tratava. O `citado_id` ja chegava -- 3EB044B725B8C809EE1FD0 -- mas
// ninguem guardava o ID das mensagens que a gente manda, entao nao havia
// com o que casar. Agora `envios.message_id` guarda, e
// `nay_imovel_da_citacao` resolve por IGUALDADE, nao por semelhanca.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const achar = (n) => { const x = wf.nodes.find((y) => y.name === n); if (!x) throw new Error(n); return x; };

// ---------- Reservar mensagens: resolve a citacao na propria query ----------
const res = achar('Reservar mensagens');
if (res.parameters.query.includes('nay_imovel_da_citacao')) {
  console.log('  (ja aplicado) Reservar mensagens');
} else {
  const de = "  nay_codigos_citados(coalesce(texto,'')) AS codigos_citados;";
  if (!res.parameters.query.includes(de)) throw new Error('ancora do Reservar mudou');
  res.parameters.query = res.parameters.query.replace(de,
    "  nay_codigos_citados(coalesce(texto,'')) AS codigos_citados,\n" +
    '  -- A citacao vira o codigo do imovel por IGUALDADE de messageId.\n' +
    '  -- NULL quando nao resolve, e nao resolver continua levando a\n' +
    '  -- perguntar -- nunca a chutar.\n' +
    '  nay_imovel_da_citacao(citado_id) AS codigo_citado;');
  console.log('  Reservar mensagens: resolve a citacao');
}

// ---------- Juntar mensagens: propaga ----------
const ju = achar('Juntar mensagens');
if (ju.parameters.jsCode.includes('codigoCitado')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  ju.parameters.jsCode = ju.parameters.jsCode.replace(
    "const citadoId = (itens.map(m => m.citado_id).filter(Boolean)[0]) || null;",
    "const citadoId = (itens.map(m => m.citado_id).filter(Boolean)[0]) || null;\n" +
    '// O imovel da mensagem que ele marcou, quando a gente consegue casar.\n' +
    'const codigoCitado = (itens.map(m => m.codigo_citado).filter(Boolean)[0]) || null;');
  ju.parameters.jsCode = ju.parameters.jsCode.replace(
    'return [{ json: { pedeUnidade: pedeUnidade, citadoId: citadoId, ',
    'return [{ json: { pedeUnidade: pedeUnidade, citadoId: citadoId, codigoCitado: codigoCitado, ');
  console.log('  Juntar mensagens: propaga codigoCitado');
}

// ---------- AI Agent: ela SABE o imovel ----------
const ag = achar('AI Agent');
if (ag.parameters.text.includes('codigoCitado')) {
  console.log('  (ja aplicado) AI Agent');
} else {
  const marca = " mensagem do corretor: ";
  if (!ag.parameters.text.includes(marca)) throw new Error('ancora do AI Agent mudou');
  ag.parameters.text = ag.parameters.text.replace(marca,
    " {{ $('Juntar mensagens').first().json.codigoCitado ? " +
    "'ele MARCOU a mensagem do imovel ' + $('Juntar mensagens').first().json.codigoCitado + " +
    "'. E desse que ele fala -- isto nao e palpite, e a mensagem que ele apontou. " +
    "Siga a conversa com esse codigo e NAO pergunte qual e. ' : '' }}" + marca);
  console.log('  AI Agent: recebe o imovel marcado');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
