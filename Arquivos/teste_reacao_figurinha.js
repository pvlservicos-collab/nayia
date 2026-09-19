/*
 * Reação e figurinha NÃO são "arquivo que não consigo abrir".
 *
 * O CASO (Moacy, 31/08 19:23): ele reagiu com 👍🏼 numa mensagem da Nay --
 * um "ok" silencioso. Ela respondeu "moacy, não consigo abrir esse
 * arquivo. escreve a mensagem ou me manda o código do imóvel?". Ele não
 * tinha mandado arquivo nenhum.
 *
 * Duas causas somadas:
 *   1. o `Filtrar e normalizar` classificava tudo que não é texto nem
 *      mídia conhecida como 'outro', e o `Juntar mensagens` tratava
 *      'outro' como arquivo;
 *   2. figurinha na Z-API costuma chegar como IMAGEM, então mesmo
 *      excluindo 'outro' ela cairia em 'imagem' e avisaria do mesmo jeito.
 *
 * Por isso reação e figurinha são testadas ANTES de imagem, e nenhuma das
 * duas gera aviso. Áudio, imagem, documento e vídeo de verdade continuam
 * avisando -- ali ela realmente não consegue abrir.
 *
 * Uso (precisa do Node do container):
 *   scp teste_reacao_figurinha.js root@SERVIDOR:/tmp/r.js
 *   ssh root@SERVIDOR 'docker cp /tmp/r.js n8n-viux-n8n-1:/tmp/r.js \
 *     && docker exec n8n-viux-n8n-1 node /tmp/r.js'
 */
// Espelha a classificacao de origem do `Filtrar e normalizar` e a decisao
// do `Juntar mensagens` de avisar (ou nao) que nao consegue abrir.
function origemDe(b, texto) {
  if (b.reaction || b.reactionBy || b.isReaction) return 'reacao';
  if (b.sticker || (b.image && b.image.isSticker)) return 'figurinha';
  if (b.audio) return 'audio';
  if (b.image) return 'imagem';
  if (b.document) return 'documento';
  if (b.video) return 'video';
  if (!texto) return 'outro';
  return 'texto';
}
const avisa = o => !['outro', 'reacao', 'figurinha', 'texto'].includes(o);

const casos = [
  ['CASO REAL Moacy: joinha na msg dela', {reactionBy:'5592...'}, null, 'reacao',   false],
  ['reacao com outro campo',              {isReaction:true},      null, 'reacao',   false],
  ['figurinha como sticker',              {sticker:{url:'x'}},    null, 'figurinha',false],
  ['figurinha que chega como imagem',     {image:{isSticker:true}},null,'figurinha',false],
  ['imagem de verdade',                   {image:{url:'x'}},      null, 'imagem',   true],
  ['audio de verdade',                    {audio:{url:'x'}},      null, 'audio',    true],
  ['documento',                           {document:{url:'x'}},   null, 'documento',true],
  ['video',                               {video:{url:'x'}},      null, 'video',    true],
  ['nada reconhecido, sem texto',         {},                     null, 'outro',    false],
  ['texto normal',                        {},              'bom dia', 'texto',      false],
  ['imagem COM legenda (tem texto)',      {image:{url:'x'}}, 'olha isso', 'imagem', true],
];

let falhas = 0;
for (const [rotulo, body, texto, esperaOrigem, esperaAviso] of casos) {
  const o = origemDe(body, texto);
  const a = avisa(o);
  const ok = o === esperaOrigem && a === esperaAviso;
  if (!ok) falhas++;
  console.log(`${ok ? 'OK  ' : 'FALHOU'}  ${rotulo.padEnd(36)} origem=${o.padEnd(10)} avisa=${a}`);
}
console.log();
console.log(falhas === 0 ? `TODOS OS ${casos.length} PASSARAM` : `${falhas} FALHARAM`);
process.exit(falhas ? 1 : 0);
