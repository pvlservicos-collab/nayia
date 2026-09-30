/*
 * Roda a LOGICA REAL dos dois nos do n8n, direto do workflow exportado.
 *
 * POR QUE NAO SE CHAMA `teste_*.js`: ele precisa do JSON exportado do n8n,
 * que nao mora no repositorio -- se o `rodar_testes.sh` o descobrisse
 * sozinho, ficaria vermelho para sempre. E o passo de conferencia do deploy,
 * nao uma suite.
 *
 * POR QUE EXISTE: o CLAUDE.md registra que "JavaScript sintaticamente valido
 * quebra em execucao -- um `_` solto no fim de uma linha passou no
 * `node --check` e derrubou o no inteiro em producao". `--check` prova
 * sintaxe; isto prova COMPORTAMENTO, e contra o codigo que vai de verdade
 * para dentro do no.
 *
 * E ele compara os dois nos entre si, que e a unica coisa que segura o bug
 * mais caro deste projeto: `Comando do Tel` tem que ACEITAR exatamente o que
 * `Rotear para o agente` DESCARTA. Se um dos dois andar sozinho, ou o
 * comando morre calado, ou o Tel recebe resposta dupla.
 *
 * E prova a parede do outro lado tambem: a gramatica de comando vale SO para
 * o Tel. A MESMA frase vinda de um corretor tem que seguir para o agente --
 * foi o bug de 27/08, em que "Vaga de garagem?" era engolido pelos tres
 * ramos e o corretor nao recebia nada.
 *
 *   docker exec n8n-viux-n8n-1 n8n export:workflow --id=sQuiEjbEDMEbjX5U \
 *     --output=/tmp/wf.json
 *   node provar_nos_do_envio.js <workflow.json>
 */
const fs = require('fs');

const TEL = '559294717316';
const CORRETOR = '559288548030';

const arquivo = process.argv[2];
if (!arquivo || !fs.existsSync(arquivo)) {
  console.error('uso: node provar_nos_do_envio.js <workflow exportado.json>');
  process.exit(1);
}
const bruto = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

function corpo(nome) {
  if (!nos[nome]) { console.error('no ' + nome + ' nao existe'); process.exit(1); }
  return nos[nome].parameters.jsCode;
}

// O `$` de mentira. O porteiro le `aprovado`/`msgs_antes`/`pausado` do
// `Gravar na fila`, nao do `Juntar mensagens` -- entregar o objeto errado faz
// o porteiro falhar FECHADO e o teste acusar falha que nao existe. Aconteceu
// na primeira versao deste arquivo.
function contexto(texto, telefone, o) {
  o = o || {};
  const j = { telefone: telefone || TEL, texto, perguntaAberta: o.perguntaAberta === true };
  const g = { aprovado: o.aprovado !== false, msgs_antes: o.msgs_antes ?? 0,
              pausado: o.pausado === true };
  return (nome) => {
    const alvo = nome === 'Gravar na fila' ? g : j;
    return { first: () => ({ json: alvo }), all: () => [{ json: alvo }] };
  };
}

// `Comando do Tel` e async e faz `await this.helpers.httpRequest`.
async function comando(texto, telefone, o) {
  const posts = [];
  const ctx = { helpers: { httpRequest: async (x) => { posts.push(x); } } };
  const fn = new Function('$', 'return (async function(){' + corpo('Comando do Tel') + '\n}).call(this)');
  await fn.call(ctx, contexto(texto, telefone, o));
  return posts;
}

function rotear(texto, telefone, o) {
  const fn = new Function('$', '$getWorkflowStaticData',
    'return (function(){' + corpo('Rotear para o agente') + '\n})()');
  try {
    return fn.call({}, contexto(texto, telefone, o), () => ({}));
  } catch (e) {
    return 'ERRO: ' + e.message;
  }
}

// `Achar codigo na resposta` e a QUARTA copia da gramatica: ele roda uma regex
// na resposta DELA e, se achar codigo, busca as fotos e envia. O guarda de
// comando existe para o texto do PROPRIO Tel nunca chegar ali -- senao "Nay
// envia as FOTOS do 5750 pro Sergio" manda as fotos para o chat dele.
// `codigo: '0'` e como o no diz "nao dispare foto nenhuma".
function acharNaResposta(escreveu, resposta) {
  const fn = new Function('$input', '$',
    'return (function(){' + corpo('Achar codigo na resposta') + '\n})()');
  try {
    return fn.call({},
      { first: () => ({ json: { output: resposta || 'ok' } }) },
      () => ({ first: () => ({ json: { texto: escreveu, textoCru: escreveu,
                                       citado: '' } }) }));
  } catch (e) { return 'ERRO: ' + e.message; }
}

// `Achar codigo` e o terceiro no que precisa concordar desde 15/09: com
// pergunta aberta ao Tel, o numero sozinho e RESPOSTA, nao pedido de card.
function acharCodigo(texto, telefone, o) {
  const fn = new Function('$', 'return (function(){' + corpo('Achar codigo') + '\n})()');
  try {
    return fn.call({}, contexto(texto, telefone, o));
  } catch (e) {
    return 'ERRO: ' + e.message;
  }
}

let falhas = 0;
function checar(titulo, cond, detalhe) {
  if (!cond) falhas++;
  console.log(`  ${cond ? 'OK  ' : 'FALHOU'} ${titulo}`);
  if (!cond && detalhe) console.log('         ' + detalhe);
}
const vazio = (r) => Array.isArray(r) && r.length === 0;
const passou = (r) => Array.isArray(r) && r.length > 0;

const LISTA = `Nay envia esses imóveis para o número 92994717316

Arezzo Residencial / 2 quartos / 2.5k
Ariranhas / 2 quartos / 2.6k (incluso a tx)
Estilo Golf / 2 quartos sendo 1 suíte / 2.6k
Estilo Golf / 2 quartos sendo 1 suíte / 2.6k`;

(async () => {
  console.log('--- `Comando do Tel`: a lista vai INTEIRA ---');
  let p = await comando(LISTA);
  checar('dispara um post so', p.length === 1);
  checar('e manda o TEXTO INTEIRO, nao a primeira linha',
         p[0] && p[0].body.texto === LISTA,
         'mandou: ' + JSON.stringify(p[0] && p[0].body.texto));
  // ~50-60s por imovel com fotos; quatro passam dos 120s dos outros ramos.
  checar('com timeout de 10 min', p[0] && p[0].timeout === 600000,
         'timeout: ' + (p[0] && p[0].timeout));

  p = await comando('Nay codigo 5719');
  checar('a escolha de codigo chega ao publicador',
         p.length === 1 && p[0].body.texto === 'Nay codigo 5719');
  p = await comando('Nay codigo 5719 e 5728');
  checar('com dois codigos tambem', p.length === 1);

  console.log();
  console.log('--- TELEFONE NA FRENTE, com e sem a palavra CODIGO ---');
  // Ele escreveu "envia 92 99462-9241  codigo 150" em 23/09 as 19:58. Nenhuma
  // das copias reconheceu, a frase foi ao agente e ele recebeu resposta sobre
  // si mesmo ("o corretor Tel Sobreira pediu fotos do 150"). O imovel nao saiu.
  //
  // MEDIDO no catalogo: 1 imovel de 2 digitos (o 45), 14 de 3, 1.238 de 4.
  for (const frase of ['envia 92 99462-9241  codigo 150',
                       'envia 92 99462-9241 codigo 150',
                       'Nay envia 92 99462-9241 cod 150',
                       'manda 92 99462-9241 codigo 45',
                       'envia 5592994629241 codigo 150',
                       'envia 92 9383-0696 o 2659',
                       'envia (92) 98478-7190 o 3210',
                       // TELEFONE ANTES DO VERBO (Tel, 24/09)
                       '92 9454-0289 ennvia todos os apartamentos no condominio verona para este número',
                       '92 9951-9275 envia para ela o amazonas flat para locação de 2k',
                       '92 9951-9275 manda pra ele o 5737',
                       '92 9454-0289 mannda o 3827 e o 3921',
                       // O GRUPO ALTO PADRAO (Tel, 25/09)
                       'Nay envia para o grupo alto padrão 4567',
                       'Nay publica no alto padrão easy o 4567',]) {
    const p = await comando(frase);
    checar(`comando aceita ${JSON.stringify(frase)}`, p.length === 1,
           JSON.stringify(p).slice(0, 120));
    checar(`  e o agente descarta`, vazio(rotear(frase)),
           JSON.stringify(rotear(frase)).slice(0, 120));
    // O caminho de codigo puro descarta: a frase nao e "5719".
    checar(`  e o caminho de codigo puro descarta`, vazio(acharCodigo(frase, TEL)),
           JSON.stringify(acharCodigo(frase, TEL)).slice(0, 120));
    // A QUARTA copia: o texto DELE nunca pode disparar o gatilho de fotos.
    const ar = acharNaResposta(frase, 'Mandei o imovel. Código: 150');
    checar(`  e nao dispara foto para o chat dele`,
           Array.isArray(ar) && ar.length === 1 && ar[0].json.codigo === '0',
           JSON.stringify(ar).slice(0, 140));
  }

  console.log();
  console.log('--- mas dois digitos SEM a palavra continuam fora ---');
  // "os 2" e a escolha da lista (12/09). Sem o marcador, o minimo e tres.
  for (const frase of ['envia 92 99462-9241 45', 'envia 92 99462-9241 o 45']) {
    const p = await comando(frase);
    checar(`${JSON.stringify(frase)} nao vira envio`, p.length === 0,
           JSON.stringify(p).slice(0, 120));
  }

  console.log();
  console.log('--- A RESPOSTA NATURAL (o bug de 12/09) ---');
  // Ele respondeu "os dois" e a frase caiu no AGENTE, que devolveu uma lista
  // de imoveis sem nexo. A propria pergunta dela dizia "ou os dois".
  for (const frase of ['os dois', 'os 2', 'ambos', 'as duas', 'todos',
                       'manda os dois', 'quero os dois', 'sim, os dois',
                       'os dois estilo golf', 'o primeiro', 'o ultimo',
                       '5719 e 5728']) {
    const p = await comando(frase);
    checar(`comando aceita ${JSON.stringify(frase)}`, p.length === 1);
    checar(`  e o agente descarta`, vazio(rotear(frase)),
           JSON.stringify(rotear(frase)).slice(0, 120));
  }

  console.log();
  console.log('--- e o que NAO pode virar escolha ---');
  // "sim"/"isso" sozinhos: ele usa "isso" como confirmacao generica, e com
  // uma lista em aberto isso mandaria a carteira sem ele pedir.
  // "sim"/"isso" sozinhos: a palavra que LIBERA a confirmacao do
  // `nay_responder_conversando`. Se virarem comando, ou a resposta da
  // pendencia morre calada, ou um "sim" dispara DOIS envios irreversiveis ao
  // mesmo tempo, porque os tres ramos do fluxo rodam em PARALELO.
  //
  // "tudo sim" e o pedaco que ele lembra do "DESCARTAR TUDO SIM".
  //
  // E AS PROPRIAS LINHAS DA LISTA: o no percorre linha por linha, e "2 quartos
  // sendo 1 suite / 2.6k" virava "manda dois" -- uma linha de PRECO
  // disparando o envio da carteira.
  for (const frase of ['sim', 'isso', 'ok', 'manda', 'pode', 'tudo', 'tudo sim',
                       'me manda os dois', '1', '2', '3',
                       '2 quartos sendo 1 suite / 2.6k', '3 quartos / 450k',
                       'duas suites', '2 vagas', '2.6k',
                       'os dois no grupo', 'manda os dois no easy']) {
    checar(`${JSON.stringify(frase)} NAO e comando`, (await comando(frase)).length === 0,
           JSON.stringify((await comando(frase)).map(x => x.body)));
  }
  // a COLISAO que a primeira versao causou: "envia" cabe no prefixo educado e
  // "todos" no quantificador, e a escolha roubava um comando de ENVIO.
  let pc = await comando('Nay envia todos os acquarelle para locacao para o corretor Sergio');
  checar('envio com destinatario vai como LINHA, nao como escolha',
         pc.length === 1 && pc[0].timeout === 120000,
         'timeout: ' + (pc[0] && pc[0].timeout));
  // E A LISTA, que dispara em 13 grupos, nunca pode ser lida como escolha.
  // Ela cai no ramo do ENVIO_RE (o "para locacao" vira cauda) e vai como
  // LINHA, com o timeout de 120s -- comportamento igual antes e depois do
  // patch, conferido. Quem a interpreta como `disparar_lista` e o Python.
  // O que importa aqui e que NAO foi para o ramo da lista colada, que manda o
  // texto inteiro com 10 minutos.
  pc = await comando('Nay dispara apartamentos para locacao');
  checar('a lista de categoria nao vira escolha nem lista colada',
         pc.length === 1 && pc[0].timeout !== 600000
           && pc[0].body.texto === 'Nay dispara apartamentos para locacao',
         'timeout: ' + (pc[0] && pc[0].timeout));

  console.log();
  console.log('--- "sim" SO com pergunta aberta (14/09) ---');
  // Ele pediu para postar de novo no Easy, ela perguntou, ele diz "sim". Sem a
  // pergunta, o "sim" e conversa -- e foi exatamente o "Pode postar novamente"
  // indo ao agente que deixou ele sem resposta.
  const ABERTA = { perguntaAberta: true };
  for (const frase of ['sim', 'Pode postar novamente', 'pode sim', 'não precisa', 'ok']) {
    const pp = await comando(frase, TEL, ABERTA);
    checar(`com pergunta: ${JSON.stringify(frase)} vai ao publicador`,
           pp.length === 1 && pp[0].body.texto === frase && pp[0].timeout === 600000,
           JSON.stringify(pp.map(x => [x.body, x.timeout])));
    checar('  e o agente descarta', vazio(rotear(frase, TEL, ABERTA)));
  }
  let ps = await comando('sim', TEL, { perguntaAberta: false });
  checar('SEM pergunta, "sim" nao e comando', ps.length === 0);
  checar('  e segue para o agente', passou(rotear('sim', TEL, { perguntaAberta: false })));
  ps = await comando('sim', CORRETOR, ABERTA);
  checar('"sim" de CORRETOR nunca vira comando', ps.length === 0);
  checar('  e segue para o agente (bug de 27/08)', passou(rotear('sim', CORRETOR, ABERTA)));
  // duas mensagens juntadas pela janela: tem um comando dentro, nao e resposta
  ps = await comando('sim\nposta o 5750', TEL, ABERTA);
  checar('"sim" + comando juntos nao e resposta',
         !ps.some(x => x.body.texto === 'sim') && ps.some(x => /posta o 5750/.test(x.body.texto)),
         JSON.stringify(ps.map(x => x.body)));
  ps = await comando('Pode postar o 5750 amanha?', TEL, ABERTA);
  checar('frase com mais coisa nao e resposta', !ps.some(x => x.timeout === 600000));

  console.log();
  console.log('--- o PEDIDO DESCRITO com faixa de valor (15/09) ---');
  // As formas que o Tel escreveu, com o destinatario no fim. O que se prova
  // aqui e o CAMINHO: a frase chega inteira ao publicador com o timeout de
  // envio, e o agente nao responde por cima. A resolucao contra o catalogo
  // e provada no servidor (`pedido_de_imoveis`), nao aqui.
  //
  // O "para" DO MEIO e a armadilha: "casa PARA venda ... PARA 92 9947-1731"
  // tem dois, e o destinatario e o ULTIMO. Com o casador guloso e o ultimo
  // que vale -- e e por isso que a frase SEM destinatario nenhum nao pode
  // ser mandada: ali o unico "para" e o de "para venda", e o destino viraria
  // "venda em condominio de 250 mil a 600 mil...".
  for (const frase of [
    'Nay envia locação de 3k a 6k nos bairros parque dez, flores e compensa para 92 9947-1731',
    'Nay envia locação de 3 mil a 6 mil nos bairros parque dez e flores para o corretor Sergio 92 9947-1731',
    'Nay envia casa para venda em condomínio de 250 mil a 600 mil nos bairros parque dez para 92 9947-1731',
    'Nay envia casa em condomínio de 250 mil a 600 mil no parque dez para 92 9947-1731',
    'Nay envia casa em condomínio de 250k a 600k no parque dez para 92 9947-1731',
    'Nay envia imóvel comercial para venda de 200 mil a 900 mil para 92 9947-1731',
    'Nay envia imóvel comercial para locação até 5 mil para 92 9947-1731',
    'Nay envia imóvel residencial para venda de 250k a 600k no parque dez para 92 9947-1731',
    'Nay envia locação a partir de 6 mil no ponta negra para 92 9947-1731',
  ]) {
    const pd = await comando(frase);
    checar(`chega inteiro: ${JSON.stringify(frase.slice(10, 58))}`,
           pd.length === 1 && pd[0].body.texto === frase,
           JSON.stringify(pd.map((x) => x.body.texto)));
    checar('  e o agente descarta', vazio(rotear(frase)),
           JSON.stringify(rotear(frase)).slice(0, 120));
  }

  console.log();
  console.log('--- o pedido SEM destinatario nenhum (15/09) ---');
  // Nao tem "para": nao casa o ENVIO_RE, e "locacao" nao esta na lista de
  // substantivos do ramo de categoria. Ia inteiro para o AGENTE.
  for (const frase of [
    'Nay envia locação de 3k a 6k nos bairros parque dez, flores e compensa',
    'Nay envia locação de 3 mil a 6 mil nos bairros parque dez, flores e compensa',
    'Nay envia casa em condomínio de 250k a 600k nos bairros parque dez',
    'Nay envia casa em condomínio de 250 mil a 600 mil nos bairros parque dez',
    'Nay envia locação até 2800 no parque dez',
    'Nay envia locação a partir de 6 mil no ponta negra',
  ]) {
    const ps = await comando(frase);
    checar(`chega ao publicador: ${JSON.stringify(frase.slice(10, 52))}`,
           ps.length === 1 && ps[0].body.texto === frase,
           JSON.stringify(ps.map((x) => x.body.texto)));
    checar('  e o agente NAO responde por cima', vazio(rotear(frase)),
           JSON.stringify(rotear(frase)).slice(0, 120));
    checar('  mas de CORRETOR segue para o agente',
           (await comando(frase, CORRETOR)).length === 0 && passou(rotear(frase, CORRETOR)));
  }

  console.log();
  console.log('--- `posta <nome do condominio>` chega inteiro (15/09) ---');
  for (const frase of ['Posta o jardim das cerejeiras',
                       'Nay publica o jardim das cerejeiras para locação',
                       'posta o jardim das cerejeiras para locação',
                       'posta para locação o jardim das cerejeiras',
                       'posta o morada dos pássaros para venda']) {
    const pn = await comando(frase);
    checar(`chega ao publicador: ${JSON.stringify(frase.slice(0, 46))}`,
           pn.length === 1 && pn[0].body.texto === frase,
           JSON.stringify(pn.map((x) => x.body.texto)));
    checar('  e o agente descarta', vazio(rotear(frase)),
           JSON.stringify(rotear(frase)).slice(0, 120));
  }

  console.log();
  console.log('--- a resposta a pergunta do `posta <nome>` (15/09) ---');
  // Com pergunta aberta, "locacao" e "5725" sao RESPOSTA: vao ao publicador,
  // o agente nao responde por cima, e o card nao sai no privado dele.
  const ABERTA2 = { perguntaAberta: true };
  for (const frase of ['locação', 'venda', '5725', '3.6k', 'o de 3.6k', 'aluguel']) {
    const pe = await comando(frase, TEL, ABERTA2);
    checar(`com pergunta: ${JSON.stringify(frase)} vai ao publicador`,
           pe.length === 1 && pe[0].body.texto === frase,
           JSON.stringify(pe.map((x) => [x.body, x.timeout])));
    checar('  com tempo para postar (a resposta dispara o envio)',
           pe[0] && pe[0].timeout === 600000, 'timeout: ' + (pe[0] && pe[0].timeout));
    checar('  e o agente descarta', vazio(rotear(frase, TEL, ABERTA2)));
  }
  checar('o card NAO sai no privado dele com pergunta aberta',
         vazio(acharCodigo('5725', TEL, ABERTA2)),
         JSON.stringify(acharCodigo('5725', TEL, ABERTA2)));

  // SEM pergunta, nada muda: "5725" continua trazendo o card, "venda" continua
  // sendo conversa que vai ao agente.
  const FECHADA = { perguntaAberta: false };
  checar('sem pergunta, "5725" nao e comando', (await comando('5725', TEL, FECHADA)).length === 0);
  checar('  e continua trazendo o card', passou(acharCodigo('5725', TEL, FECHADA)));
  checar('sem pergunta, "venda" nao e comando', (await comando('venda', TEL, FECHADA)).length === 0);
  checar('  e segue para o agente', passou(rotear('venda', TEL, FECHADA)));
  // E DE CORRETOR nunca: o card dele continua saindo, e a palavra vai ao agente.
  checar('"5725" de corretor continua trazendo o card',
         passou(acharCodigo('5725', CORRETOR, ABERTA2)));
  checar('"venda" de corretor segue para o agente',
         passou(rotear('venda', CORRETOR, ABERTA2)));
  checar('  e nao vira comando', (await comando('venda', CORRETOR, ABERTA2)).length === 0);

  console.log();
  console.log('--- os caminhos ANTIGOS, sem regressao ---');
  p = await comando('Nay manda o 5750 pro Sergio');
  checar('envio por codigo manda so a linha',
         p.length === 1 && p[0].body.texto === 'Nay manda o 5750 pro Sergio');
  checar('e com o timeout de sempre', p[0] && p[0].timeout === 120000);
  checar('VAGAS continua indo', (await comando('Nay VAGAS')).length === 1);
  checar('agenda de visitas continua indo',
         (await comando('agenda de visitas')).length === 1);
  checar('ALUGOU continua indo', (await comando('Nay ALUGOU 5750')).length === 1);
  checar('codigo puro NAO e comando', (await comando('5719')).length === 0);
  checar('conversa NAO e comando', (await comando('bom dia')).length === 0);
  checar('nada do que nao e o Tel virá comando',
         (await comando(LISTA, CORRETOR)).length === 0);

  console.log();
  console.log('--- `Rotear para o agente` DESCARTA o que o outro aceita ---');
  checar('a lista', vazio(rotear(LISTA)));
  checar('a escolha de codigo', vazio(rotear('Nay codigo 5719')),
         JSON.stringify(rotear('Nay codigo 5719')).slice(0, 160));
  checar('com dois codigos', vazio(rotear('Nay codigo 5719 e 5728')));
  checar('o envio por codigo', vazio(rotear('Nay manda o 5750 pro Sergio')));
  checar('o VAGAS', vazio(rotear('Nay VAGAS')));

  console.log();
  console.log('--- e NAO silencia corretor (o bug de 27/08) ---');
  checar('pergunta comum segue ao agente',
         passou(rotear('tem algo no Aleixo?', CORRETOR)));
  checar('"Vaga de garagem?" segue', passou(rotear('Vaga de garagem?', CORRETOR)));
  // A gramatica de comando vale SO para o Tel: a mesma frase de um corretor
  // nao pode ser engolida, senao ele fala e ninguem responde.
  checar('"Nay codigo 5719" de corretor segue',
         passou(rotear('Nay codigo 5719', CORRETOR)),
         JSON.stringify(rotear('Nay codigo 5719', CORRETOR)).slice(0, 160));
  checar('lista colada por corretor segue', passou(rotear(LISTA, CORRETOR)));

  console.log();
  console.log('--- as paredes do porteiro, ainda de pe ---');
  checar('pausado: corretor nao passa', vazio(rotear('oi', CORRETOR, {pausado: true})));
  checar('pausado: o Tel ainda passa', passou(rotear('oi', TEL, {pausado: true})));
  checar('desconhecido reincidente nao passa',
         vazio(rotear('oi', CORRETOR, {aprovado: false, msgs_antes: 3})));
  checar('desconhecido na PRIMEIRA mensagem passa',
         passou(rotear('oi', CORRETOR, {aprovado: false, msgs_antes: 0})));

  console.log();
  if (falhas) { console.log(falhas + ' FALHARAM'); process.exit(1); }
  console.log('OS DOIS NOS CONCORDAM');
})();
