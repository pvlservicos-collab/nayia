// A descrição da ferramenta para de mandar tratar TUDO como final.
//
// A função ganhou um caminho novo: quando o nome só se parece com um
// condomínio nosso, ela devolve "você quis dizer X?" em vez de afirmar.
// A descrição antiga dizia "a resposta vem do sistema e e FINAL: se
// disser que nao tem, diga que nao tem" -- o que, nesse caminho, mandaria
// negar um condomínio que o corretor nem perguntou.
//
// Quem manda agora é a `instrucao_para_voce`, que vem por caso.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const no = wf.nodes.find((x) => x.name === 'disponibilidade_no_condominio');
if (!no) throw new Error('disponibilidade_no_condominio nao encontrado');

const de = 'A ' +
  'resposta vem do sistema e e FINAL: se disser que nao tem, diga que nao tem ' +
  'e NAO escale ao Tel -- o que nao esta no nosso sistema ja saiu da carteira. ';
const para = 'SIGA A ' +
  'instrucao_para_voce que vier junto, ao pe da letra: e ela que diz se aquela ' +
  'resposta e final, se voce deve perguntar qual condominio ele quis dizer, ou se ' +
  'o imovel e de parceria. Quando a instrucao disser que e resposta, NAO escale ao ' +
  'Tel e NAO diga que vai verificar. Quando ela mandar perguntar, pergunte e chame ' +
  'esta ferramenta de novo com o que ele responder -- nunca afirme disponibilidade ' +
  'sobre um condominio que ele nao confirmou. ';

if (no.parameters.toolDescription.includes('SIGA A instrucao_para_voce')) {
  console.log('  (ja aplicado) disponibilidade_no_condominio');
} else {
  if (!no.parameters.toolDescription.includes(de)) throw new Error('a descricao mudou');
  no.parameters.toolDescription = no.parameters.toolDescription.replace(de, para);
  console.log('  disponibilidade_no_condominio: quem manda e a instrucao_para_voce');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
