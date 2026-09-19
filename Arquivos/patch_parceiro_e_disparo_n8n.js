// Terceiro patch: os dois achados críticos que sobraram da auditoria.
//
//   1. `imovel_por_codigo` entrega a descrição inteira de imóvel de
//      PARCEIRO, enquanto o card esconde tudo de propósito.
//   2. `imovel_do_disparo` olha os grupos e ignora os cards que a própria
//      Nay mandou em privado -- que é onde mora a resposta.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;

function achar(nome) {
  const n = wf.nodes.find((x) => x.name === nome);
  if (!n) throw new Error('no nao encontrado: ' + nome);
  return n;
}
function trocar(no, campo, de, para, marca, rotulo) {
  const v = no.parameters[campo];
  if (v.includes(marca)) { console.log('  (ja aplicado) ' + rotulo); return; }
  if (!v.includes(de)) throw new Error('ancora mudou em ' + rotulo);
  no.parameters[campo] = v.replace(de, para);
  if (!no.parameters[campo].includes(marca)) throw new Error('marca ausente em ' + rotulo);
  console.log('  ' + rotulo);
}

// ---------- 1. A descricao de PARCEIRO nao sai ----------
// O card de parceiro mostra so o nome do condominio e o aviso de que e
// parceria -- sem bairro, sem valor, sem foto. Mas o ramo da descricao
// ficava FORA desse gate e entregava tudo pela instrucao: endereco, CEP,
// valor, e em 8 casos a posicao financeira do proprietario ("Entrada de
// R$ 170.000,00 | Saldo devedor: R$ 101.000,00"). Sao 469 dos 909
// parceiros com descricao; 122 com valor, 44 com endereco ou CEP.
//
// Falha FECHADA: so libera quando `e_parceiro` prova ser falso.
const tool = achar('imovel_por_codigo');
trocar(tool, 'query',
  `       WHEN COALESCE(i.descricao,'') <> '' THEN`,
  `       -- PARCEIRO NAO TEM DESCRICAO AQUI. O card ja esconde tudo; sem\n` +
  `       -- este gate a instrucao entregava endereco, CEP, valor e ate o\n` +
  `       -- saldo devedor do proprietario. Falha fechada: so passa quando\n` +
  `       -- e_parceiro prova ser falso.\n` +
  `       WHEN COALESCE(i.e_parceiro, true) THEN ''\n` +
  `       WHEN COALESCE(i.descricao,'') <> '' THEN`,
  'COALESCE(i.e_parceiro, true) THEN', 'imovel_por_codigo: descricao de parceiro fechada');

// ---------- 2. O disparo olha a conversa, nao os grupos ----------
// MEDIDO nos 3 casos reais do historico em que o corretor disse "esse"
// sem codigo: nos 3 a lista de cards PRIVADOS continha o imovel certo, e
// a janela de grupo ou nao sabia de nada ou apontou para o errado (o
// 5717 do Gustavo). `envios` tem 11 codigos distintos em privado contra
// 1 em grupo -- a conversa e a fonte, o grupo e ruido.
const disparo = achar('imovel_do_disparo');
disparo.parameters.query =
  'SELECT texto_pronto, NULL::text AS codigo, instrucao_para_voce ' +
  'FROM nay_qual_imovel($1);';
disparo.parameters.options = disparo.parameters.options || {};
disparo.parameters.options.queryReplacement =
  "={{ [$('Juntar mensagens').first().json.telefone] }}";
disparo.parameters.toolDescription =
  "Descobre de qual imovel o corretor fala quando ele diz 'esse', 'esse ai', " +
  "'esse imovel' SEM dar o codigo. Devolve a lista dos imoveis que VOCE mandou " +
  'para ELE, para ele escolher. NUNCA devolve um codigo escolhido: quem escolhe ' +
  'e o corretor. Mostre a lista como veio e espere ele apontar. NAO suponha que ' +
  'e o ultimo imovel que voces conversaram, nem o ultimo postado nos grupos -- ' +
  'sao mais de 3 por dia, e mandar informacao de um imovel como se fosse de ' +
  'outro e o pior erro possivel.';
console.log('  imovel_do_disparo: passa a olhar a conversa, e nunca escolhe');

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
