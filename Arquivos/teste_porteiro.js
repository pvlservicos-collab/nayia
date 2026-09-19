/*
 * Decisao do PORTEIRO -- quem a Nay atende.
 *
 * VERSAO QUE FALHA FECHADA (30/08). A anterior tinha um buraco:
 *
 *   if (!g.aprovado && Number(g.msgs_antes || 0) > 0) return [];
 *
 * Com `g` vazio -- referencia falhando, formato inesperado, campo ausente --
 * `Number(undefined) > 0` da FALSO e a porta ABRIA. Porteiro que nao sabe
 * quem esta na frente tem que dizer nao, nao sim. Os seis ultimos casos
 * deste arquivo sao exatamente as formas que passavam antes.
 *
 * Descoberto investigando por que uma cliente (nao corretora, 71 mensagens)
 * apareceu tendo sido atendida. Ver HISTORICO-APRENDIZADO.md.
 *
 * Uso (precisa do Node do container):
 *   scp teste_porteiro.js root@SERVIDOR:/tmp/p.js
 *   ssh root@SERVIDOR 'docker cp /tmp/p.js n8n-viux-n8n-1:/tmp/p.js \
 *     && docker exec n8n-viux-n8n-1 node /tmp/p.js'
 */
// Porteiro que falha FECHADA. O buraco anterior: com `g` vazio,
// `Number(undefined) > 0` da falso e a porta abria.
function decidir(g, ehTel) {
  const aprovado = g.aprovado === true;
  const primeiraVez = g.msgs_antes === 0;
  const pausado = g.pausado !== false;
  if (pausado && !ehTel) return 'bloqueado(pausa)';
  if (!aprovado && !primeiraVez) return 'bloqueado';
  if (!aprovado) return 'cortesia';
  return 'atende';
}

const casos = [
  ['corretor aprovado',            {aprovado:true,  msgs_antes:42, pausado:false}, false, 'atende'],
  ['desconhecido, 1a mensagem',    {aprovado:false, msgs_antes:0,  pausado:false}, false, 'cortesia'],
  ['CASO REAL Fernanda (71 msgs)', {aprovado:false, msgs_antes:70, pausado:false}, false, 'bloqueado'],
  ['pausado, corretor aprovado',   {aprovado:true,  msgs_antes:42, pausado:true},  false, 'bloqueado(pausa)'],
  ['pausado, mas e o Tel',         {aprovado:true,  msgs_antes:42, pausado:true},  true,  'atende'],

  // O BURACO: antes, todos estes ABRIAM a porta.
  ['g vazio',                      {},                                              false, 'bloqueado(pausa)'],
  ['sem msgs_antes',               {aprovado:false, pausado:false},                 false, 'bloqueado'],
  ['msgs_antes nulo',              {aprovado:false, msgs_antes:null, pausado:false}, false, 'bloqueado'],
  ['msgs_antes texto',             {aprovado:false, msgs_antes:'0', pausado:false},  false, 'bloqueado'],
  ['aprovado como texto',          {aprovado:'true', msgs_antes:5, pausado:false},   false, 'bloqueado'],
  ['pausado ausente',              {aprovado:true,  msgs_antes:5},                   false, 'bloqueado(pausa)'],
];

let falhas = 0;
for (const [rotulo, g, ehTel, esperado] of casos) {
  const obtido = decidir(g, ehTel);
  const ok = obtido === esperado;
  if (!ok) falhas++;
  console.log(`${ok ? 'OK  ' : 'FALHOU'}  ${rotulo.padEnd(30)} -> ${obtido}`);
}
console.log();
console.log(falhas === 0 ? `TODOS OS ${casos.length} PASSARAM` : `${falhas} FALHARAM`);
process.exit(falhas ? 1 : 0);
