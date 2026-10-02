// >>> telefone na frente (patch 23/09)
const ENVIO_TEL_FRENTE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh)(?:a|ar|e|ei|ou|o)?\b\s*(?:para\s+|pra\s+|pro\s+|p\/\s*)?((?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4})\s+(c[o\u00f3]d(?:igo)?s?\b[\s:=.-]*\d{2,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{2,5})*|(?:o|os|a|as)?\s*\d{3,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{3,5})*)\s*$/i;
const ENVIO_TEL_ANTES = /^\s*(?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4}[\s,;:.-]+(?:@?nay\b[\s,;:.!?-]*)?(?:en+vi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b/i;
const ALTO_PADRAO_GRUPO = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:envi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b(?=[\s\S]*\balto[\s\-]*padr[a\u00e3]o\b)(?=[\s\S]*\b(?:grupo|easy|anunciar)\b)/i;
const EH_ENVIO_TEL = (x) => ENVIO_TEL_FRENTE.test(x) || ENVIO_TEL_ANTES.test(x) || ALTO_PADRAO_GRUPO.test(x);
// <<< telefone na frente
// LIDO de `regex_liberar.js` pelo patch -- nao editar aqui.
const TAXA_CODIGO = /^(\d{3,5})\s*[-–—:,]?\s*([^\d]{2,40})$/;
const FALA_DE_TAXA = /\b(tx|taxa|condominio|condomínio|cond)\b/i;
const FALA_DE_INCLUSAO = /\b(inclus[ao]|inclu[íi]d[ao]|inclui)\b/i;
const NEGA = /\b(nao|não|sem)\b/i;

function ehComandoDeTaxa(texto) {
  const m = TAXA_CODIGO.exec(String(texto || ''));
  if (!m) return false;
  const resto = m[2];
  if (!FALA_DE_TAXA.test(resto)) return false;
  return FALA_DE_INCLUSAO.test(resto) || NEGA.test(resto);
}

const VOC = '(?:@?nay\\b[\\s,;:.!?-]*)?';

const V_DESCARTA =
  '(?:descarta|descartar|descarte|esquece|esquecer|esqueca|esqueça|' +
  'apaga|apagar|cancela|cancelar|ignora|ignorar)';

const V_RESPOSTA = '(?:resposta|responde|responder)';

const LIGACAO = '(?:\\s+a)?(?:\\s+pend[eê]ncias?)?';

const RE_RESPOSTA = new RegExp(
  '^\\s*' + VOC + V_RESPOSTA + LIGACAO + '\\s+(\\d{1,6})\\s+([\\s\\S]+?)\\s*$', 'i');

const RE_DESCARTA = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + LIGACAO + '\\s+(\\d{1,6})\\s*$', 'i');

const RE_DESCARTA_TUDO = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + '\\s+tudo\\s*$', 'i');

const RE_DESCARTA_TUDO_SIM = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + '\\s+tudo\\s+sim\\s*$', 'i');

const RE_LISTAR = new RegExp(
  '^\\s*' + VOC + '(?:pend[eê]ncias?|pendentes)\\s*$', 'i');

function ehComandoDePendencia(t) {
  const s = String(t || '');
  return RE_DESCARTA_TUDO_SIM.test(s) || RE_DESCARTA_TUDO.test(s) ||
         RE_DESCARTA.test(s) || RE_RESPOSTA.test(s) || RE_LISTAR.test(s);
}

function interpretarPendencia(t) {
  const s = String(t || '');
  let m;
  if (RE_DESCARTA_TUDO_SIM.test(s)) return { acao: 'DESCARTAR TUDO SIM', p_id: null, p_texto: null };
  if (RE_DESCARTA_TUDO.test(s)) return { acao: 'DESCARTAR TUDO', p_id: null, p_texto: null };
  m = s.match(RE_RESPOSTA);
  if (m) return { acao: 'RESPOSTA', p_id: parseInt(m[1], 10), p_texto: m[2].trim() };
  m = s.match(RE_DESCARTA);
  if (m) return { acao: 'DESCARTAR', p_id: parseInt(m[1], 10), p_texto: null };
  if (RE_LISTAR.test(s)) return { acao: 'PENDENCIAS', p_id: null, p_texto: null };
  return null;
}


// ===== NAI: o caminho sai do CABECALHO (Abrir turno), nunca do texto solto.
function ehComandoAntigo(t) {
  return ehComandoDePendencia(t)
    || EH_ENVIO_TEL(t)
    || /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)(?:a|ar|e|ei|ou|o)?\b([\s\S]*)(?:\bpara\b|\bpra\b|\bpro\b|\bp\/)\s*([\s\S]+?)\s*$/i.test(t)
    || /^(@?NAY\b[\s,:;.!\-]*)?((POSTA|POSTAR|PUBLICA|PUBLICAR|DISPARA|DISPARAR|SOLTA|TIRA|TIRAR|REMOVE|REMOVER|RETIRA|RETIRAR|VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA|VAGAS|VAGA|LISTA)\b|(MANDA|MANDAR|MANDE|ENVIA|ENVIAR|ENVIE)\s+(AS?\s+|OS?\s+)?(LISTA|APARTAMENTOS?|APTOS?|COBERTURAS?|FLATS?|CASAS?|SOBRADOS?|SALAS?|LOJAS?|LOTES?|TERRENOS?)\b)/i.test(t)
    || /^(?:@?NAY\b[\s,:;.!\-]*)?(\d{3,5})\s*[-–—:,]?\s*(?:JA|JÁ)?\s*(VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA)\b/i.test(t)
    || ehComandoDeTaxa(t);
}
const j = $('Juntar mensagens').first().json;
let cab = {};
try { cab = $('Abrir turno').first().json.cab || {}; } catch (e) { cab = {}; }
if (cab.ok !== true) return [];                       // sem cabecalho, nada sai
const papel = cab.papel;
const t = String(cab.texto || '').trim();
const envelope = String(j.texto || '').trim();
if (papel === 'tel') {
  // Comando da NAI (VISITAS, VISITA N, ACESSO, ASSUMIR, DEVOLVER e, desde
  // 15/09, AGENDA DE VISITAS). Quem decide e o banco, em `cab.comando_nai`;
  // a regex abaixo fica como reserva para cabecalho antigo.
  if (cab.comando_nai === true) return [{ json: { rota: 'tel_nai' } }];
  if (/^\s*(@?nay[\s,:;.!-]*)?(visitas\s*$|visita\s+#?\d+\s+\S|acesso\s+\d{3,5}\s+\S|(assumir|devolver)\s+\S)/i.test(t)) return [{ json: { rota: 'tel_nai' } }];
  if (ehComandoAntigo(t)) return [{ json: { rota: cab.teste === true ? 'aviso_teste' : 'tel_antigo' } }];
  return envelope ? [{ json: { rota: 'agente' } }] : [];
}
if (cab.pausado !== false) return [];                  // pausada (ou sem saber): silencio
if (papel === 'proprietario') return t ? [{ json: { rota: 'proprietario' } }] : [];
if (papel === 'motoboy') return t ? [{ json: { rota: 'motoboy' } }] : [];
// corretor -- o porteiro, que falha FECHADO
// A PORTA primeiro (Tel, 15/09): com a regra publica ligada, quem decide e
// `nai_deve_atender`, no banco. false = silencio; true = atende mesmo sem
// estar em `corretores` (gente nova que chega do grupo perguntando de
// imovel). Indefinido = regra desligada, e vale o porteiro de sempre.
if (cab.atende === false) return [];
if (cab.atende !== true && cab.aprovado !== true) return cab.primeira_vez === true ? [{ json: { rota: 'cortesia' } }] : [];
// NUMERO SOLTO: so e codigo de imovel quando ela NAO acabou de perguntar o
// valor. Em 13/09 ela perguntou a faixa de preco, ele respondeu "3500" e
// levou "nao achei nenhum imovel com o codigo 3500".
if (/^\d{3,5}$/.test(t) && cab.esperando_valor !== true) return [{ json: { rota: 'codigo', codigo: parseInt(t, 10) } }];
if (!envelope) return [];
return [{ json: { rota: 'agente' } }];
