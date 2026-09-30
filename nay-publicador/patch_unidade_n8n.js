// Patch do fluxo `Nay- recebe mensagem` para a parede do numero da unidade.
//
// TRES EDICOES, e nenhuma delas cria uma copia da regra: quem decide se a
// pergunta pede a unidade continua sendo `nay_pede_localizacao_da_unidade`,
// no banco. O n8n so carrega o booleano.
//
//   1. `Gravar na fila` (SQL) calcula `pede_unidade` por mensagem
//   2. `Juntar mensagens` (JS)  faz OR entre as mensagens do lote
//   3. `AI Agent` (expressao)   injeta a regra NO TURNO, nao no prompt
//
// POR QUE NO TURNO E NAO NO PROMPT: o prompt de 28 mil caracteres JA diz
// "o numero da unidade, nunca" em quatro lugares -- e ela prometeu
// verificar assim mesmo. Instrucao no turno, so quando o caso acontece,
// e a unica que ela nao dilui. E ainda assim e a segunda linha de defesa:
// a primeira e `nay_escalar`, que recusa no banco.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
// `n8n export:workflow --id=X` devolve um ARRAY de um elemento, nao o
// objeto. Aceitar as duas formas evita quebrar quando o formato mudar.
const wf = Array.isArray(bruto) ? bruto[0] : bruto;

function achar(nome) {
  const n = wf.nodes.find((x) => x.name === nome);
  if (!n) throw new Error('no nao encontrado: ' + nome);
  return n;
}

// ---------- 1. Gravar na fila ----------
const grava = achar('Gravar na fila');
const alvo = `       COALESCE((SELECT valor = 'sim' FROM config
                  WHERE chave = 'atendimento_pausado'), false) AS pausado`;
if (grava.parameters.query.includes('pede_unidade')) {
  console.log('  (Gravar na fila ja tinha pede_unidade, nao mexi)');
} else {
  if (!grava.parameters.query.includes(alvo)) throw new Error('ancora do Gravar na fila mudou');
  grava.parameters.query = grava.parameters.query.replace(
    alvo,
    alvo + `,\n       -- A pergunta pede o numero do apartamento? A regra mora em\n` +
      `       -- unidade_nunca.sql; aqui so vem o resultado, para nao existir\n` +
      `       -- uma segunda copia dela em JavaScript.\n` +
      `       nay_pede_localizacao_da_unidade(NULLIF($4,'null')) AS pede_unidade`
  );
  console.log('  Gravar na fila: coluna pede_unidade acrescentada');
}

// ---------- 2. Juntar mensagens ----------
const junta = achar('Juntar mensagens');
const alvoJs = 'return [{ json: { telefone: itens[0].telefone,';
if (junta.parameters.jsCode.includes('pedeUnidade')) {
  console.log('  (Juntar mensagens ja tinha pedeUnidade, nao mexi)');
} else {
  if (!junta.parameters.jsCode.includes(alvoJs)) throw new Error('ancora do Juntar mensagens mudou');
  junta.parameters.jsCode = junta.parameters.jsCode.replace(
    alvoJs,
    '// OR entre as mensagens do lote: se o corretor mandou duas linhas e a\n' +
      '// pergunta da unidade esta na segunda, a parede tem que valer igual.\n' +
      'const pedeUnidade = itens.some(m => m.pede_unidade === true);\n' +
      'return [{ json: { pedeUnidade: pedeUnidade, telefone: itens[0].telefone,'
  );
  console.log('  Juntar mensagens: pedeUnidade acrescentado');
}

// ---------- 3. AI Agent ----------
const agente = achar('AI Agent');
const marca = ' mensagem do corretor: ';
if (agente.parameters.text.includes('pedeUnidade')) {
  console.log('  (AI Agent ja tinha a regra, nao mexi)');
} else {
  if (!agente.parameters.text.includes(marca)) throw new Error('ancora do AI Agent mudou');
  const regra =
    "{{ $('Juntar mensagens').first().json.pedeUnidade ? " +
    "'ATENCAO, REGRA FIXA DA IMOB EASY: ele esta pedindo o numero do apartamento, " +
    'a unidade, o complemento ou o endereco exato. Voce NAO passa isso, NAO promete ' +
    'verificar, NAO diz que vai perguntar ao Tel e NAO diz que retorna depois. Diga ' +
    'no seu tom que esse dado a gente so passa na hora da visita agendada, que e ' +
    'politica para todos os imoveis e nao e nada contra ele, e ofereca agendar a ' +
    'visita. Depois siga ajudando no resto normalmente -- valor, area, quartos, ' +
    "fotos, tudo isso voce passa. NAO chame escalar_ao_tel para isso. ' : '' }}";
  agente.parameters.text = agente.parameters.text.replace(marca, ' ' + regra + marca);
  console.log('  AI Agent: regra injetada no turno');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
