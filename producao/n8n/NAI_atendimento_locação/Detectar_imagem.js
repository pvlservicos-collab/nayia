// 01/10/2026: A NAY NAO LE MAIS IMAGEM (Pedro). Este no para aqui: nao
// baixa a foto e nao chama a OpenAI. NAO marque este no como desativado --
// no n8n o no desativado PASSA o dado adiante, e isso jogaria o item cru
// dentro do "Juntar mensagens". Ver scripts/madrugada/patch_sem_ler_imagem.py.
return [];
// LER IMAGEM E ARQUIVO (Tel, 16/09): "cria um fluxo que le imagem, audio e
// arquivo com a api do gpt". O audio ja era transcrito no ramo ao lado; a
// imagem nao tinha caminho nenhum, e o corretor ouvia "nao consigo abrir a
// imagem".
//
// A Z-API entrega a midia no proprio corpo do webhook -- `image.imageUrl`,
// `document.documentUrl`. Sem url, este ramo nao roda e o fluxo segue como era.
//
// O CORPO DO PEDIDO VAI MONTADO DAQUI (16/09). Escrito como expressao no
// proprio httpRequest, o no devolvia {"error":"invalid syntax"} em 31ms: o
// parser do n8n nao aceita `{{ JSON.stringify({...}) }}` comecando com chave.
// Montado aqui e mandado como string, a mesma chamada leu a foto do 5709.
const w = $('Webhook').first().json.body || {};

// SO LE O QUE CHEGA, NUNCA O QUE SAI (Tel, 16/09 -- corrigindo erro meu do
// mesmo dia). Este ramo lia o webhook direto, sem as exclusoes que o "Filtrar
// e normalizar" faz logo ali do lado. Resultado: cada foto que a PROPRIA NAY
// manda -- e ela manda quatro por card -- era enviada ao GPT para ser
// descrita. Alem do gasto, foi isso que quebrou o "Abrir turno" as 12:41: a
// resposta da OpenAI entrava na lista de mensagens do lote.
//
// As mesmas condicoes do "Filtrar e normalizar", pela mesma razao.
if (w.isGroup || w.isNewsletter || w.broadcast || w.isStatusReply) return [];
if (w.type !== 'ReceivedCallback') return [];
if (w.fromMe || w.fromApi) return [];

const img = w.image || {};
const doc = w.document || {};
const url = img.imageUrl || img.url || '';
const docUrl = doc.documentUrl || doc.url || '';
const mime = String(doc.mimeType || doc.mimetype || '');
// PDF e imagem o GPT le pela url. Planilha, .docx, video e audio nao passam
// por aqui: audio tem o ramo dele, e o resto vai para o Tel.
const docLegivel = docUrl && /pdf|image/i.test(mime);
const alvo = url || (docLegivel ? docUrl : '');
if (!alvo) return [];

const prompt = 'Voce trabalha numa imobiliaria de Manaus. Descreva em portugues, '
  + 'em ate 5 linhas, o que este arquivo mostra. Quando for imovel, diga o que da '
  + 'para ver: comodo, estado, mobilia. Quando for print de conversa, anuncio ou '
  + 'documento, transcreva o texto que aparece. Codigo de imovel, valor e endereco '
  + 'escreva exatamente como aparecem.';

const corpo = JSON.stringify({
  model: 'gpt-4o-mini',
  max_tokens: 400,
  messages: [{ role: 'user', content: [
    { type: 'text', text: prompt },
    { type: 'image_url', image_url: { url: alvo } }
  ]}]
});

return [{ json: {
  midia_url: alvo,
  tipo: url ? 'imagem' : 'arquivo',
  corpo: corpo,
  telefone: w.phone,
  nome: w.senderName
} }];
