/*
 * Deteccao do CARD COLADO -- no `Juntar mensagens`.
 *
 * A DESCOBERTA (30/08): a Z-API NAO manda mensagem citada. Capturei a
 * estrutura de 22 payloads reais e nenhum traz `referencedMessage`. Os
 * campos que chegam sao:
 *   isStatusReply chatLid connectedPhone waitingMessage isEdit isGroup
 *   isNewsletter instanceId messageId phone fromMe momment status chatName
 *   senderName photo broadcast adContext messageExpirationSeconds
 *   forwarded type fromApi text
 *
 * O `referencedMessage` que eu tinha achado no historico de execucoes do
 * n8n em 29/08 vinha de outro contexto (reacao), e passei um dia inteiro
 * escrevendo extracao para um campo que nao existe nesta configuracao.
 *
 * O que o corretor faz DE VERDADE e COLAR ou ENCAMINHAR o card do grupo.
 * O texto chega inteiro -- nunca houve dado faltando. O defeito era ela
 * ler o card, buscar o codigo e devolver o MESMO card: a Samira mandou o
 * 2943 e recebeu o 2943 de volta.
 *
 * Uso (precisa do Node do container):
 *   scp teste_card_colado.js root@SERVIDOR:/tmp/c.js
 *   ssh root@SERVIDOR 'docker cp /tmp/c.js n8n-viux-n8n-1:/tmp/c.js \
 *     && docker exec n8n-viux-n8n-1 node /tmp/c.js'
 */
// Detecta o card COLADO pelo corretor. Levantado em 30/08: a Z-API nao
// manda mensagem citada, entao o jeito real de identificar imovel e o
// corretor colar ou encaminhar o card do grupo.
function tratar(texto) {
  const mCard = texto.match(/C[óo]digo:\s*(\d{3,5})/i);
  if (mCard && /[📍•]/.test(texto)) {
    return { ehCard: true, codigo: mCard[1] };
  }
  return { ehCard: false, codigo: null };
}

const CARD_SAMIRA = '\u{1F4CD} Condomínio Acquarelle\n* Bairro: Ponta Negra\n* 58m2\n* 2 quartos sendo 1 suíte\n• 1 vaga\nLocação: R$ 3.500\nCódigo: 2943';
const CARD_SEM_PIN = '• Bairro: Ponta Negra\n• 2 quartos\nCódigo: 2943';

const casos = [
  ['CASO REAL Samira: card colado',   CARD_SAMIRA,                    true,  '2943'],
  ['card sem o pin, com bullets',     CARD_SEM_PIN,                   true,  '2943'],
  ['card com texto junto',            CARD_SAMIRA + '\nesse aqui',    true,  '2943'],
  ['so o codigo, sem card',           '2943',                         false, null],
  ['fala do codigo em frase',         'me manda o 2943 por favor',    false, null],
  ['pergunta comum',                  'tem algo no Aleixo?',          false, null],
  ['numero grande sem card',          'o de 900.000 ainda ta?',       false, null],
  ['bullet sem codigo',               '• quero 2 quartos\n• ate 3000', false, null],
];

let falhas = 0;
for (const [rotulo, txt, esperaCard, esperaCod] of casos) {
  const r = tratar(txt);
  const ok = r.ehCard === esperaCard && r.codigo === esperaCod;
  if (!ok) falhas++;
  console.log(`${ok ? 'OK  ' : 'FALHOU'}  ${rotulo.padEnd(32)} -> card=${r.ehCard} codigo=${r.codigo}`);
}
console.log();
console.log(falhas === 0 ? `TODOS OS ${casos.length} PASSARAM` : `${falhas} FALHARAM`);
process.exit(falhas ? 1 : 0);
