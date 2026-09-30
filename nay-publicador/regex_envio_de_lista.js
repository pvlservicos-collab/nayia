/*
 * A gramatica do ENVIO POR LISTA COLADA, em UM lugar.
 *
 * O PEDIDO (Tel, 11/09):
 *
 *   Nay envia esses imoveis para o numero 92994717316
 *   Arezzo Residencial / 2 quartos / 2.5k
 *   Estilo Golf / 2 quartos sendo 1 suite / 2.6k
 *   Estilo Golf / 2 quartos sendo 1 suite / 2.6k
 *
 * POR QUE ESTE ARQUIVO EXISTE: o no `Comando do Tel` faz `split('\n')` e
 * manda ao publicador SO A LINHA que casou -- medido. Para a lista, isso
 * entrega um comando sem imovel nenhum ("nao entendi qual imovel mandar"),
 * porque os codigos estao justamente nas linhas de baixo. Entao a lista
 * precisa de um ramo que mande o TEXTO INTEIRO, e a regra de quando fazer
 * isso nao pode ser redigitada em cada no.
 *
 * `patch_envio_de_lista_n8n.js` LE estes literais deste arquivo. Redigitar
 * regex dentro do patch ja dobrou as barras invertidas uma vez e o literal
 * que entrou no no nao casava NADA -- comando morto em silencio.
 *
 * `teste_regex_envio_de_lista.js` (Node) e `teste_envio_de_lista.py`
 * exercitam os MESMOS casos de `casos_envio_de_lista.json`, entao
 * divergencia entre o Python e os nos vira teste vermelho.
 */

// O MESMO literal das quatro copias (interpretar_comando.py e tres nos).
const ENVIO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh|mostr|post|public|dispar|solt)(?:a|ar|e|ei|ou|o)?\b([\s\S]*)(?:\bpara\b|\bpra\b|\bpro\b|\bp\/)\s*([\s\S]+?)\s*$/i;

const NAO_PESSOA_RE = /\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores)\b/i;

// "Nay codigo 5719" -- ele respondendo a pergunta de desambiguacao.
//
// A PALAVRA "codigo" NA FRENTE E OBRIGATORIA, e e ela que separa isto do
// codigo puro. "5719" sozinho cai no ramo `Achar codigo` do fluxo, que manda
// o card e TODAS as fotos para o chat do proprio Tel -- nao para o corretor.
// A forma com a palavra foi a que ele escreveu, e e a que nao colide.
const ESCOLHER_CODIGO_RE = /^\s*(?:@?nay\b[\s,;:.!?-]*)?(?:c[óo]digos?|cods?)\b[\s:=-]*((?:\d{3,5}[\s,;]*(?:e\s+)?)+)$/i;

// E UMA LISTA COLADA? Cabecalho de envio na primeira linha, itens embaixo.
//
// CODIGO NO CABECALHO CAI NO CAMINHO ANTIGO, de proposito: "Nay manda o 5718
// pro Sergio" seguido de qualquer coisa continua sendo o envio de sempre.
// Este ramo so pega o cabecalho que NAO diz qual imovel -- a forma em que as
// linhas de baixo sao a unica fonte.
function ehEnvioDeLista(texto) {
  const linhas = String(texto || '').split('\n');
  if (linhas.length < 2) return false;
  if (!linhas.slice(1).some((l) => l.trim())) return false;

  const m = linhas[0].trim().match(ENVIO_RE);
  if (!m) return false;
  if (NAO_PESSOA_RE.test(m[3])) return false;
  // codigo no corpo -> caminho antigo
  if (/\b\d{1,6}\b/.test(m[2])) return false;
  return true;
}

// O PEDIDO COM VALOR E SEM DESTINATARIO (15/09).
//
//   Nay envia locacao de 3k a 6k nos bairros parque dez, flores e compensa
//
// Nao tem "para" nenhum, entao o ENVIO_RE nao casa; e "locacao" nao esta na
// lista de substantivos do ramo de categoria. Resultado medido: a frase ia
// para o AGENTE de IA, que respondia qualquer coisa -- "mandei para a Nay
// isso e ela nao soube enviar".
//
// DUAS MARCAS JUNTAS, e e o que impede esta regra de roubar conversa: o
// "@nay" na frente (obrigatorio, sem a forma opcional dos outros ramos) e um
// VALOR ESCRITO no meio. Quem decide o que a frase SIGNIFICA continua sendo o
// Python (`interpretar_comando`); aqui so se decide que ela chega la em vez
// de ir para o agente -- e, se o Python nao entender, ele responde isso.
//
// `post` e `public` ficam DE FORA: sao os verbos de grupo, e "Nay posta o
// 5750" ja tem caminho proprio.
// "ate 2800" e "a partir de 6000" nao tem k nem ponto de milhar -- o que
// marca o valor ali e a PALAVRA DE LIMITE na frente. Sem esta metade,
// "Nay envia locacao ate 2800 no parque dez" (que ele escreveu assim) ficava
// de fora e voltava para o agente.
const VALOR_ESCRITO = '(?:\\d+[.,]?\\d*\\s*(?:k|mil|milh\\w*|mi)\\b|\\d{1,3}\\.\\d{3}\\b'
  + '|\\b(?:at[eé]|a\\s+partir\\s+de|acima\\s+de|no\\s+m[aá]ximo|m[aá]ximo\\s+de)\\s+r?\\$?\\s*\\d)';
const PEDIDO_SEM_DESTINO_RE = new RegExp(
  '^\\s*@?nay\\b[\\s,;:.!?-]*'
  + '(?:envi|m[a]?nd|repass|encaminh|mostr|dispar|solt)\\w*\\b\\s+'
  + '[\\s\\S]*' + VALOR_ESCRITO, 'i');

// AS RESPOSTAS NATURAIS a "qual desses?" -- a licao de 12/09.
//
// Ele respondeu **"os dois"** e a frase nao casou cópia nenhuma: foi para o
// AGENTE de IA, que devolveu uma lista de imoveis sem nexo. E a PROPRIA
// pergunta dela dizia "ou os dois" -- ela induziu a resposta que nao sabia
// ler. Pergunta que nao resolve na volta e laco fechado.
//
// "SIM" E "ISSO" SOZINHOS NAO ENTRAM: ele usa "isso" como confirmacao
// generica (medido nas mensagens reais dele), e com uma lista em aberto um
// "isso" sobre outro assunto mandaria a carteira sem ele pedir. Eles valem so
// colados num quantificador: "sim, os dois".
//
// O MESMO literal de `interpretar_comando.py`. Quem traduz "os dois" nos
// codigos de verdade e o publicador, que tem a lista em aberto na mao -- aqui
// so se decide se a frase E comando.
// "me manda" fica de fora: no vocabulario medido dele "me manda o 2539" e
// como pede o card PARA SI -- o "me" nomeia OUTRO destinatario. E "tudo" fica
// de fora porque ela pede "DESCARTAR TUDO SIM" para confirmar descarte de
// pendencia, e "tudo sim" com uma lista em aberto mandaria a carteira inteira
// enquanto ele pensa que descartou pendencias.
const ANTES_DA_ESCOLHA =
  '(?:(?:sim|isso|ok|blz|beleza|pode|quero|vai|bora|manda|mande|mandar|' +
  'envia|envie|enviar|pode\\s+mandar|pode\\s+enviar)' +
  '[\\s,;.!]*)*';

// O DIGITO CRU exige o artigo: "os 2" e escolha, "2" nao e nada. Digito curto
// solto nao e intencao -- a mesma licao do "as 08:00" que virou os codigos 08
// e 00, e do valor 4000 que virou o imovel 4000. E "2" como resposta a "qual?"
// quer dizer "o segundo", nao "dois deles".
const ESCOLHA_NATURAL_RE = new RegExp(
  '^\\s*(?:@?nay\\b[\\s,;:.!?-]*)?' + ANTES_DA_ESCOLHA +
  '(?:([oa]s?)\\s+)?' +
  '(?:(ambos|ambas|tod[oa]s)' +
  '|(dois|duas|tr[êe]s|quatro|cinco)' +
  '|([2-5])' +
  '|(primeir[oa]|segund[oa]|terceir[oa]|[úu]ltim[oa]))' +
  '\\b([^\\n]*)$', 'i');

// "5719 e 5728" sem a palavra codigo. DOIS OU MAIS de proposito: o codigo
// SOZINHO ja tem caminho proprio -- o ramo `Achar codigo` dispara para
// `^\d{3,5}$` e manda card com todas as fotos. Ele digita codigo puro o tempo
// todo (medido: "5611" 13 vezes), e roubar isso quebraria o que ele mais usa.
const ESCOLHA_SO_CODIGOS_RE = new RegExp(
  '^\\s*(?:@?nay\\b[\\s,;:.!?-]*)?' + ANTES_DA_ESCOLHA +
  '(?:[oa]s?\\s+)?' +
  '(\\d{3,5}(?:\\s*(?:,|;|\\+|/|e)\\s*(?:[oa]s?\\s+)?\\d{3,5})+)' +
  '[\\s.!]*$', 'i');

// Cauda que e CATEGORIA nao e escolha: "manda todos os apartamentos para
// locacao" e a LISTA, e a lista dispara em 13 grupos.
const CATEGORIA_NA_CAUDA =
  /\b(apartamentos?|aptos?|coberturas?|flats?|casas?|sobrados?|salas?\s+comerciais?|salas?|lojas?|lotes?|terrenos?|listas?)\b/i;

// CAUDA COM DESTINATARIO E ENVIO, NAO ESCOLHA. A primeira versao desta
// gramatica roubou "Nay envia todos os acquarelle para locacao para o corretor
// Sergio" -- um comando de envio inteiro: o "envia" cabe no prefixo educado e
// o "todos" no quantificador. A escolha NUNCA tem destinatario: ele ja esta
// guardado na lista em aberto. O pronome escapa ("manda os dois pra ela").
// A EXCECAO DO PRONOME NAO EXISTE, e isso e deliberado: no Python a escolha
// natural roda no FIM do dispatch, entao o ENVIO_RE pega "manda os dois pra
// ela" antes e recusa dizendo "nao achei corretor chamado ela". Abrir o
// pronome aqui faria o JS e o Python discordarem -- exatamente o que a fonte
// unica de casos existe para pegar.
const CAUDA_COM_DESTINO = /\b(?:para|pra|pro|p\/)\s+/i;

// AS PROPRIAS LINHAS DA LISTA casavam a escolha: "2 quartos sendo 1 suite /
// 2.6k" devolvia "manda dois", e o no `Comando do Tel` percorre o texto LINHA
// POR LINHA. Uma linha de PRECO disparava o envio da carteira.
const CAUDA_DE_IMOVEL =
  /\b(?:quartos?|su[íi]tes?|vagas?|dormit[óo]rios?|banheiros?|mobiliad[oa]s?|semi|climatizad[oa]s?|andar|torre|bloco)\b|\d\s*(?:k\b|m2|m²)|r\$|\//i;

// "os dois no grupo" fala de GRUPO, e a escolha manda para UMA PESSOA -- ele
// acharia que postou em 14 grupos e nao postou.
const CAUDA_DE_GRUPO =
  /\b(grupos?|grade|vagas?|easy|anunciar|todos os corretores)\b/i;

function ehEscolhaNatural(texto) {
  const t = String(texto || '');
  if (ESCOLHA_SO_CODIGOS_RE.test(t)) return true;
  const m = t.match(ESCOLHA_NATURAL_RE);
  if (!m) return false;
  // "os 2" e escolha; "2" sozinho nao e nada. O artigo e o que separa.
  if (m[4] && !m[1]) return false;
  const cauda = m[6] || '';
  return !CATEGORIA_NA_CAUDA.test(cauda) && !CAUDA_COM_DESTINO.test(cauda)
      && !CAUDA_DE_IMOVEL.test(cauda) && !CAUDA_DE_GRUPO.test(cauda);
}

function ehEscolhaDeCodigo(texto) {
  return ESCOLHER_CODIGO_RE.test(String(texto || ''));
}

module.exports = { ENVIO_RE, NAO_PESSOA_RE, ESCOLHER_CODIGO_RE,
                   ESCOLHA_NATURAL_RE, ESCOLHA_SO_CODIGOS_RE,
                   CATEGORIA_NA_CAUDA, CAUDA_COM_DESTINO, CAUDA_DE_IMOVEL,
                   CAUDA_DE_GRUPO, ANTES_DA_ESCOLHA,
                   ehEnvioDeLista, ehEscolhaDeCodigo, ehEscolhaNatural };
