/*
 * A RESPOSTA À PERGUNTA DO `posta <nome do condominio>`, em UM lugar.
 *
 * O PEDIDO (Tel, 15/09): "se estiver mais de uma opcao ela vai me mandar o
 * jardim das cerejeiras com o valor e codigo para eu decidir e respondo com
 * ela pelo valor ou codigo que ela me enviou". E "caso tenha para venda e
 * locacao ela me pergunta se e para venda ou locacao".
 *
 * Entao a resposta dele e uma destas tres coisas, sozinha na mensagem:
 *   "locacao" / "venda"   -> qual lado
 *   "5725"                -> qual imovel
 *   "3.6k" / "3.600"      -> qual imovel, pelo valor que ela imprimiu
 *
 * SO VALE COM PERGUNTA ABERTA (`nay_pergunta_aberta_do_tel`, lido no
 * `Reservar mensagens`). Sem isso, "5725" sozinho e o codigo puro de sempre,
 * que manda o card no chat do proprio Tel -- e "venda" e conversa.
 *
 * TRES NOS DEPENDEM DISTO, e por motivos diferentes:
 *   `Comando do Tel`       -> manda ao publicador (senao a resposta morre)
 *   `Rotear para o agente` -> DESCARTA (senao o agente responde por cima)
 *   `Achar codigo`         -> NAO busca o card (senao ele recebe o card no
 *                             privado ao mesmo tempo em que o imovel vai aos
 *                             grupos -- os ramos rodam em PARALELO)
 *
 * `casos_escolha_do_posta.json` roda contra este arquivo (Node) e contra o
 * `interpretar_comando.py` (Python), entao divergencia vira teste vermelho.
 */

// Os enfeites que ele pode pendurar na frente: "e locacao", "o 5725",
// "codigo 5725", "o de 3.6k". Sao opcionais e podem vir juntos.
const PREFIXO_DA_ESCOLHA =
  '(?:@?nay\\b[\\s,;:.!?-]*)?(?:(?:[eé]|eh|para|pra|pro|de|do|o|a|no|na|esse|essa|c[óo]digo|cod|por)\\s+)*';

// O NUMERO DE 1 OU 2 DIGITOS FICA DE FORA: "1" e "2" e o que ele escreveria
// contando as opcoes na tela, e a pergunta nao as numera -- imprime o CODIGO
// na frente. Virar "R$ 1" ali seria responder qualquer coisa.
const ESCOLHA_DO_POSTA_RE = new RegExp(
  '^\\s*' + PREFIXO_DA_ESCOLHA
  + '(?:loca[çc][ãaoõ]\\w*|alug\\w*|arrend\\w*|vend[ae]s?|vender'
  + '|r\\$\\s*\\d[\\d.,]*'
  + '|\\d[\\d.,]*\\s*(?:milh\\w*|mil|mi|k|m)'
  + '|\\d{1,3}[.,]\\d{3}'
  + '|\\d{3,5})'
  + '[\\s.!,;]*$', 'i');

function ehEscolhaDoPosta(texto) {
  return ESCOLHA_DO_POSTA_RE.test(String(texto || '').trim());
}

if (typeof module !== 'undefined') {
  module.exports = { ESCOLHA_DO_POSTA_RE, ehEscolhaDoPosta };
}
