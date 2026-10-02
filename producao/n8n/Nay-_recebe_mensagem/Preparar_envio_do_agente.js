// >>> segundo numero do Tel (28/09)
const TELS_DO_TEL = ['[telefone …7316]', '[telefone …6408]'];
const _finalDoTel = (x) => String(x == null ? '' : x).replace(/\D/g, '').slice(-8);
const _FINAIS_DO_TEL = TELS_DO_TEL.map(_finalDoTel);
const ehTelDoTel = (x) => _FINAIS_DO_TEL.indexOf(_finalDoTel(x)) !== -1;
// <<< segundo numero do Tel
const j = $('Juntar mensagens').first().json;
const tel = j.telefone;

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
const TEL_DO_TEL = TELS_DO_TEL[0];
if (pausado && !ehTelDoTel(tel)) return [];
if (!aprovado) {
  if (!primeiraVez) return [];
  const quem = j.nome ? (j.nome + ' (' + tel + ')') : tel;
  return [
    { json: { rota: 'send-text', pausa: 1, corpo: { phone: tel, message:
      'oi! aqui e a Nay, da Imob Easy. por aqui eu atendo os corretores parceiros. se voce e corretor e quer se cadastrar, me manda seu nome e CRECI que eu passo pro Tel.' } } },
    ...TELS_DO_TEL.map((_t) => ({ json: { rota: 'send-text', pausa: 3, corpo: { phone: _t, message:
      'numero fora do cadastro escreveu: ' + quem + '\n\n"' + String(j.texto || '').slice(0, 300) + '"' } } })),
  ];
}

const texto = String($('Achar codigo na resposta').first().json.texto || '');
const linhas = $input.all().map(i => i.json).filter(x => x && x.url);
const saida = [];

// Agrupa as fotos por imovel para poder mandar CARD, fotos dele, proximo
// card. Quando o corretor pede varios imoveis de uma vez (o Gustavo pediu
// tres em 30/08), jogar os tres textos e depois trinta fotos soltas nao
// diz de quem e cada foto.
const porCodigo = new Map();
for (const l of linhas) {
  const k = String(l.codigo);
  if (!porCodigo.has(k)) porCodigo.set(k, []);
  porCodigo.get(k).push(l.url);
}

// Quebra a resposta dela em blocos, cada um terminando no seu "Codigo:".
const blocos = [];
const re = /C[óo]digo:\s*(\d{3,5})/gi;
let ini = 0, m;
while ((m = re.exec(texto)) !== null) {
  const fim = m.index + m[0].length;
  blocos.push({ codigo: m[1], texto: texto.slice(ini, fim).trim() });
  ini = fim;
}
const resto = texto.slice(ini).trim();

if (blocos.length === 0) {
  // Sem card na resposta: as FOTOS primeiro, a frase depois. O Tel pediu
  // assim em 31/08 -- "ela precisa enviar tudo e depois mandar a mensagem".
  // Com a frase antes, o "prontinho, as fotos seguem ai" aparecia no meio
  // do album e o corretor achava que ja tinha acabado.
  for (const us of porCodigo.values()) for (const u of us) saida.push({ rota: 'send-image', pausa: 3, corpo: { phone: tel, image: u } });
  if (texto.trim()) saida.push({ rota: 'send-text', pausa: 1, corpo: { phone: tel, message: texto.trim() } });
} else {
  for (const b of blocos) {
    if (b.texto) saida.push({ rota: 'send-text', pausa: 1, corpo: { phone: tel, message: b.texto } });
    for (const u of (porCodigo.get(b.codigo) || [])) saida.push({ rota: 'send-image', pausa: 3, corpo: { phone: tel, image: u } });
  }
  // O que ela escreveu depois do ultimo card (pergunta, fechamento) vai por ultimo.
  if (resto) saida.push({ rota: 'send-text', pausa: 1, corpo: { phone: tel, message: resto } });
}
return saida.map(x => ({ json: x }));
