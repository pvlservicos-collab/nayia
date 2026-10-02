const b = $('Webhook').first().json.body || {};
// O QUE SAI TAMBEM SE GUARDA (31/08). Ate aqui `fromMe` era descartado
// junto com grupo e newsletter, entao NADA do que a Nay responde -- nem
// do que o Tel digita no WhatsApp dela -- ficava gravado: 2.800 linhas em
// `mensagens`, todas 'recebida', zero 'enviada'. O efeito pratico foi eu
// diagnosticar conversa pela metade e propor resposta para corretor que o
// Tel ja tinha atendido.
// A mensagem que sai e gravada com status 'Enviado', e o `Reservar
// mensagens` so pega 'Recebido' -- entao ela entra no historico e o fluxo
// para sozinho, sem responder a si mesma.
if (b.isGroup || b.isNewsletter || b.broadcast || b.isStatusReply) return [];
if (b.type !== 'ReceivedCallback') return [];
const saindo = !!(b.fromMe || b.fromApi);
const legenda = (b.image && b.image.caption) || (b.video && b.video.caption) || (b.document && b.document.caption) || null; const texto = (b.text && b.text.message) ? b.text.message : (legenda || null);
// A CITACAO. O corretor quase nunca manda o codigo: ele responde
// citando o card que saiu no grupo, e o codigo esta la dentro. Ate
// 29/08 isso era jogado fora aqui na entrada, e a Nay recebia
// "Ainda disponivel?" sem imovel nenhum (caso Valois, 29/08).
// A Z-API entrega em `referencedMessage` -- confirmado no historico
// de execucoes do n8n. A forma INTERNA ainda nao foi vista, entao
// tenta os caminhos plausiveis e, se nenhum servir, guarda o que
// veio: o proximo caso se explica sozinho em vez de sumir calado.
// A Z-API NAO manda mensagem citada nesta configuracao: 22 payloads
// capturados em 30/08 e nenhum traz `referencedMessage`. Os campos sao
// isStatusReply chatLid connectedPhone waitingMessage isEdit isGroup
// isNewsletter instanceId messageId phone fromMe momment status chatName
// senderName photo broadcast adContext messageExpirationSeconds forwarded
// type fromApi text. O campo fica aqui defensivamente, para o dia em que
// a Z-API passar a mandar -- mas quem identifica o imovel hoje e o CARD
// COLADO, tratado no `Juntar mensagens`.
// Captura a estrutura de quem RESPONDE MARCANDO. A conclusao anterior
// ("a Z-API nao manda citacao") veio de 22 amostras que eram mensagens
// comuns -- nao havia resposta marcada entre elas, entao a ausencia do
// campo nao provava nada. Agora so grava quando ha sinal de citacao ou
// quando o corpo traz campo desconhecido, para nao encher a tabela.
const camposRaiz = Object.keys(b).filter(k => b[k] !== null && b[k] !== undefined).join(' ');
const CONHECIDOS = new Set(['isStatusReply','chatLid','connectedPhone','waitingMessage',
  'isEdit','isGroup','isNewsletter','instanceId','messageId','phone','fromMe','momment',
  'status','chatName','senderName','photo','broadcast','adContext',
  'messageExpirationSeconds','forwarded','type','fromApi','text','image','audio','video',
  'document','sticker','reaction','reactionBy','notification','participantPhone',
  'participantLid','senderPhoto','isGroupMessage']);
const novos = Object.keys(b).filter(k => !CONHECIDOS.has(k));
const desc = v => v === null || v === undefined ? 'nulo'
  : Array.isArray(v) ? 'lista[' + v.length + ']'
  : typeof v === 'object' ? '{' + Object.keys(v).join(',') + '}'
  : typeof v === 'string' ? 'texto(' + v.length + ')' : typeof v;
const estrutura = novos.length
  ? novos.map(k => k + '=' + desc(b[k])).join(' | ')
  : null;

const ref = b.referencedMessage || null;
// `referenceMessageId` e o nome REAL do campo (visto em payload_estrutura,
// 01/09). So o ID chega, nunca o texto -- entao serve para saber que ELE
// respondeu citando algo, e ela perguntar de qual imovel se trata.
const refId = b.referenceMessageId || (ref && ref.messageId) || null;
let citado = null;
if (ref) {
  if (typeof ref === 'string') citado = ref;
  else citado = (ref.text && ref.text.message) || ref.message || ref.body
             || (ref.image && ref.image.caption)
             || (ref.video && ref.video.caption) || null;
  if (!citado) { try { citado = JSON.stringify(ref).slice(0, 900); } catch (e) { citado = null; } }
}
// TEMPORARIO (31/08): descobrir onde a Z-API poe a URL da imagem, para
// decidir se da para a Nay VER a foto. 12% das mensagens sao imagem (346
// em 30 dias) e hoje ela so diz que nao consegue abrir.
// Guarda apenas NOMES DE CAMPO e tipo, nunca o valor -- mesma disciplina
// da captura de citacao, que respondeu em 22 amostras o que seis palpites
// nao responderam. Apagar assim que o campo estiver conhecido.
let dbgImg = null;
if (b.image || b.video || b.document) {
  const desc = v => v === null || v === undefined ? 'nulo'
    : typeof v === 'object' ? '{' + Object.keys(v).join(',') + '}'
    : typeof v === 'string' ? 'texto(' + v.length + ')' : typeof v;
  dbgImg = ['image','video','document']
    .filter(k => b[k]).map(k => k + '=' + desc(b[k])).join(' | ');
}
let origem = 'texto';
// REACAO e FIGURINHA vem ANTES de imagem: figurinha costuma chegar como
// imagem na Z-API, e cairia em 'imagem' -- fazendo a Nay dizer "nao
// consigo abrir esse arquivo" para um 👍🏼. Foi o que aconteceu com o Moacy
// em 31/08: ele reagiu com joinha na mensagem DELA e recebeu o pedido de
// mandar o codigo do imovel.
if (b.reaction || b.reactionBy || b.isReaction) origem = 'reacao';
else if (b.sticker || (b.image && b.image.isSticker)) origem = 'figurinha';
else if (b.audio) origem = 'audio';
else if (b.image) origem = 'imagem';
else if (b.document) origem = 'documento';
else if (b.video) origem = 'video';
else if (!texto) origem = 'outro';
return [{ json: {
  telefone: String(b.phone || ''),
  nome: b.senderName || b.chatName || null,
  texto: texto,
  origem: origem,
  message_id: b.messageId || null,
  citado: citado,
    citadoId: refId,
  saindo: saindo,
  dbg_img: dbgImg,
  dbg_raiz: camposRaiz,
  dbg_estrutura: estrutura
} }];
