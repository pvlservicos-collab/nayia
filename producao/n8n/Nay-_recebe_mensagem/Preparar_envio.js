// >>> segundo numero do Tel (28/09)
const TELS_DO_TEL = ['[telefone …7316]', '[telefone …6408]'];
const _finalDoTel = (x) => String(x == null ? '' : x).replace(/\D/g, '').slice(-8);
const _FINAIS_DO_TEL = TELS_DO_TEL.map(_finalDoTel);
const ehTelDoTel = (x) => _FINAIS_DO_TEL.indexOf(_finalDoTel(x)) !== -1;
// <<< segundo numero do Tel
const tel = $('Juntar mensagens').first().json.telefone;
// PORTEIRO (29/08), mesma regra do `Preparar envio do agente`: so quem
// esta em `corretores` recebe. Aqui NAO ha cortesia -- um desconhecido
// cujo primeiro contato e um codigo puro ("1234") fica no silencio, e a
// cortesia sai quando ele escrever qualquer texto. Caso raro, e o preco
// de nao duplicar a mensagem nos dois caminhos.
// PORTEIRO, versao que falha FECHADA (30/08). A anterior tinha um buraco:
//   if (!g.aprovado && Number(g.msgs_antes || 0) > 0) return [];
// Se `g` viesse vazio -- referencia falhando, formato inesperado --
// `Number(undefined) > 0` da FALSO e a porta abria. Porteiro que nao sabe
// quem esta na frente tem que dizer nao, nao sim.
let g;
try { g = $('Gravar na fila').first().json || {}; } catch (e) { g = {}; }
const aprovado = g.aprovado === true;
const primeiraVez = g.msgs_antes === 0;   // exatamente zero, nunca "nao sei"
const pausado = g.pausado !== false;      // sem informacao, considera pausado
if (pausado && !ehTelDoTel(tel)) return [];
// Caminho de codigo puro: desconhecido nao recebe nem a cortesia --
// ela sai pelo caminho do agente quando ele escrever texto.
if (!aprovado) return [];
const m = $('Montar mensagem').first().json;
const fotos = $input.all().map(i => i.json.url).filter(Boolean);
const saida = [];
saida.push({ rota: 'send-text', pausa: 1, corpo: { phone: tel, message: m.lead_in } });
saida.push({ rota: 'send-text', pausa: 2, corpo: { phone: tel, message: m.bloco } });
for (const u of fotos) saida.push({ rota: 'send-image', pausa: 6, corpo: { phone: tel, image: u } });
return saida.map(x => ({ json: x }));
