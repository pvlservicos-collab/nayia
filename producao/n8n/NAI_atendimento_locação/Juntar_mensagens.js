// SO MENSAGEM ENTRA AQUI (Tel, 16/09, corrigindo erro meu do mesmo dia).
// O no "Ler imagem (GPT)" tambem desagua neste, e a resposta da OpenAI traz um
// campo `id` que e texto -- "chatcmpl-EOm3J...". O filtro antigo so olhava se
// havia `id`, entao essa resposta entrava na lista como se fosse mensagem, e o
// "Abrir turno" quebrava com `invalid input syntax for type bigint`.
// Id de mensagem e sempre numero: e isso que este filtro exige agora.
// AS MENSAGENS VEM SEMPRE DE "Reservar mensagens" (Tel, 16/09). Pelo $input,
// na segunda passada chegava so a resposta da OpenAI e a lista ficava vazia.
let bruto;
try { bruto = $('Reservar mensagens').all().map(i => i.json); }
catch (e) { bruto = $input.all().map(i => i.json); }
const itens = bruto
  .filter(m => m && m.id !== undefined && m.id !== null && /^[0-9]+$/.test(String(m.id)));
if (itens.length === 0) return [];

// ESPERAR O RAMO DA MIDIA. Se ha audio ou imagem no lote e a leitura ainda nao
// terminou, esta passada nao produz nada: quem abre o turno e a passada
// seguinte, ja com o texto do audio ou da imagem na mao. Sem isto o turno
// nascia vazio e a porta decidia "assunto que nao e de corretor".
//
// So espera o que REALMENTE vem: se "Detectar audio"/"Detectar imagem" rodou e
// nao devolveu item (midia sem url, mensagem que saiu daqui), nao ha nada que
// esperar e a mensagem segue. E os nos do ramo tem onError, entao ate a falha
// da API devolve o controle para ca.
function rodou(no) {
  try { const r = $(no).all(); return { sim: true, itens: (r || []).length }; }
  catch (e) { return { sim: false, itens: 0 }; }
}
// QUEM DECIDE SE HA LEITURA A ESPERAR E O WEBHOOK, nao os nos detectores
// (corrigindo erro meu de 16/09 13:16). Na PRIMEIRA passada os detectores
// ainda nao rodaram, entao perguntar a eles devolvia "nao ha nada vindo" e a
// espera nunca acontecia -- o mesmo audio abria dois turnos.
//
// O corpo do webhook esta disponivel desde o inicio e diz, sozinho, se vai
// haver transcricao ou leitura: e a mesma condicao que "Detectar audio" e
// "Detectar imagem" usam para decidir se produzem item.
const w = $('Webhook').first().json.body || {};
const midiaDaqui = !!(w.fromMe || w.fromApi || w.isGroup || w.isNewsletter
                      || w.broadcast || w.isStatusReply || w.type !== 'ReceivedCallback');
const urlAudio = (w.audio && w.audio.audioUrl) || '';
const urlImg   = (w.image && (w.image.imageUrl || w.image.url)) || '';
const urlDoc   = (w.document && (w.document.documentUrl || w.document.url)) || '';
const mimeDoc  = String((w.document && (w.document.mimeType || w.document.mimetype)) || '');
const vaiTranscrever = !midiaDaqui && !!urlAudio;
// 01/10/2026: NAO LEMOS MAIS IMAGEM (Pedro), entao nao ha leitura a esperar.
// Deixar `true` aqui com o ramo desligado faria o turno nunca abrir para quem
// manda foto: a Nay ficaria muda com toda imagem.
const vaiLerImagem   = false;
// O CRITERIO E TER ITEM, NAO "TER RODADO" (corrigindo erro meu de 16/09 13:05).
// `$('No').all()` NAO lança quando o no ainda nao executou: devolve vazio. Com
// `.sim` a espera nunca acontecia, as duas passadas produziam saida e o mesmo
// arquivo abria DOIS turnos -- foi o que aconteceu com o Sr. Leonardo, turnos
// 8391 e 8392 para a mensagem 14015.
//
// Zero itens quer dizer "ainda nao veio". Se a leitura falhar, o no tem
// onError e devolve um item com o erro dentro -- entao a espera termina e a
// mensagem segue para o Tel, sem travar.
// Espera a leitura que o webhook prometeu. Zero itens = ainda nao veio; os
// nos do ramo tem onError, entao ate a falha devolve item e a espera termina.
if (vaiTranscrever && rodou('Transcrever').itens === 0) return [];
if (vaiLerImagem   && rodou('Ler imagem (GPT)').itens === 0) return [];
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
// A LEITURA DA IMAGEM (Tel, 16/09), no mesmo molde da transcricao do audio.
// O no roda com onError, entao aqui pode chegar tanto a resposta do GPT quanto
// um erro: so vale o que tiver texto de verdade dentro.
let lidoNaImagem = '';
let tipoDaMidia = 'imagem';
try {
  const im = $('Ler imagem (GPT)').all();
  if (im && im.length) {
    const j = im[0].json || {};
    const ch = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || '';
    lidoNaImagem = String(ch || '').trim();
  }
} catch (e) { lidoNaImagem = ''; }
try {
  const dt = $('Detectar imagem').all();
  if (dt && dt.length) { tipoDaMidia = String((dt[0].json || {}).tipo || 'imagem'); }
} catch (e) { tipoDaMidia = 'imagem'; }
if (transcrito) {
  textoCru = transcrito;
  texto = '(o corretor mandou um audio. transcricao: "' + transcrito + '") '
        + 'Atenda o que ele pediu nesta resposta, sem esperar confirmacao. Diga numa linha '
        + 'curta o que voce entendeu e ja entregue junto -- por exemplo "Entendi que o Sr. '
        + 'quer as fotos do Acquarelle, ja te mando!". Transcricao erra nome de condominio: '
        + 'quando o imovel que voce entendeu nao for o da conversa, confirme qual e antes de '
        + 'mandar material daquele imovel.';
} else if (lidoNaImagem) {
  // A IMAGEM FOI LIDA (Tel, 16/09). Vale como se ele tivesse escrito: o
  // corretor que manda o print do anuncio ou a foto do imovel esta dizendo de
  // qual imovel fala, e agora ela enxerga isso.
  //
  // A LEGENDA VEM NA FRENTE. Foto com legenda e o caso comum -- "esse ainda
  // esta disponivel?" com o print junto -- e a pergunta dele nao pode ser
  // trocada pela descricao da foto. `textoCru`, que e o que vai ao portao de
  // fotos, continua sendo o que ELE escreveu quando ele escreveu algo.
  const dele = String(texto || '').trim();
  if (!dele) { textoCru = lidoNaImagem; }
  texto = (dele ? dele + '\n' : '')
        + '(informacao de sistema, nao repita isso literalmente) ele mandou '
        + (tipoDaMidia === 'arquivo' ? 'um arquivo' : 'uma imagem')
        + ' e voce leu. Conteudo: "' + lidoNaImagem + '". '
        + (dele ? 'Responda a mensagem dele acima usando isto. '
                : 'Responda o que ele quer a partir disso. ')
        + 'Fale no seu tom, sem dizer que leu nem descrever a imagem de volta.';
} else if (!texto && nt.length) {
  // A MIDIA VAI PARA O TEL (Tel, 16/09): "ela NUNCA deve falar que nao le
  // imagem; se nao conseguir, manda a imagem ao Tel".
  //
  // Aqui estava a origem da frase. Este trecho MANDAVA ela dizer que nao
  // consegue abrir -- e foi o que o Sr. Ribamar ouviu as 05:32, depois de
  // mandar treze fotos, e o proprio Tel as 05:30. Nao adiantava proibir a
  // frase no prompt: a ordem chegava dentro do texto do turno.
  //
  // Este ramo so roda quando a leitura acima falhou (API fora do ar, arquivo
  // que o GPT nao abre). Entao ela cala e o Tel ve a midia no WhatsApp dele.
  const nomes = { audio: 'um audio', imagem: 'uma imagem', documento: 'um arquivo', video: 'um video', outro: 'algo que nao e texto' };
  const lista = nt.map(o => nomes[o] || nomes.outro).join(' e ');
  texto = '(informacao de sistema, nao repita isso literalmente) ele enviou ' + lista
        + ' e nenhum texto junto, e voce nao conseguiu abrir. Chame escalar_ao_tel '
        + 'NESTA resposta e mande o texto_pronto que ela devolver, exatamente como veio: '
        + 'e uma linha curta avisando que recebeu, para ele nao ficar sem resposta. '
        + 'Depois dela o Tel assume. A frase "nao consigo abrir" nao vai para ele em '
        + 'forma nenhuma.';
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
return [{ json: { pedeUnidade: pedeUnidade, citadoId: citadoId, codigoCitado: codigoCitado, codigosDele: codigosDele, telefone: itens[0].telefone, nome: nomeItem ? nomeItem.nome : null, pedeVisita: pedeVisita, focoAviso: focoAviso, vaoSairFotos: vaoSairFotos, negocioPedido: negocioPedido, opcoesCitacao: (itens.map(m => m.opcoes_citacao).filter(Boolean)[0]) || null, nomePessoa: (itens.map(m => m.nome_pessoa).filter(Boolean)[0]) || null, texto: texto, textoCru: textoCru, citado: citado, naoTexto: nt, ids: itens.map(m => m.id), qtd: itens.length } }];
