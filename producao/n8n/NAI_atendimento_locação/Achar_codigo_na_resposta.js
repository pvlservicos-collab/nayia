// >>> telefone na frente (patch 23/09)
const ENVIO_TEL_FRENTE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh)(?:a|ar|e|ei|ou|o)?\b\s*(?:para\s+|pra\s+|pro\s+|p\/\s*)?((?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4})\s+(c[o\u00f3]d(?:igo)?s?\b[\s:=.-]*\d{2,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{2,5})*|(?:o|os|a|as)?\s*\d{3,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{3,5})*)\s*$/i;
const ENVIO_TEL_ANTES = /^\s*(?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4}[\s,;:.-]+(?:@?nay\b[\s,;:.!?-]*)?(?:en+vi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b/i;
const ALTO_PADRAO_GRUPO = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:envi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b(?=[\s\S]*\balto[\s\-]*padr[a\u00e3]o\b)(?=[\s\S]*\b(?:grupo|easy|anunciar)\b)/i;
const EH_ENVIO_TEL = (x) => ENVIO_TEL_FRENTE.test(x) || ENVIO_TEL_ANTES.test(x) || ALTO_PADRAO_GRUPO.test(x);
// <<< telefone na frente
const r = $input.first().json;
const saida = String(r.output || r.text || '');
const j = $('Juntar mensagens').first().json;
const escreveu = String(j.texto || '');
// O que sai daqui como `escreveu` alimenta `nay_deve_mandar_fotos`.
// Tem que ser a fala DELE, nunca o envelope que este fluxo escreveu.
// O fallback existe para o caso de `Juntar mensagens` ser mais antigo
// que este no -- mas o guarda de comando acima continua lendo `escreveu`
// inteiro, senao um `textoCru` vazio abriria a porta que ele fecha.
const cru = String(j.textoCru !== undefined && j.textoCru !== null ? j.textoCru : (j.texto || ''));
const citou = String(j.citado || '');

// A QUARTA copia, a menos obvia: sem ela, "Nay envia as FOTOS do 5750
// pro Sergio" faz `pediuFoto` ler o texto do PROPRIO Tel e `solto`
// colher o 5750 -- as fotos sairiam para o chat dele tambem.
if (/^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)(?:a|ar|e|ei|ou|o)?\b([\s\S]*)(?:\bpara\b|\bpra\b|\bpro\b|\bp\/)\s*([\s\S]+?)\s*$/i.test(escreveu) || EH_ENVIO_TEL(escreveu)) {
  return [{ json: { texto: saida, codigo: '0', codigos: ['0'], escreveu: '' } }];
}

// TODOS os codigos que ela mandou, nao so o primeiro. Em 30/08 o Gustavo
// pediu "me passa as informacoes dos 3" -- ela mandaria os tres cards e so
// as fotos do primeiro sairiam.
const todos = [...saida.matchAll(/C[óo]digo:\s*(\d{3,5})/gi)].map(m => m[1]);

// Quando ela nao repetiu card nenhum, o imovel vem da citacao ou da fala
// dele. Numero colado a ponto ou virgula NAO conta: "valor: 900.000"
// virava codigo 900 (caso Sebastiana, 29/08).
const porRotulo = t => { const m = String(t).match(/C[óo]digo:\s*(\d{3,5})/i); return m ? m[1] : null; };
const solto = t => { const m = String(t).match(/(?<![\d.,])(\d{3,5})(?![\d.,])/); return m ? m[1] : null; };

// `codigosDele` vem de `nay_codigos_citados`, que tira os VALORES antes
// de procurar codigo -- "paga ate 4000" nao e o imovel 4000. O `solto()`
// cru fica so para a citacao, onde nao ha alternativa.
const dele = j.codigosDele || [];
const codigos = todos.length ? [...new Set(todos)]
  : [porRotulo(citou) || j.codigoCitado || porRotulo(escreveu) || dele[0] || solto(citou)].filter(Boolean);


// SEM PEDIDO, SEM IMOVEL (71). Quem manda o card e as fotos e ESTE no,
// por uma regex na resposta dela -- nao o modelo, e nenhuma conferencia
// do fim pergunta "ele pediu isso?". Entao a parede mora aqui.
//
// `pediu_imovel` vem do Jev, pelo `Decidir quem responde`. So barra
// quando a resposta e um NAO explicito: ausente, nulo ou caminho que
// nem passou pelo Jev (codigo solto, cortesia) seguem como hoje.
let pediu = null;
try { pediu = $('Decidir quem responde').first().json.pediu_imovel; } catch (e) { pediu = null; }
if (pediu === false) {
  return [{ json: { texto: saida, codigo: '0', codigos: ['0'], escreveu: cru } }];
}
return [{ json: {
  texto: saida,
  codigo: codigos[0] || '0',
  codigos: codigos.length ? codigos : ['0'],
  escreveu: cru
} }];
