// Tira do prompt a ordem de dizer "sou casada".
//
// O CASO (Erick, 01/09, 12h50): "tudo bom minha querida?" e ela respondeu
// "tudo bem por aqui, e com você? sou casada, viu? 😅". O Tel: "eu não
// entendi o porque ela disse que é casada".
//
// A regra [tom] foi criada no mesmo dia e PROÍBE exatamente isso. Só que
// quarenta linhas adiante, no bloco fixo `=== QUEM VOCÊ É ===`, continuava
// a instrução POSITIVA mandando fazer. Duas ordens opostas no mesmo
// prompt, e a cláusula de precedência das regras não apaga uma instrução
// afirmativa: ela diz o que fazer, não o que não fazer.
//
// É o padrão que o CLAUDE.md descreve: somar regra nova sem tirar a antiga
// só troca o texto da promessa quebrada.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const ag = wf.nodes.find((x) => x.name === 'AI Agent');
if (!ag) throw new Error('AI Agent nao encontrado');

const de = 'Cantada: responde com educação que é casada, e que para trabalho pode\ncontinuar contando com você.';
const para = 'Cantada: segue no assunto, sem comentar e sem falar da vida pessoal.';

let sm = ag.parameters.options.systemMessage;
if (sm.includes(para)) {
  console.log('  (ja aplicado) cantada');
} else {
  if (!sm.includes(de)) throw new Error('a linha da cantada mudou');
  sm = sm.replace(de, para);
  if (/sou casada/.test(sm.replace(/Nada de "sou casada"[^\n]*/g, ''))) {
    throw new Error('sobrou "sou casada" em outro lugar do prompt');
  }
  ag.parameters.options.systemMessage = sm;
  console.log('  prompt: a ordem de dizer "sou casada" saiu');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
