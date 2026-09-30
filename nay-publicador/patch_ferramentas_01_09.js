// As três ferramentas que faltavam, e o conserto da instrução que
// mandava a Nay nunca concluir nada.
//
//   1. disponibilidade_no_condominio -- responde "tem/não tem" pelo NOME
//      do condomínio, sem escalar. O Tel: "é de extrema urgência que a
//      gente coloque o nome do condomínio também para ela identificar".
//   2. o_que_sei_do_imovel -- o que o Tel já explicou daquele imóvel,
//      consultado ANTES de escalar.
//   3. guardar_do_imovel -- o Tel ensina uma vez e ela não pergunta mais.
//   4. resumo_do_condominio deixa de dizer "Nunca responda que nao tem".
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;

const modelo = wf.nodes.find((x) => x.name === 'como_funciona_a_visita');
if (!modelo) throw new Error('modelo de ferramenta nao encontrado');

function ferramenta(nome, id, desc, query, repl, pos) {
  if (wf.nodes.some((x) => x.name === nome)) { console.log('  (ja existe) ' + nome); return; }
  wf.nodes.push({
    parameters: {
      descriptionType: 'manual',
      toolDescription: desc,
      operation: 'executeQuery',
      query: query,
      options: repl ? { queryReplacement: repl } : {},
    },
    type: modelo.type,
    typeVersion: modelo.typeVersion,
    position: pos,
    id: id,
    name: nome,
    credentials: modelo.credentials,
  });
  wf.connections[nome] = { ai_tool: [[{ node: 'AI Agent', type: 'ai_tool', index: 0 }]] };
  console.log('  criada: ' + nome);
}

ferramenta('disponibilidade_no_condominio', 'tool-disp-cond-01',
  'Diz se a Imob Easy TEM ou NAO TEM imovel num condominio, pelo NOME dele -- ' +
  'o corretor nao precisa saber o codigo. CHAME SEMPRE que ele perguntar se ' +
  'algo esta disponivel citando o nome do condominio ou colando um anuncio. ' +
  'Passe tambem se ele quer venda ou locacao, quando ele tiver dito. A ' +
  'resposta vem do sistema e e FINAL: se disser que nao tem, diga que nao tem ' +
  'e NAO escale ao Tel -- o que nao esta no nosso sistema ja saiu da carteira. ' +
  'Quando vier um codigo preenchido, e porque so existe um imovel la e voce ja ' +
  'pode seguir com ele.',
  'SELECT texto_pronto, codigo, instrucao_para_voce FROM nay_disponibilidade_no_condominio($1,$2);',
  "={{ [$fromAI('condominio', 'o nome do condominio como o corretor escreveu', 'string') ?? null, " +
  "$fromAI('negocio', 'venda ou locacao, se ele tiver dito; senao deixe vazio', 'string') ?? null] }}",
  [2128, 560]);

ferramenta('o_que_sei_do_imovel', 'tool-sei-imovel-01',
  'O que o Tel JA explicou sobre ESTE imovel e que nao esta na ficha nem no ' +
  'anuncio: se esta quitado, o valor de entrada, as condicoes de locacao ' +
  '(caucao, renda, restricoes), pet, mobilia, estado, situacao. CHAME SEMPRE ' +
  'antes de escalar_ao_tel: se vier sabe=true, responda com isso e NAO escale. ' +
  'Se vier sabe=false, ai sim escale COM o codigo -- a resposta do Tel fica ' +
  'gravada e serve para o proximo corretor que perguntar o mesmo.',
  'SELECT texto_pronto, sabe, instrucao_para_voce FROM nay_o_que_sei_do_imovel($1,$2);',
  "={{ [$fromAI('codigo', 'o codigo do imovel', 'string') ?? null, " +
  "$fromAI('pergunta', 'o que o corretor quer saber, nas palavras dele', 'string') ?? null] }}",
  [2128, 672]);

ferramenta('guardar_do_imovel', 'tool-guardar-imovel-01',
  'Guarda o que o TEL explicar sobre um imovel -- quitacao, valor de entrada, ' +
  'condicoes de locacao, pet, mobilia, estado, situacao. Chame na MESMA ' +
  'resposta em que ele explicar: se nao chamar, a informacao se perde e voce ' +
  'vai perguntar de novo. So o Tel consegue gravar; se um corretor tentar, a ' +
  'ferramenta recusa e voce NAO diz que guardou.',
  'SELECT nay_guardar_do_imovel($1,$2,$3,$4) AS texto_pronto;',
  "={{ [$fromAI('codigo', 'o codigo do imovel', 'string') ?? null, " +
  "$fromAI('assunto', 'do que se trata: quitacao, entrada, condicoes de locacao, pet, mobilia, estado ou situacao', 'string') ?? null, " +
  "$fromAI('texto', 'o que o Tel explicou, nas palavras dele', 'string') ?? null, " +
  "$('Juntar mensagens').first().json.telefone] }}",
  [2128, 784]);

// ---------- 4. `resumo_do_condominio` para de proibir concluir ----------
const res = wf.nodes.find((x) => x.name === 'resumo_do_condominio');
if (!res) throw new Error('resumo_do_condominio nao encontrado');
if (res.parameters.query.includes('disponibilidade_no_condominio')) {
  console.log('  (ja aplicado) resumo_do_condominio');
} else {
  const de = "'ATENCAO: esta faixa de valor e apenas informativa e NAO serve para concluir se existe ou nao existe imovel. Assim que o corretor informar quartos ou valor, chame obrigatoriamente a ferramenta listar_no_condominio, mesmo que o valor dele pareca estar fora desta faixa - a busca usa uma margem maior. Nunca responda que nao tem sem ter chamado listar_no_condominio.'";
  if (!res.parameters.query.includes(de)) throw new Error('ancora do resumo mudou');
  res.parameters.query = res.parameters.query.replace(de,
    "'ATENCAO: esta faixa de valor e apenas informativa e NAO serve para concluir " +
    "se existe ou nao existe imovel. Assim que o corretor informar quartos ou valor, " +
    "chame listar_no_condominio, mesmo que o valor dele pareca fora desta faixa -- a " +
    "busca usa margem maior. Se a pergunta dele for se TEM ou NAO TEM naquele " +
    "condominio, use disponibilidade_no_condominio, que responde isso de forma final. " +
    "O que voce NAO pode e concluir que nao tem olhando so esta faixa de valor.'");
  console.log('  resumo_do_condominio: deixa de proibir concluir');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
