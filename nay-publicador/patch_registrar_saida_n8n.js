// Cada mensagem que SAI é registrada com o ID dela -- dentro do laço,
// onde o ID e o texto andam juntos.
//
// O QUE EU AFIRMEI E NÃO ERA VERDADE: escrevi em 01/09 que "a citação
// resolve por igualdade de message_id". O sinal da Z-API chega mesmo
// (`citado_id` vem preenchido). O que não existia era o outro lado.
//
// MEDIDO na execução 3768 (Waldyrene, 22h02), lendo o runData do próprio
// n8n em vez de supor:
//   * `Enviar Z-API` rodou 4 vezes, um card por vez, cada uma com seu
//     messageId;
//   * `Preparar registro` rodou UMA vez e pegou `.first()`, que é o
//     primeiro item da ÚLTIMA rodada -- ou seja, o ID do QUARTO card;
//   * e casou esse ID com `codigo = 1125`, que é o PRIMEIRO card.
//   * resultado no banco (envios 215): código 1125 com o ID do 5643.
//
// Isso não é "não resolve": é resolver ERRADO. Se ela citasse o último
// card, a Nay responderia com convicção sobre outro imóvel.
//
// E o caso da Alice (21h57 e 21h58): ela marcou duas mensagens da Nay e
// ouviu "não consigo identificar qual imóvel foi citado" duas vezes. Os
// IDs não estavam em `envios` porque `Registrar envio` só grava quando a
// resposta tem `Código: NNNN` -- e o que ela marcou era a LISTA
// ("• 2943 ... • 5611 ..."), que não tem esse rótulo. Card era
// registrado; conversa, não.
//
// O CONSERTO É DE LUGAR, não de lógica: um nó DENTRO do laço, entre o
// `Enviar Z-API` e o `Loop fotos`. Ali, na mesma iteração, `$json` é a
// resposta da Z-API (o ID) e `$('Loop fotos').first().json.corpo.message`
// é o texto que acabou de sair. Não há pareamento a errar.
//
// Falha FECHADA para o laço: `onError: continueRegularOutput` e
// `alwaysOutputData`, senão um erro de banco pararia o envio das fotos no
// meio -- a mensagem já saiu quando isto roda.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

const modelo = nos['Registrar envio'];
if (!modelo) throw new Error('Registrar envio nao encontrado (modelo de credencial)');

const QUERY = `-- Uma linha por mensagem que sai, com o ID dela.
-- Os dois INSERT sao CTE que MODIFICA dado, entao os dois rodam sempre --
-- CTE de SELECT que ninguem referencia o Postgres nem executa (foi assim
-- que o \`nay_sincronizar_nome\` ficou meses sem rodar).
WITH s AS (
  INSERT INTO mensagem_saida (message_id, telefone, texto)
  SELECT $1::text, $2::text, $3::text
   WHERE NULLIF(btrim(coalesce($1::text,'')),'') IS NOT NULL
  ON CONFLICT (message_id) DO NOTHING
  RETURNING 1
), e AS (
  -- O codigo sai do TEXTO DESTA mensagem, nao de outro no: e isso que
  -- garante que o codigo e o ID sejam do mesmo card.
  INSERT INTO envios (codigo, telefone, destino, valor_enviado, message_id)
  SELECT i.codigo, $2::text, 'corretor',
         COALESCE(i.valor_venda, i.valor_aluguel, 0), $1::text
    FROM imoveis i
   WHERE NULLIF(btrim(coalesce($1::text,'')),'') IS NOT NULL
     AND i.codigo::text = (regexp_match(coalesce($3::text,''), 'C[oó]digo:\\s*(\\d{3,5})'))[1]
  RETURNING 1
)
SELECT (SELECT count(*) FROM s) AS saida, (SELECT count(*) FROM e) AS envio;`;

const REPL = "={{ [$json.messageId ?? $json.id ?? $json.zaapId ?? null, " +
  "$('Juntar mensagens').first().json.telefone ?? null, " +
  "(($('Loop fotos').first().json.corpo || {}).message) ?? null] }}";

if (!nos['Registrar saida']) {
  const pos = (nos['Enviar Z-API'].position || [0, 0]);
  wf.nodes.push({
    parameters: { operation: 'executeQuery', query: QUERY, options: { queryReplacement: REPL } },
    type: modelo.type,
    typeVersion: modelo.typeVersion,
    position: [pos[0] + 180, pos[1] + 140],
    id: 'reg-saida-0001',
    name: 'Registrar saida',
    credentials: modelo.credentials,
    onError: 'continueRegularOutput',
    alwaysOutputData: true,
    retryOnFail: false,
  });
  console.log('  criado: Registrar saida');
} else {
  nos['Registrar saida'].parameters.query = QUERY;
  nos['Registrar saida'].parameters.options = { queryReplacement: REPL };
  console.log('  atualizado: Registrar saida');
}

// `Enviar Z-API` -> `Registrar saida` -> `Loop fotos`
const cz = wf.connections['Enviar Z-API'];
if (!cz || !cz.main || !cz.main[0]) throw new Error('conexao do Enviar Z-API mudou');
const jaNoMeio = cz.main[0].some((c) => c.node === 'Registrar saida');
if (jaNoMeio) {
  console.log('  (ja aplicado) Enviar Z-API -> Registrar saida');
} else {
  if (!cz.main[0].some((c) => c.node === 'Loop fotos')) {
    throw new Error('Enviar Z-API nao volta para o Loop fotos; nao vou adivinhar');
  }
  wf.connections['Enviar Z-API'] = { main: [[{ node: 'Registrar saida', type: 'main', index: 0 }]] };
  wf.connections['Registrar saida'] = { main: [[{ node: 'Loop fotos', type: 'main', index: 0 }]] };
  console.log('  Enviar Z-API -> Registrar saida -> Loop fotos');
}

// `Registrar envio` para de gravar: o par codigo/ID que ele montava era
// justamente o errado. Fica como no-op para nao mexer na forma do fluxo.
const re = nos['Registrar envio'];
if (re.parameters.query.includes('no-op')) {
  console.log('  (ja aplicado) Registrar envio');
} else {
  re.parameters.query =
    "-- no-op desde 01/09. Este no gravava em `envios` o codigo do PRIMEIRO\n" +
    "-- card com o message_id do ULTIMO (medido na execucao 3768: codigo 1125\n" +
    "-- com o ID do 5643). Quem grava agora e o `Registrar saida`, dentro do\n" +
    "-- laco, onde o codigo e o ID sao da mesma mensagem.\n" +
    "SELECT $1::int AS codigo_ignorado, $2::text AS telefone, $3::text AS id_ignorado;";
  console.log('  Registrar envio: virou no-op (gravava o par errado)');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
