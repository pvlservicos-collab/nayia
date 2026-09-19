/* Frentes 1 e 2: mata o prompt de reserva dos 3 agentes e enxuga as 18
   descricoes de ferramenta. Le nai_cru.json, escreve nai_patched.json.
   NAO apaga regra: o que sai daqui entra no prompt do banco. */
const fs = require('fs');
const path = require('path');
const AQUI = __dirname;
const NL = String.fromCharCode(10);

const w = JSON.parse(fs.readFileSync(path.join(AQUI, 'nai_cru.json'), 'utf8'));
const f = Array.isArray(w) ? w[0] : w;

// ---------------------------------------------------------------- FRENTE 1
const GUARDA = [
  "={{ (() => {",
  "  const p = $('Abrir turno').first().json?.cab?.prompt;",
  "  if (typeof p === 'string' && p.trim().length > 500) return p;",
  "  throw new Error('PROMPT_VAZIO: nai_prompt do papel nao veio do banco');",
  "})() }}"
].join(NL);

let antesSM = 0, depoisSM = 0, agentes = 0;
f.nodes.filter(n => n.type.indexOf('langchain.agent') >= 0).forEach(n => {
  n.parameters = n.parameters || {};
  n.parameters.options = n.parameters.options || {};
  antesSM += String(n.parameters.options.systemMessage || '').length;
  n.parameters.options.systemMessage = GUARDA;
  depoisSM += GUARDA.length;
  agentes++;
});

// ---------------------------------------------------------------- FRENTE 2
// Forma unica: o que devolve / quando usar / quando NAO usar / argumentos.
// Regra de negocio saiu daqui e foi para o prompt do banco.
const L = (...linhas) => linhas.join(NL);

const D = {
  imovel_por_codigo: L(
    "Devolve o card pronto de um imovel.",
    "Use quando: ele citar um numero de 3 a 5 digitos, ou pedir o card.",
    "Nao use para pergunta pontual de um dado: ai e o_que_sei_do_imovel.",
    "Arg: codigo."),

  resumo_do_condominio: L(
    "Devolve quantos imoveis temos num condominio, separando venda e locacao, com a faixa de valor.",
    "Use quando: ele citar o nome de um condominio.",
    "Arg: nome (como ele escreveu)."),

  listar_no_condominio: L(
    "Devolve a lista de imoveis de um condominio, filtrada.",
    "Use quando: souber o condominio, venda ou locacao, e quartos OU valor.",
    "Arg: condominio, negocio, quartos, teto (o valor como ele falou, sem fazer conta)."),

  buscar_por_perfil: L(
    "Busca imovel de LOCACAO por BAIRRO e faixa de valor, e traz tambem os bairros ao redor.",
    "Use quando: ele pedir por regiao e preco. Chame antes de dizer se tem ou nao tem.",
    "NAO USE se ele citou o nome de um CONDOMINIO: ai e disponibilidade_no_condominio.",
    "Arg: bairro, negocio, teto, quartos, mobilia (as palavras dele)."),

  disponibilidade_no_condominio: L(
    "Diz se temos ou nao imovel num CONDOMINIO, pelo nome dele.",
    "Use SEMPRE que ele citar o nome de um condominio, ou colar um anuncio. Esta vem antes de",
    "buscar_por_perfil: condominio tem nome, bairro nao.",
    "Arg: nome (como ele escreveu), negocio.",
    "Siga a instrucao_para_voce que vier junto."),

  o_que_sei_do_imovel: L(
    "Responde uma pergunta sobre UM imovel: comodos, area, andar, valores, IPTU, endereco, pet,",
    "lazer, e o que o Tel ja explicou dele.",
    "Use quando: ele perguntar um dado. Chame antes de escalar_ao_tel.",
    "Arg: codigo, pergunta (nas palavras dele)."),

  guardar_do_imovel: L(
    "Grava o que o TEL explicar de um imovel.",
    "Use quando: o Tel explicar algo -- na MESMA resposta.",
    "Se quem falou foi corretor, a ferramenta recusa.",
    "Arg: codigo, o_que."),

  imovel_do_disparo: L(
    "Devolve a lista dos imoveis que voce mandou para ele, para ele escolher.",
    "Use quando: ele disser 'esse' sem dar o codigo.",
    "Nunca devolve um codigo escolhido."),

  responder_pendencia: L(
    "Entrega a resposta que o TEL deu a uma pendencia que voce escalou.",
    "Use quando: o Tel responder o que voce perguntou a ele. Nunca para corretor.",
    "Arg: pendencia_id, resposta."),

  escalar_ao_tel: L(
    "Avisa o Tel e passa o chat para ele.",
    "Use quando: nenhuma ferramenta de consulta trouxe a resposta.",
    "Arg: assunto (uma linha)."),

  dados_do_corretor: L(
    "Diz se voce ja tem nome completo, CPF e CRECI dele.",
    "Use quando: antes de pedir esses dados.",
    "Devolve instrucao_para_voce: nunca mostre a ele."),

  pedir_visita: L(
    "Pede a visita e conduz o resto: confere o horario, fala com o proprietario, sobe ao Tel quando precisa.",
    "Use quando: souber QUAL imovel e QUANDO.",
    "Arg: codigo, quando (AAAA-MM-DD HH:MM, Manaus)."),

  guardar_dados_da_visita: L(
    "Grava os dados da visita: do corretor (nome, CPF, CRECI) e do visitante (nome, CPF).",
    "Use quando: ele mandar qualquer um -- na MESMA resposta.",
    "Arg: como ele escreveu; vazio o que nao veio."),

  responder_horario_do_proprietario: L(
    "Registra o que o corretor respondeu sobre o horario que o proprietario sugeriu.",
    "Arg: aceita (sim se topou), outro_quando (AAAA-MM-DD HH:MM)."),

  mudar_horario_da_visita: L(
    "Muda o horario de uma visita ja pedida.",
    "Arg: codigo, quando (AAAA-MM-DD HH:MM)."),

  resultado_da_visita: L(
    "Registra como foi a visita e passa o chat ao Tel.",
    "Arg: resultado = quer_alugar, nao_gostou, pensando ou nao_foi."),

  resposta_do_proprietario: L(
    "Registra a resposta do PROPRIETARIO sobre a visita.",
    "Arg: decisao = aceita, outro_horario, recusa, acesso, cancela ou duvida."),

  resposta_do_motoboy: L(
    "Registra a resposta do FERNANDO sobre uma visita.",
    "Arg: decisao = confirma, nao_pode, problema ou outro.")
};

let antesTD = 0, depoisTD = 0, trocadas = 0;
const naoAchei = [], vistos = new Set();
f.nodes.filter(n => /Tool/i.test(n.type)).forEach(n => {
  const p = (n.parameters = n.parameters || {});
  antesTD += String(p.toolDescription || '').length;
  if (D[n.name] !== undefined) { p.toolDescription = D[n.name]; vistos.add(n.name); trocadas++; }
  else { naoAchei.push(n.name); }
  depoisTD += String(p.toolDescription || '').length;
});
const semNo = Object.keys(D).filter(k => !vistos.has(k));

fs.writeFileSync(path.join(AQUI, 'nai_patched.json'), JSON.stringify(w, null, 2));

console.log('FRENTE 1 -- systemMessage');
console.log('  agentes...........:', agentes);
console.log('  antes / depois....:', antesSM, '->', depoisSM,
  '(' + Math.round(100 - depoisSM / antesSM * 100) + '% menor)');
console.log('');
console.log('FRENTE 2 -- descricoes das ferramentas');
console.log('  trocadas..........:', trocadas);
console.log('  sem no no fluxo...:', semNo.length ? semNo.join(', ') : 'nenhuma');
console.log('  no sem texto......:', naoAchei.length ? naoAchei.join(', ') : 'nenhuma');
console.log('  antes / depois....:', antesTD, '->', depoisTD,
  '(' + Math.round(100 - depoisTD / antesTD * 100) + '% menor)');
const acima = Object.entries(D).filter(([, v]) => v.length > 350);
console.log('  acima de 350......:', acima.length ? acima.map(([k, v]) => k + '=' + v.length).join(', ') : 'nenhuma');
console.log('  maior.............:',
  Object.entries(D).sort((a, b) => b[1].length - a[1].length)[0].map(x => typeof x === 'string' ? x : x.length).join(' = '));
console.log('');
console.log('TOTAL FIXO: ' + (antesSM + antesTD) + ' -> ' + (depoisSM + depoisTD) +
  ' (-' + Math.round(100 - (depoisSM + depoisTD) / (antesSM + antesTD) * 100) + '%)');
