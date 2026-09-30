/*
 * A gramatica de "o imovel saiu do mercado", em UM lugar.
 *
 * POR QUE ESTE ARQUIVO EXISTE: a mesma regra vive nos nos `Comando do Tel` e
 * `Rotear para o agente` do n8n, mais o `interpretar_comando.py`. Quando as
 * copias divergem, ou o comando MORRE (o Tel escreve e nada acontece) ou o
 * Tel recebe resposta DUPLA -- uma do publicador e outra do agente. O
 * CLAUDE.md ja registra que a gramatica de envio chegou a ter quatro copias
 * com uma errada.
 *
 * Os dois nos do n8n colam este mesmo literal. `teste_regex_liberar.js` roda
 * os casos de `casos_comando_liberar.json` contra ele, e
 * `teste_interpretar_comando.py` roda os MESMOS casos contra o Python --
 * entao divergencia vira teste vermelho em vez de comando morto.
 */

// Verbo na frente: "ALUGOU 5712", "Nay lista de apartamento para locacao".
// Os outros comandos entram junto porque os dois nos usam uma condicao so.
//
// MANDA/ENVIA ficam de fora do primeiro grupo de propósito: sozinhos eles
// aparecem em conversa comum do Tel, e aqui reconhecer demais faz o
// publicador responder "nao entendi" a cada frase. Eles so entram COLADOS em
// LISTA -- "Nay manda a lista de apartamento para locacao" -- que e forma que
// ele usa e que, sem isto, morreria calada: nao casa o primeiro grupo e nao
// casa a regex de envio privado (que exige preposicao no fim).
// MANDA/ENVIA tambem valem com o SUBSTANTIVO da categoria, sem a palavra
// "lista" -- "manda as salas comerciais para locacao". Em 09/09 o Tel escreveu
// "dispara apartamentos para locacao no anunciar easy" e ouviu "nao entendi":
// a gramatica tinha sido montada a partir da frase que ele digitou AQUI, que
// trazia "lista". Esta lista de substantivos e a irma do
// `_SUBSTANTIVO_DE_CATEGORIA` do `interpretar_comando.py`; `casos_comando_
// liberar.json` roda os dois lados e acusa se uma andar sem a outra.
const VERBO_NA_FRENTE =
  /^(@?NAY\b[\s,:;.!\-]*)?((POSTA|POSTAR|PUBLICA|PUBLICAR|DISPARA|DISPARAR|SOLTA|TIRA|TIRAR|REMOVE|REMOVER|RETIRA|RETIRAR|VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA|VAGAS|VAGA|LISTA)\b|AGENDA\s+DE\s+VISITAS?\b|VISITAS?\s+(AGENDADAS?|DO\s+DIA|DE\s+HOJE)\b|AGENDA\b|(MANDA|MANDAR|MANDE|ENVIA|ENVIAR|ENVIE)\s+(AS?\s+|OS?\s+)?(LISTA|APARTAMENTOS?|APTOS?|COBERTURAS?|FLATS?|CASAS?|SOBRADOS?|SALAS?|LOJAS?|LOTES?|TERRENOS?)\b)/i;

// Codigo na frente: "5712 Alugado". Pedido do Tel em 09/09 -- e como ele
// escreve olhando a grade, que lista o codigo primeiro.
//
// O codigo tem que estar no COMECO e o verbo COLADO nele: sem isso,
// "o imovel 5712 foi alugado ontem" -- conversa -- viraria comando, e
// comando aqui posta no grupo sem desfazer.
const CODIGO_NA_FRENTE =
  /^(?:@?NAY\b[\s,:;.!\-]*)?(\d{3,5})\s*[-–—:,]?\s*(?:JA|JÁ)?\s*(VENDEU|VENDIDO|VENDIDA|ALUGOU|ALUGADO|ALUGADA)\b/i;

// "5729 incluso a tx" -- a taxa de condominio ja esta no aluguel. O site NAO
// publica esse dado (conferido no HTML inteiro do 5729), entao so o Tel pode
// informar. Olha a FRASE inteira, nao a ordem das palavras: "5729 sem a tx" e
// "5729 tx nao inclusa" tem que valer, e a primeira versao errou os dois.
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

function ehComandoDoTel(texto) {
  const t = String(texto || '');
  return VERBO_NA_FRENTE.test(t) || CODIGO_NA_FRENTE.test(t) || ehComandoDeTaxa(t);
}

// Só para o teste: qual codigo e qual motivo a forma "codigo na frente" leu.
function lerCodigoNaFrente(texto) {
  const m = CODIGO_NA_FRENTE.exec(String(texto || ''));
  if (!m) return null;
  return {
    codigo: m[1],
    motivo: /^alug/i.test(m[2]) ? 'alugado' : 'vendido',
  };
}

module.exports = { VERBO_NA_FRENTE, CODIGO_NA_FRENTE, TAXA_CODIGO,
                   ehComandoDeTaxa, ehComandoDoTel, lerCodigoNaFrente };
