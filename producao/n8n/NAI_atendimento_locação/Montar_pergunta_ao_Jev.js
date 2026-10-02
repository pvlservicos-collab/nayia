// O ESTADO E O QUE O JEV LE (77). Ele nao le imagem nem banco: le isto.
// A descricao que o GPT fez da foto e a transcricao do audio entram aqui.
//
// A MUDANCA: antes iam quatro campos (mensagem, quem fala, leitura da
// imagem, imovel em foco). Agora vai o estado inteiro -- inclusive a
// ULTIMA FALA DELA e os imoveis JA MOSTRADOS e RECUSADOS. Sem isso,
// "esse nao" e "pode ser" nao tem contra o que ser interpretados.
const base = $json;
const j = $('Juntar mensagens').first().json || {};
const cab = $('Abrir turno').first().json.cab || {};
const texto = String(j.texto || cab.texto || '').slice(0, 1500);

let est = {};
try { est = $('Ler estado').first().json.estado || {}; } catch (e) { est = {}; }

let leitura = '';
try {
  const im = $('Ler imagem (GPT)').all();
  if (im && im.length) {
    const c = ((im[0].json || {}).choices || [])[0];
    leitura = String(((c || {}).message || {}).content || '').trim();
  }
} catch (e) { leitura = ''; }

const estado = {
  mensagem: texto || '(sem texto)',
  quem_fala: est.papel || 'corretor',
  nome: est.nome || '',
  leitura_das_imagens: leitura || '',
  imovel_em_foco: est.codigo_foco ? String(est.codigo_foco) : '',
  imoveis_ja_mostrados: (est.codigos_mostrados || []).join(', '),
  imoveis_que_ele_recusou: (est.codigos_rejeitados || []).join(', '),
  ultima_coisa_que_a_nay_disse: String(est.ultima_fala_dela || '').slice(0, 500),
  tem_visita_pendente: est.visita_pendente ? 'sim' : 'nao',
  ultimas_trocas: (est.ultimas_trocas || []).map(function (t) {
    return 'ele: ' + String(t.ele || '').slice(0,160) + ' | ela: ' + String(t.ela || '').slice(0,160);
  }).join(' // '),
};

// OS CANDIDATOS. O Jev ESCOLHE entre opcoes -- ele nao extrai texto.
// Pedir "qual codigo ele quer" em texto livre devolveria numero
// inventado; oferecer 5727 / 5718 / nenhum devolve escolha com
// probabilidade. Teto de 8: lista longa piora a escolha.
const cands = [];
function poe(v) {
  const s = String(v || '').replace(/\D/g, '');
  if (s.length >= 3 && s.length <= 5 && cands.indexOf(s) < 0) cands.push(s);
}
poe(est.codigo_foco);
(j.codigosDele || []).forEach(poe);
(est.codigos_mostrados || []).forEach(poe);
const candidatos = cands.slice(0, 8);

function escolhasDeCodigo(comOutro) {
  const o = {};
  candidatos.forEach(function (c) { o[c] = 'E o imovel de codigo ' + c + '.'; });
  o.nenhum = 'Nenhum imovel especifico nesta mensagem.';
  if (comOutro) o.outro_nao_listado = 'Um imovel que nao esta nesta lista.';
  return o;
}

const perguntas = {
  intencao: {
    type: 'choice',
    instructions: 'O que ele quer NESTA mensagem? Leia junto com a ultima coisa que a Nay disse.',
    criteria: {"pedir_imovel":"Ele quer RECEBER imovel: pede card, fotos, opcoes, valores, ou descreve o que o cliente dele procura para a gente mandar.","rejeitar_imovel":"Ele esta RECUSANDO um imovel que ja mostramos: nao gostou, o cliente nao gostou, nao serve, quer outro no lugar.","pergunta_sobre_imovel":"Ele pergunta um DADO de um imovel que ja esta na conversa: valor, quartos, area, andar, condominio, disponibilidade, documentacao.","visita":"Ele quer marcar, remarcar, confirmar ou cancelar uma visita.","resultado_visita":"Ele esta contando COMO FOI uma visita que ja aconteceu, ou o que o cliente achou depois de ver.","cortesia":"So cumprimento, agradecimento ou confirmacao curta, sem assunto novo: oi, bom dia, ok, obrigado, blz.","oferta_de_imovel":"Ele esta OFERECENDO um imovel DELE para a imobiliaria, ou perguntando como anunciar com a gente.","assunto_geral":"Nao e sobre imovel do nosso catalogo: recado, duvida sobre a imobiliaria, parceria, comissao, grupo, reclamacao, assunto pessoal."}
  },
  codigo_quer: {
    type: 'choice',
    instructions: 'Qual imovel ele quer receber ou saber nesta mensagem?',
    criteria: escolhasDeCodigo(true),
  },
  codigo_rejeita: {
    type: 'choice',
    instructions: 'Qual imovel ele esta RECUSANDO nesta mensagem? So quando ele diz que nao serve ou nao gostou.',
    criteria: escolhasDeCodigo(false),
  },
  oferta: {
    type: 'noul',
    instructions: 'A pessoa esta oferecendo um imovel DELA para a imobiliaria?',
    criteria: { true: 'Diz que tem um imovel e quer enviar, cadastrar ou anunciar com a gente.', false: 'Esta perguntando sobre imovel nosso, ou falando de outra coisa.' },
  },
  cortesia: {
    type: 'noul',
    instructions: 'A mensagem e apenas cortesia, sem assunto novo?',
    criteria: { true: 'So agradecimento, confirmacao ou saudacao: ok, obrigado, bom dia, blz.', false: 'Tem pergunta, pedido ou informacao nova.' },
  },
  o_que_mandou: {
    type: 'choice',
    instructions: 'O que a pessoa mandou nas imagens ou arquivos?',
    criteria: { anuncio_dele: 'Fotos ou print de um imovel DELE, que ele quer oferecer.', documento: 'Documento, contrato, comprovante, ficha, print de conversa.', duvida_sobre_nosso: 'Foto de um imovel NOSSO, perguntando algo sobre ele.', nao_da_para_saber: 'Nao veio imagem, ou nao da para dizer pelo que veio.' },
  },
};

const corpo = JSON.stringify({
  model: 'typesafe/jev-1.13',
  state: estado,
  questions: perguntas,
});
return [{ json: Object.assign({}, base, { corpo, texto_lido: texto, candidatos: candidatos }) }];
