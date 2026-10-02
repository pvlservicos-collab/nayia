// O GPT LE O ARQUIVO, NAO A URL (22/09).
// Mandando a url da Z-API, quem precisa alcancar a foto e a OpenAI --
// e midia de WhatsApp expira e as vezes nem abre de fora. Baixando aqui
// (como o audio ja fazia) e mandando o arquivo, a leitura nao depende de
// ninguem alcancar nada.
//
// O BINARIO NAO ESTA EM `binary.data.data` (medido em 22/09). Este n8n
// guarda arquivo em DISCO: aquele campo vem com a etiqueta
// 'filesystem-v2', e foi exatamente isso que viajou para a OpenAI --
// 'data:image/png;base64,filesystem-v2' --, que respondeu 'you uploaded
// an unsupported image'. Quem traz os bytes e o helper abaixo.
const ent = $('Detectar imagem').first().json;
const OK = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'];
let b64 = '', mime = 'image/jpeg';
try {
  const bin = $input.first().binary || {};
  const chave = bin.data ? 'data' : Object.keys(bin)[0];
  const d = bin[chave] || {};
  if (OK.indexOf(String(d.mimeType || '')) >= 0) { mime = d.mimeType; }
  const buf = await this.helpers.getBinaryDataBuffer(0, chave);
  b64 = buf.toString('base64');
} catch (e) { b64 = ''; }
const corpo = JSON.parse(ent.corpo);
// Sem o arquivo na mao, volta a valer a url: pior ler pela url do que
// nao ler.
if (b64) {
  corpo.messages[0].content[1].image_url.url = 'data:' + mime + ';base64,' + b64;
}
return [{ json: Object.assign({}, ent, { corpo: JSON.stringify(corpo),
                                        veio_arquivo: !!b64,
                                        bytes_lidos: b64.length }) }];
