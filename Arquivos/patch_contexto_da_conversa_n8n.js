// A Nay para de pedir o código de um imóvel que ela acabou de mandar.
//
// O CASO (Márcio, 01 e 02/09). Às 18h32 ele mandou "1327" e a Nay devolveu
// o card da Casa em Nova Cidade. Onze horas depois: "qual o menor valor,
// dessa casa no Nova cidade" -- e ela pediu o código de novo. O Tel: *"ela
// precisa lembrar o contexto da conversa"*.
//
// POR QUE AUMENTAR A MEMÓRIA NÃO RESOLVERIA, e isso foi medido: em
// `nay_memoria` a conversa dele PULA de 18h33 para 19h21. O turno das
// 18h32 -- o que estabeleceu o imóvel -- não está lá, e não foi a janela
// que cortou. Quando o corretor manda só o número, o fluxo atende pelo
// caminho do `Achar codigo`, que NÃO passa pelo agente: ninguém escreve em
// `nay_memoria`. O evento mais informativo da conversa é invisível para
// ela por construção.
//
// Então o contexto sai do DADO, não da memória: `envios` sabe que mandamos
// o 1327 para ele, `mensagens` sabe que ele escreveu 1327, e
// `mensagem_saida` sabe cada card que saiu. Isso não se perde.
//
// A LINHA QUE O TEL TRAÇOU continua de pé: *"concluir que foi o último
// disparado é um tiro no pé"*. Isto NÃO olha disparo de grupo -- só a
// conversa 1 a 1 com este corretor. E com mais de um imóvel na janela, ela
// PERGUNTA com a lista, nunca escolhe.
//
// A segurança não é ela acertar sozinha: é ela DIZER de qual imóvel está
// falando ("sobre a Casa em Nova Cidade, código 1327: ..."), para o
// corretor corrigir na mensagem seguinte se for outro.
//
// E a janela da memória sobe de 15 para 40: não era a causa, mas 15 é
// pouco para conversa que passa o dia -- a do Márcio tem 10 turnos com
// buracos de horas entre eles.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const rm = nos['Reservar mensagens'];
if (rm.parameters.query.includes('nay_aviso_do_foco')) {
  console.log('  (ja aplicado) Reservar mensagens');
} else {
  const ancora = '  nay_pede_visita(texto) AS pede_visita,';
  if (!rm.parameters.query.includes(ancora)) throw new Error('ancora do pede_visita mudou');
  rm.parameters.query = rm.parameters.query.replace(ancora, ancora +
    '\n  -- De qual imovel esta conversa vem falando. Sai do DADO (envios,\n' +
    '  -- mensagens, mensagem_saida), nao da memoria do modelo -- o caminho\n' +
    '  -- do codigo puro nao passa pelo agente e nao entra em `nay_memoria`.\n' +
    '  nay_aviso_do_foco(telefone) AS foco_aviso,');
  console.log('  Reservar mensagens: + foco_aviso');
}

const jm = nos['Juntar mensagens'];
if (jm.parameters.jsCode.includes('focoAviso')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  const ancora = 'const pedeVisita = itens.some(m => m.pede_visita === true);';
  if (!jm.parameters.jsCode.includes(ancora)) throw new Error('ancora do pedeVisita mudou');
  jm.parameters.jsCode = jm.parameters.jsCode.replace(ancora, ancora + '\n' +
    "// O aviso e o mesmo para todas as mensagens do lote (depende do\n" +
    "// telefone, nao do texto): basta o primeiro que veio preenchido.\n" +
    "const focoAviso = (itens.map(m => m.foco_aviso).filter(Boolean)[0]) || null;");
  const saida = 'pedeVisita: pedeVisita,';
  jm.parameters.jsCode = jm.parameters.jsCode.replace(saida, saida + ' focoAviso: focoAviso,');
  console.log('  Juntar mensagens: + focoAviso');
}

const ag = nos['AI Agent'];
if (ag.parameters.text.includes('focoAviso')) {
  console.log('  (ja aplicado) AI Agent');
} else {
  const ancora = ' mensagem do corretor: ';
  ag.parameters.text = ag.parameters.text.replace(ancora,
    " {{ $('Juntar mensagens').first().json.focoAviso || '' }}" + ancora);
  console.log('  AI Agent: recebe o contexto da conversa');
}

const mem = nos['Postgres Chat Memory'];
if (mem.parameters.contextWindowLength === 40) {
  console.log('  (ja aplicado) memoria');
} else {
  mem.parameters.contextWindowLength = 40;
  console.log('  memoria: janela de 15 -> 40 mensagens');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
