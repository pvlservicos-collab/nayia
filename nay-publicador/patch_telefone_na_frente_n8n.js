// TELEFONE NA FRENTE: "envia 92 9383-0696 o 2659" e "envia 92 99462-9241
// codigo 150".
//
// O CASO, TRES VEZES (Tel, 23/09): ele escreve o comando com o telefone antes
// do codigo, o `ENVIO_RE` -- que EXIGE "para/pra/pro" -- nao casa, e a frase
// vai ao AGENTE, que escala de volta. Na segunda vez eu ja tinha consertado o
// PYTHON e esqueci o NO. Na terceira eu tinha consertado os nos da NAY ANTIGA
// e esqueci os da NAI -- e e a NAI que atende os comandos dele hoje. O
// CLAUDE.md diz "QUATRO copias"; medido em 23/09 sao SEIS, em dois fluxos:
//
//   Nay antiga  `Comando do Tel`            manda ao publicador
//   Nay antiga  `Rotear para o agente`      DESCARTA (senao resposta dupla)
//   Nay antiga  `Achar codigo na resposta`  nao deixa o texto DELE virar foto
//   NAI         `Comando do Tel`            idem ao primeiro
//   NAI         `Rotear pelo cabecalho`     roteia para `tel_antigo`
//   NAI         `Achar codigo na resposta`  idem ao terceiro
//
// A preposicao NAO pode ser afrouxada no `ENVIO_RE`: e ela que separa o envio
// privado do `posta`, que vai para os 19 grupos. Por isso esta forma tem regex
// PROPRIA e estreita -- so vale com TELEFONE, que nenhum codigo de imovel tem.
//
// Uso:  node patch_telefone_na_frente_n8n.js entrada.json saida.json
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const INICIO = '// >>> telefone na frente (patch 23/09)';
const FIM = '// <<< telefone na frente';

// O MESMO literal de `interpretar_comando.py`. Divergir aqui e o bug que este
// arquivo existe para nao repetir.
//
// DOIS DIGITOS so com a palavra "codigo": o catalogo tem um imovel de dois
// digitos (o 45) e 14 de tres, e sem o marcador "os 2" -- a escolha da lista,
// medida em 12/09 -- viraria o imovel 2. O `55` na frente e opcional porque e
// a forma que o banco guarda o telefone.
const LITERAL =
  "/^\\s*(?:@?nay\\b[\\s,;:.!?-]*)?(envi|m[a]?nd|repass|encaminh)(?:a|ar|e|ei|ou|o)?\\b\\s*" +
  "(?:para\\s+|pra\\s+|pro\\s+|p\\/\\s*)?" +
  "((?:55[\\s.-]*)?\\(?\\d{2}\\)?[\\s.-]*\\d{4,5}[\\s.-]*\\d{4})" +
  "\\s+(c[o\\u00f3]d(?:igo)?s?\\b[\\s:=.-]*\\d{2,5}(?:[\\s,;]+(?:e\\s+)?(?:o|os)?\\s*\\d{2,5})*" +
  "|(?:o|os|a|as)?\\s*\\d{3,5}(?:[\\s,;]+(?:e\\s+)?(?:o|os)?\\s*\\d{3,5})*)\\s*$/i";

// TELEFONE ANTES DO VERBO: "92 9454-0289 envia todos os apartamentos no
// condominio verona para este numero" (Tel, 24/09, duas vezes em minutos).
//
// Aqui basta DETECTAR: o no manda a linha inteira ao publicador, e quem
// reescreve para a forma canonica e o `interpretar_comando.py`. Sem esta
// deteccao a frase nem chega la -- vai para o modelo, que trata o Tel como
// corretor qualquer.
//
// `en+vi` e `m[a]?n+d` porque ele digitou "ennvia": letra repetida e o
// teclado do celular, nao outra palavra.
const LITERAL_ANTES =
  "/^\\s*(?:55[\\s.-]*)?\\(?\\d{2}\\)?[\\s.-]*\\d{4,5}[\\s.-]*\\d{4}[\\s,;:.-]+" +
  "(?:@?nay\\b[\\s,;:.!?-]*)?" +
  "(?:en+vi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\\b/i";

// UMA FUNCAO NOMEADA, e os pontos de uso nunca mais mudam.
//
// A primeira versao deste patch punha `ENVIO_TEL_FRENTE.test(...)` direto em
// cada ponto. Ao acrescentar a segunda forma, o caminho "bloco ja existe"
// trocou as DECLARACOES e nao religou os USOS: os seis nos passaram a
// declarar `ENVIO_TEL_ANTES` e nenhum o usava. Passou no `node --check`, e
// so o provador pegou. Com `EH_ENVIO_TEL`, acrescentar forma e editar o
// BLOCO -- nada mais.
// O GRUPO "IMÓVEIS ALTO PADRÃO PARA ANUNCIAR EASY" (Tel, 25/09).
//
// "Nay envia para o grupo alto padrão 4567" -- a frase que ele deu -- NAO era
// reconhecida pelo `Comando do Tel`: o `NAO_PESSOA_RE` contem `grupos?`, entao
// o ramo de envio descarta de proposito (e a parede que impede "envia o 5750
// pro grupo" de virar disparo), e o ramo de POSTA nao casa com "envia". A NAI
// roteava para `tel_antigo` e o outro lado deixava cair -- o "mandei e ela nao
// fez nada" de sempre. Medido em 25/09 antes de consertar.
//
// DUAS MARCAS SAO EXIGIDAS, "alto padrao" E grupo/easy/anunciar, iguais as da
// versao Python. Sem a segunda, "envia o 5750 pro corretor do alto padrao" --
// uma PESSOA -- viraria postagem num grupo de 11 corretores, e isso nao
// desfaz.
// SEM `post|public` AQUI, e isso NAO e esquecimento -- e a correcao de um
// estrago real de 25/09. O no ja trata "POSTA/PUBLICA" num ramo proprio, o das
// palavras em caixa alta. Com os dois verbos no meu literal, "Posta no grupo
// alto padrao easy 5035" casava OS DOIS RAMOS e o publicador era chamado DUAS
// VEZES: duas respostas iguais ao Tel, e a reserva atomica transformava a
// segunda chamada em "ja foi postado, quer que eu poste de novo?" -- ele
// recebeu isso em cadeia, achou que nada tinha funcionado e repetiu o comando
// tres vezes.
//
// Este literal existe para as formas que o ramo de ENVIO nao pega (o
// `NAO_PESSOA_RE` descarta "grupo"). Postagem por "posta"/"publica" ja tem
// caminho, e acrescentar um segundo nao acrescenta nada -- duplica.
const LITERAL_ALTO_PADRAO =
  "/^\\s*(?:@?nay\\b[\\s,;:.!?-]*)?" +
  "(?:envi|m[a]?n+d|repass+|encaminh)(?:a|ar|e|ei|ou|o)?\\b" +
  "(?=[\\s\\S]*\\balto[\\s\\-]*padr[a\\u00e3]o\\b)" +
  "(?=[\\s\\S]*\\b(?:grupo|easy|anunciar)\\b)/i";

const BLOCO = [
  INICIO,
  'const ENVIO_TEL_FRENTE = ' + LITERAL + ';',
  'const ENVIO_TEL_ANTES = ' + LITERAL_ANTES + ';',
  'const ALTO_PADRAO_GRUPO = ' + LITERAL_ALTO_PADRAO + ';',
  // A funcao nomeada e o que faz uma forma nova custar UMA edicao em vez de
  // seis. Foi criada ontem exatamente por isso, e hoje pagou.
  'const EH_ENVIO_TEL = (x) => ENVIO_TEL_FRENTE.test(x) || ENVIO_TEL_ANTES.test(x)' +
    ' || ALTO_PADRAO_GRUPO.test(x);',
  FIM,
].join('\n');

// Bloco DELIMITADO, trocado inteiro. Guarda por mudanca ("se ja tem, pula")
// empilharia a versao velha ao lado da nova -- a licao de 12/09.
function trocar(c) {
  const i = c.indexOf(INICIO);
  if (i < 0) return null;
  const j = c.indexOf(FIM, i);
  if (j < 0) throw new Error('marcador de inicio sem o de fim');
  return c.slice(0, i) + BLOCO + c.slice(j + FIM.length);
}

let mexidos = 0;

// Migra a forma antiga (`ENVIO_TEL_FRENTE.test(x)` solto no codigo) para a
// funcao nomeada. So FORA do bloco -- dentro dele a chamada e a definicao.
function migrar(c) {
  const i = c.indexOf(INICIO);
  const j = c.indexOf(FIM, i);
  if (i < 0 || j < 0) return c;
  const antes = c.slice(0, i);
  const bloco = c.slice(i, j + FIM.length);
  const depois = c.slice(j + FIM.length);
  const troca = (x) => x.replace(/ENVIO_TEL_FRENTE\.test\(/g, () => 'EH_ENVIO_TEL(');
  return troca(antes) + bloco + troca(depois);
}

function patch(nome, inserir, ligar) {
  const node = nos[nome];
  if (!node) return;                       // o no vive no outro fluxo
  let c = node.parameters.jsCode;

  // 1. o bloco: trocado inteiro se existe, inserido se nao
  const trocado = trocar(c);
  c = trocado !== null ? trocado : inserir(c);

  // 2. a forma antiga vira a funcao nomeada
  c = migrar(c);

  // 3. e o uso, se ainda nao existir.
  //
  // A CONTAGEM E SO DOS USOS: a definicao e `const EH_ENVIO_TEL = (x) =>`,
  // com espaco antes do parentese, entao ela NAO casa com `EH_ENVIO_TEL\(`.
  // Contar errado aqui fez o patch chamar `ligar` de novo num no ja ligado e
  // duplicar `const mTelFrente` -- declaracao duplicada derruba o no INTEIRO,
  // e o `node --check` passa nela (CLAUDE.md, 12/09).
  const usos = (c.match(/EH_ENVIO_TEL\(/g) || []).length;
  if (usos < 1) {
    c = ligar(c);
  }

  const agora = (c.match(/EH_ENVIO_TEL\(/g) || []).length;
  if (agora < 1) throw new Error(nome + ': o literal ficou sem uso');
  const dup = (c.match(/const mTelFrente/g) || []).length;
  if (dup > 1) throw new Error(nome + ': const mTelFrente duplicada');
  node.parameters.jsCode = c;
  console.log('  ' + nome + ': ok (' + agora + ' uso)');
  mexidos++;
}

// ---------- 1. Comando do Tel: manda ao publicador ----------
patch('Comando do Tel', (c) => {
  // A NAY antiga le `j.texto` (do `Juntar mensagens`); a NAI le `cab.texto`
  // (do cabecalho). Fixar um dos dois fazia o patch recusar o outro fluxo --
  // que e exatamente a copia que estava faltando.
  const decl = c.match(/const linhas = String\([^)]*\)\.split\('\\n'\);/);
  if (!decl) throw new Error('ancora do laco mudou');
  return c.replace(decl[0], () => BLOCO + '\n' + decl[0]);
}, (c) => {
  const anc = 'const mEnv = linha.match(ENVIO_RE);';
  if (!c.includes(anc)) throw new Error('ancora do ENVIO_RE mudou');
  // O teste entra ao lado do ENVIO_RE, no MESMO ramo -- mesmo timeout, mesma
  // rota, porque e o MESMO comando escrito de outro jeito.
  c = c.replace(anc, () => anc + '\n  const mTelFrente = EH_ENVIO_TEL(linha);');
  return c.replace('if (mEnv && !NAO_PESSOA_RE.test(mEnv[3])) {',
    () => 'if (mTelFrente || (mEnv && !NAO_PESSOA_RE.test(mEnv[3]))) {');
});

// ---------- 2. Rotear para o agente: DESCARTA ----------
// Sem isto o Tel recebe resposta dupla -- o publicador manda o imovel e o
// agente responde alguma coisa sobre a mesma frase.
patch('Rotear para o agente', (c) => {
  const anc = 'const ehTel = ';
  const i = c.indexOf(anc);
  if (i < 0) throw new Error('nao achei o ehTel');
  const fim = c.indexOf('\n', i) + 1;
  return c.slice(0, fim) + '\n' + BLOCO + '\n' + c.slice(fim);
}, (c) => {
  const anc = FIM + '\n';
  const i = c.indexOf(anc);
  if (i < 0) throw new Error('nao achei o fim do bloco');
  const corte = i + anc.length;
  return c.slice(0, corte) +
    'if (ehTel && EH_ENVIO_TEL(t)) return [];\n' + c.slice(corte);
});

// ---------- 3. Rotear pelo cabecalho (NAI): manda para `tel_antigo` ----------
// E O NO DECISIVO. Foi por aqui que "envia 92 99462-9241 codigo 150" escapou
// em 23/09 as 19:58: `ehComandoAntigo` nao reconheceu, a frase seguiu para o
// agente da NAI e ele respondeu ao Tel sobre o Tel ("o corretor Tel Sobreira
// pediu fotos do 150").
patch('Rotear pelo cabeçalho', (c) => {
  // A declaracao vai no topo do arquivo: `ehComandoAntigo` e uma funcao, e a
  // const precisa existir no escopo do modulo quando ela roda.
  return BLOCO + '\n' + c;
}, (c) => {
  const anc = '  return ehComandoDePendencia(t)';
  if (!c.includes(anc)) throw new Error('ancora do ehComandoAntigo mudou');
  return c.replace(anc, () => anc + '\n    || EH_ENVIO_TEL(t)');
});

// ---------- 4. Achar codigo na resposta: o texto DELE nao vira foto ----------
// Sem esta copia, "Nay envia as FOTOS do 5750 pro Sergio" faz o gatilho ler o
// texto do proprio Tel e mandar as fotos para o chat DELE.
patch('Achar codigo na resposta', (c) => {
  return BLOCO + '\n' + c;
}, (c) => {
  const anc = '\\s*$/i.test(escreveu)) {';
  if (!c.includes(anc)) throw new Error('ancora do guarda de comando mudou');
  return c.replace(anc, () => '\\s*$/i.test(escreveu) || EH_ENVIO_TEL(escreveu)) {');
});

if (!mexidos) throw new Error('nenhum no deste fluxo foi tocado');
fs.writeFileSync(process.argv[3],
  JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  ' + mexidos + ' no(s) -- gravado em ' + process.argv[3]);
