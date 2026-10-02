const itens = $input.all().map(i => i.json).filter(m => m && m.id);
if (itens.length === 0) return [];
itens.sort((a, b) => a.id - b.id);
const nomeItem = itens.find(m => m.nome);
const val = (m) => (m.texto && m.texto !== 'null') ? m.texto : '';
let texto = itens.map(val).filter(Boolean).join('\n');
// 'outro' fica de FORA: e o que nao e texto nem arquivo conhecido --
// reacao com emoji, figurinha, enquete. Tratar isso como arquivo fez
// ela dizer ao Moacy "nao consigo abrir esse arquivo" quando ele nao
// tinha mandado arquivo nenhum (31/08, 19:23).
const nt = [...new Set(itens.filter(m => !val(m))
  .map(m => m.origem || 'outro')
  .filter(o => o !== 'outro' && o !== 'reacao' && o !== 'figurinha'))];
// O QUE O CORRETOR FALOU, sem envelope de sistema nenhum. E este que
// vai ao portao de fotos: os envelopes abaixo sao escritos por NOS, e
// um deles tinha a palavra 'fotos' dentro.
let textoCru = texto;
let transcrito = '';
try { const tr = $('Transcrever').all(); if (tr && tr.length) { transcrito = String(tr[0].json.text || tr[0].json.transcription || '').trim(); } } catch (e) { transcrito = ''; }
if (transcrito) {
  textoCru = transcrito;
  texto = '(o corretor mandou um audio. transcricao: "' + transcrito + '") Antes de enviar qualquer material, repita em uma linha o que voce entendeu e peca confirmacao.';
} else if (!texto && nt.length) {
  const nomes = { audio: 'um audio', imagem: 'uma imagem', documento: 'um arquivo', video: 'um video', outro: 'algo que nao e texto' };
  const lista = nt.map(o => nomes[o] || nomes.outro).join(' e ');
  texto = '(informacao de sistema, nao repita isso literalmente) o corretor enviou ' + lista + ' e nenhum texto junto. Voce nao consegue abrir nem ouvir esse tipo de arquivo. Responda em uma linha, no seu tom, dizendo que nao consegue abrir ' + lista + ' e pedindo para ele escrever a mensagem ou mandar o codigo do imovel. Nunca finja que viu ou ouviu o conteudo.';
}
// A citacao vai SEPARADA do texto, nunca colada nele. Se fosse
// colada, o card dela citado de volta -- que termina em "quer que
// eu mande as fotos?" -- dispararia envio de foto sem ninguem ter
// pedido. A citacao serve para achar o IMOVEL, o pedido se le so
// no que o corretor escreveu.
const citado = (itens.map(m => m.citado).filter(Boolean)[0]) || null;
// O CARD COLADO. Levantado em 30/08 capturando a estrutura do payload:
// a Z-API NAO manda mensagem citada (nao existe `referencedMessage` nos
// 22 payloads observados). O que o corretor faz de verdade e COLAR ou
// ENCAMINHAR o card do grupo para dizer de qual imovel fala -- o texto
// chega inteiro, entao nunca houve dado faltando.
// O defeito era outro: ela lia o card, buscava o codigo e devolvia o
// MESMO card de volta. A Samira mandou o 2943 e recebeu o 2943.
const mCard = texto.match(/C[óo]digo:\s*(\d{3,5})/i);
if (mCard && /[📍•]/.test(texto)) {
  texto = '(informacao de sistema, nao repita isso ao corretor) ele COLOU o card do imovel '
        + mCard[1] + ' para dizer de qual imovel esta falando. NAO mande esse card de volta, '
        + 'ele acabou de mandar. Siga de onde a conversa estava, tratando o ' + mCard[1]
        + ' como o imovel escolhido. Mensagem dele: ' + texto;
}
// OR entre as mensagens do lote: se o corretor mandou duas linhas e a
// pergunta da unidade esta na segunda, a parede tem que valer igual.
const pedeUnidade = itens.some(m => m.pede_unidade === true);
// Visita pedida em QUALQUER mensagem do lote vale para o turno todo.
const pedeVisita = itens.some(m => m.pede_visita === true);
// O aviso e o mesmo para todas as mensagens do lote (depende do
// telefone, nao do texto): basta o primeiro que veio preenchido.
const focoAviso = (itens.map(m => m.foco_aviso).filter(Boolean)[0]) || null;
// Pedido de foto em QUALQUER mensagem do lote vale para o turno todo --
// e o portao de envio le o texto junto, entao tem que ser OR aqui.
const vaoSairFotos = itens.some(m => m.manda_fotos === true);
// E os negocios se SOMAM: 'locacao' numa linha e 'venda' na outra e o
// caso que quebrou -- ela mandou so os de venda.
const negs = new Set();
for (const m of itens) {
  const x = m.negocio_pedido;
  if (x === 'ambos') { negs.add('venda'); negs.add('locacao'); }
  else if (x) negs.add(x);
}
const negocioPedido = negs.size > 1 ? 'ambos' : (negs.values().next().value || null);
// Ele respondeu citando alguma mensagem? So o ID chega, nunca o texto.
// `citado_id` (snake) e o nome que vem do RETURNING do Postgres.
const citadoId = (itens.map(m => m.citado_id).filter(Boolean)[0]) || null;
// O imovel da mensagem que ele marcou, quando a gente consegue casar.
const codigoCitado = (itens.map(m => m.codigo_citado).filter(Boolean)[0]) || null;
// Uniao dos codigos que ele escreveu, sem os valores.
const codigosDele = [...new Set(itens.flatMap(m => m.codigos_citados || []))];
return [{ json: { perguntaAberta: itens.some(m => m.pergunta_aberta === true), pedeUnidade: pedeUnidade, citadoId: citadoId, codigoCitado: codigoCitado, codigosDele: codigosDele, telefone: itens[0].telefone, nome: nomeItem ? nomeItem.nome : null, pedeVisita: pedeVisita, focoAviso: focoAviso, vaoSairFotos: vaoSairFotos, negocioPedido: negocioPedido, opcoesCitacao: (itens.map(m => m.opcoes_citacao).filter(Boolean)[0]) || null, nomePessoa: (itens.map(m => m.nome_pessoa).filter(Boolean)[0]) || null, texto: texto, textoCru: textoCru, citado: citado, naoTexto: nt, ids: itens.map(m => m.id), qtd: itens.length } }];
