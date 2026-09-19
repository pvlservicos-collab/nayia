// O portão de fotos para de ler o texto que o PRÓPRIO fluxo escreveu.
//
// O CASO (Gustavo, 01/09): por áudio ele disse "não, as fotos eu já tenho,
// agora eu quero saber só o valor de entrada" -- e recebeu o card e as 11
// fotos de novo. A regra nova no prompt não impediu nada, porque quem
// decide não é o modelo: é `nay_deve_mandar_fotos`, dentro da query do nó
// `Buscar fotos do agente`.
//
// E ela recebia o texto ERRADO. Para áudio, `Juntar mensagens` troca o
// texto do corretor por um envelope de sistema que terminava em "Antes de
// mandar imovel ou fotos, repita...". Essa frase tem a palavra "fotos".
// Medido no banco: para 100% dos áudios, qualquer que fosse o conteúdo, o
// portão devolvia `true`.
//
// Duas mudanças, as duas de separação -- não de texto:
//   1. `textoCru` carrega o que o CORRETOR falou (a transcrição pura, ou o
//      que ele digitou), e é ele que vai ao portão. O envelope continua
//      indo ao modelo, que é para quem ele foi escrito.
//   2. o envelope deixa de citar "fotos". Não é o conserto -- é para que o
//      próximo texto de sistema não reabra a porta por acidente.
//
// O `escreveu` do comando (a quarta cópia da gramática) continua lendo o
// texto INTEIRO de propósito: se `textoCru` faltasse, ele voltaria a
// deixar passar "Nay envia as fotos do 5750 pro Sergio" e as fotos iriam
// para o chat do Tel.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

// ---------- 1. `Juntar mensagens` passa a carregar o texto cru ----------
const jm = nos['Juntar mensagens'];
if (!jm) throw new Error('Juntar mensagens nao encontrado');
let c = jm.parameters.jsCode;

if (c.includes('textoCru')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  const ancora = "let transcrito = '';";
  if (!c.includes(ancora)) throw new Error('ancora do transcrito mudou');
  c = c.replace(ancora,
    "// O QUE O CORRETOR FALOU, sem envelope de sistema nenhum. E este que\n" +
    "// vai ao portao de fotos: os envelopes abaixo sao escritos por NOS, e\n" +
    "// um deles tinha a palavra 'fotos' dentro.\n" +
    "let textoCru = texto;\n" + ancora);

  const envelope = "  texto = '(o corretor mandou um audio. transcricao: \"' + transcrito + '\") Antes de mandar imovel ou fotos, repita em uma linha o que voce entendeu e peca confirmacao.';";
  if (!c.includes(envelope)) throw new Error('envelope de audio mudou');
  c = c.replace(envelope,
    "  textoCru = transcrito;\n" +
    "  texto = '(o corretor mandou um audio. transcricao: \"' + transcrito + '\") Antes de enviar qualquer material, repita em uma linha o que voce entendeu e peca confirmacao.';");

  const saida = 'texto: texto, citado: citado,';
  if (!c.includes(saida)) throw new Error('saida do Juntar mensagens mudou');
  c = c.replace(saida, 'texto: texto, textoCru: textoCru, citado: citado,');

  jm.parameters.jsCode = c;
  console.log('  Juntar mensagens: textoCru + envelope sem a palavra "fotos"');
}

// ---------- 2. `Achar codigo na resposta` manda o cru ao portao ----------
const ac = nos['Achar codigo na resposta'];
if (!ac) throw new Error('Achar codigo na resposta nao encontrado');
let a = ac.parameters.jsCode;

if (a.includes('const cru =')) {
  console.log('  (ja aplicado) Achar codigo na resposta');
} else {
  const ancora = "const escreveu = String(j.texto || '');";
  if (!a.includes(ancora)) throw new Error('ancora do escreveu mudou');
  a = a.replace(ancora, ancora +
    "\n// O que sai daqui como `escreveu` alimenta `nay_deve_mandar_fotos`.\n" +
    "// Tem que ser a fala DELE, nunca o envelope que este fluxo escreveu.\n" +
    "// O fallback existe para o caso de `Juntar mensagens` ser mais antigo\n" +
    "// que este no -- mas o guarda de comando acima continua lendo `escreveu`\n" +
    "// inteiro, senao um `textoCru` vazio abriria a porta que ele fecha.\n" +
    "const cru = String(j.textoCru !== undefined && j.textoCru !== null ? j.textoCru : (j.texto || ''));");

  const saida = 'escreveu: escreveu\n} }];';
  if (!a.includes(saida)) {
    const alt = 'escreveu: escreveu';
    if (a.split(alt).length - 1 !== 2) throw new Error('saida do Achar codigo mudou');
    // duas ocorrencias: a do ramo de comando (`escreveu: ''`) nao casa com
    // este texto, entao a que sobra e a do retorno final.
    a = a.replace(/escreveu: escreveu(\s*\n\} \}\];)/, 'escreveu: cru$1');
  } else {
    a = a.replace(saida, 'escreveu: cru\n} }];');
  }
  if (!a.includes('escreveu: cru')) throw new Error('nao consegui trocar a saida');
  ac.parameters.jsCode = a;
  console.log('  Achar codigo na resposta: o portao passa a ler o texto cru');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
