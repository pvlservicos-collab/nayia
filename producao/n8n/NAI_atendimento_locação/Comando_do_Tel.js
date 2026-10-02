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

// NAI: o papel vem do CABECALHO. Publicador (posta, dispara...) so fora do teste.
let cab = {};
try { cab = $('Abrir turno').first().json.cab || {}; } catch (e) { cab = {}; }
if (cab.papel !== 'tel' || cab.teste === true) return [];
const TEL = String(cab.telefone);
// >>> telefone na frente (patch 23/09)
const ENVIO_TEL_FRENTE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh)(?:a|ar|e|ei|ou|o)?\b\s*(?:para\s+|pra\s+|pro\s+|p\/\s*)?((?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4})\s+(c[o\u00f3]d(?:igo)?s?\b[\s:=.-]*\d{2,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{2,5})*|(?:o|os|a|as)?\s*\d{3,5}(?:[\s,;]+(?:e\s+)?(?:o|os)?\s*\d{3,5})*)\s*$/i;
const ENVIO_TEL_ANTES = /^\s*(?:55[\s.-]*)?\(?\d{2}\)?[\s.-]*\d{4,5}[\s.-]*\d{4}[\s,;:.-]+(?:@?nay\b[\s,;:.!?-]*)?(?:en+vi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b/i;
const ALTO_PADRAO_GRUPO = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:envi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\b(?=[\s\S]*\balto[\s\-]*padr[a\u00e3]o\b)(?=[\s\S]*\b(?:grupo|easy|anunciar)\b)/i;
const EH_ENVIO_TEL = (x) => ENVIO_TEL_FRENTE.test(x) || ENVIO_TEL_ANTES.test(x) || ALTO_PADRAO_GRUPO.test(x);
// <<< telefone na frente
const linhas = String(cab.texto || '').split('\n');
for (const bruta of linhas) {
  const linha = bruta.trim();
  if (!linha) continue;
  const up = linha.toUpperCase();
  // A gramatica de pendencia mora em regex_pendencia.js, com 45 casos
  // em casos_comando_pendencia.json. 'descarta 47' e 'esquece 47' sao
  // formas que o Tel usa de verdade.
  const pend = interpretarPendencia(linha);
  if (pend) return [{ json: { acao: pend.acao, p_id: pend.p_id, p_texto: pend.p_texto, tel_tel: TEL } }];
  if (up === 'PENDENCIAS' || up === 'PEND\u00caNCIAS') return [{ json: { acao: 'PENDENCIAS', p_id: null, p_texto: null, tel_tel: TEL } }];
  // ENVIO PRIVADO (31/08): mesma regex do interpretar_comando.py. Vem
  // ANTES dos verbos antigos porque "posta o 5750 pro Sergio" precisa
  // chegar ao Python para ser RECUSADO, em vez de virar postagem em 14
  // grupos. Timeout maior: um envio com fotos leva mais que 8s.
  const ENVIO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)(?:a|ar|e|ei|ou|o)?\b([\s\S]*)(?:\bpara\b|\bpra\b|\bpro\b|\bp\/)\s*([\s\S]+?)\s*$/i;
  const NAO_PESSOA_RE = /\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores)\b/i;
  const mEnv = linha.match(ENVIO_RE);
  const mTelFrente = EH_ENVIO_TEL(linha);
  if (mTelFrente || (mEnv && !NAO_PESSOA_RE.test(mEnv[3]))) {
    try {
      await this.helpers.httpRequest({
        method: 'POST', url: 'http://172.16.0.1:8080/comando',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
        body: { texto: linha }, json: true, timeout: 120000
      });
    } catch (e) {}
    return [];
  }
  if (/^(@?NAY\b[\s,:;.!\-]*)?((POSTA|POSTAR|PUBLICA|PUBLICAR|DISPARA|DISPARAR|SOLTA|TIRA|TIRAR|REMOVE|REMOVER|RETIRA|RETIRAR|VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA|VAGAS|VAGA|LISTA)\b|(MANDA|MANDAR|MANDE|ENVIA|ENVIAR|ENVIE)\s+(AS?\s+|OS?\s+)?(LISTA|APARTAMENTOS?|APTOS?|COBERTURAS?|FLATS?|CASAS?|SOBRADOS?|SALAS?|LOJAS?|LOTES?|TERRENOS?)\b)/i.test(up)
      // "5712 Alugado" -- o codigo na frente (Tel, 09/09). Mesmo literal
      // de `regex_liberar.js`, exercitado por `casos_comando_liberar.json`.
      || /^(?:@?NAY\b[\s,:;.!\-]*)?(\d{3,5})\s*[-–—:,]?\s*(?:JA|JÁ)?\s*(VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA)\b/i.test(up)
      || ehComandoDeTaxa(up)
      // "5712 Alugado" -- o codigo na frente (Tel, 09/09). Mesmo literal
      // de `regex_liberar.js`, exercitado por `casos_comando_liberar.json`.
      || /^(?:@?NAY\b[\s,:;.!\-]*)?(\d{3,5})\s*[-–—:,]?\s*(?:JA|JÁ)?\s*(VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA)\b/i.test(up)) {
    try {
      await this.helpers.httpRequest({
        method: 'POST',
        url: 'http://172.16.0.1:8080/comando',
        headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer <REDIGIDO>' },
        body: { texto: linha },
        json: true,
        timeout: 8000
      });
    } catch (e) {}
    return [];
  }
}
return []
