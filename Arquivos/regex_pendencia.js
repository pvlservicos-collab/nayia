// A gramatica dos comandos de PENDENCIA do Tel, em UM lugar so.
//
// NASCEU DE UM CASO REAL (01/09, 13h18): o Tel escreveu "descarta 47" e a
// gramatica so conhecia "DESCARTAR". A mensagem caiu no agente, que leu o
// 47 como codigo de imovel e respondeu "o 47 tem so dois digitos, me
// passa o codigo completo". Ele repetiu tres vezes sem entender.
//
// Este arquivo e a FONTE: o patch do n8n cola estas mesmas linhas nos dois
// nos que precisam delas -- `Comando do Tel`, que EXECUTA, e `Rotear para
// o agente`, que DESCARTA (senao o Tel recebe resposta dupla). Divergir e
// o padrao 4.3 do HISTORICO, e aqui ja custou.
//
// Rodar: node teste_regex_pendencia.js

// O vocativo no comeco, aceito em todos os caminhos desde 27/08.
const VOC = '(?:@?nay\\b[\\s,;:.!?-]*)?';

// Os verbos que o Tel usa de verdade para descartar. "esquece" entrou
// porque e o que sai naturalmente quando se quer que a Nay pare de
// reusar aquilo.
const V_DESCARTA =
  '(?:descarta|descartar|descarte|esquece|esquecer|esqueca|esqueça|' +
  'apaga|apagar|cancela|cancelar|ignora|ignorar)';

const V_RESPOSTA = '(?:resposta|responde|responder)';

// "a", "a pendencia", "a pendência" entre o verbo e o numero.
const LIGACAO = '(?:\\s+a)?(?:\\s+pend[eê]ncias?)?';

const RE_RESPOSTA = new RegExp(
  '^\\s*' + VOC + V_RESPOSTA + LIGACAO + '\\s+(\\d{1,6})\\s+([\\s\\S]+?)\\s*$', 'i');

// `\\d{1,6}\\s*$` no fim: "descarta 47 e posta o 5750" NAO e descarte --
// tem cauda, e cauda muda a intencao.
const RE_DESCARTA = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + LIGACAO + '\\s+(\\d{1,6})\\s*$', 'i');

const RE_DESCARTA_TUDO = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + '\\s+tudo\\s*$', 'i');

const RE_DESCARTA_TUDO_SIM = new RegExp(
  '^\\s*' + VOC + V_DESCARTA + '\\s+tudo\\s+sim\\s*$', 'i');

const RE_LISTAR = new RegExp(
  '^\\s*' + VOC + '(?:pend[eê]ncias?|pendentes)\\s*$', 'i');

// Um comando de pendencia, qualquer um deles. E o que o `Rotear para o
// agente` usa para descartar.
function ehComandoDePendencia(t) {
  const s = String(t || '');
  return RE_DESCARTA_TUDO_SIM.test(s) || RE_DESCARTA_TUDO.test(s) ||
         RE_DESCARTA.test(s) || RE_RESPOSTA.test(s) || RE_LISTAR.test(s);
}

// Qual comando, e com que argumentos. E o que o `Comando do Tel` usa.
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

if (typeof module !== 'undefined') {
  module.exports = { ehComandoDePendencia, interpretarPendencia };
}
