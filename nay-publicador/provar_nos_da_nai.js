// Prova o roteador da NAI: comando do Tel tem que ir para o fluxo ANTIGO.
//
// POR QUE EXISTE (23/09): `provar_nos_do_envio.js` roda contra a topologia da
// NAY ANTIGA -- `Rotear para o agente`, `Juntar mensagens`. A NAI tem outros
// nos, e por isso os nos DELA nunca foram provados por nada. Foi ali que
// "envia 92 99462-9241 codigo 150" escapou: `ehComandoAntigo` nao reconheceu,
// a frase seguiu para o agente da NAI, e ele respondeu ao Tel sobre o Tel
// ("o corretor Tel Sobreira pediu fotos do 150"). O imovel nao saiu.
//
// O no decisivo e `Rotear pelo cabecalho`: quem devolve `rota: 'tel_antigo'`
// manda a frase para o publicador; quem nao devolve, manda para o modelo.
//
//   node provar_nos_da_nai.js <workflow-da-nai.json>
const fs = require('fs');
const arquivo = process.argv[2];
if (!arquivo) { console.error('uso: node provar_nos_da_nai.js <nai.json>'); process.exit(2); }
const bruto = JSON.parse(fs.readFileSync(arquivo, 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

let falhas = 0;
function checar(t, cond, det) {
  if (!cond) falhas++;
  console.log('  ' + (cond ? 'OK  ' : 'FALHOU') + ' ' + t +
              (cond || !det ? '' : '  <- ' + det));
}

// O `$` de mentira. `cab` vem de `Abrir turno`, nao de `Juntar mensagens` --
// entregar o objeto errado faz o no falhar FECHADO (`cab.ok !== true`) e o
// teste acusar falha que nao existe.
function rotear(texto, cab) {
  const c = nos['Rotear pelo cabeçalho'].parameters.jsCode;
  const fake = {
    'Juntar mensagens': { first: () => ({ json: { texto: texto } }) },
    'Abrir turno': { first: () => ({ json: { cab: Object.assign(
      { ok: true, papel: 'tel', texto: texto, comando_nai: false,
        pausado: false, atende: true, teste: false }, cab || {}) } }) },
  };
  const fn = new Function('$', 'return (function(){' + c + '\n})()');
  try { return fn.call({}, (n) => fake[n] || { first: () => ({ json: {} }) }); }
  catch (e) { return 'ERRO: ' + e.message; }
}

const rota = (r) => (Array.isArray(r) && r[0] && r[0].json ? r[0].json.rota : null);

console.log('--- comando do Tel vai para o fluxo ANTIGO (o publicador) ---');
for (const frase of [
  'envia 92 99462-9241  codigo 150',   // a frase exata de 23/09, 19:58
  'envia 92 99462-9241 codigo 150',
  'Nay envia 92 99462-9241 cod 150',
  'manda 92 99462-9241 codigo 45',     // o unico imovel de 2 digitos
  'envia 5592994629241 codigo 150',    // como o banco guarda o numero
  'envia 92 9383-0696 o 2659',
  'envia (92) 98478-7190 o 3210',
  // TELEFONE ANTES DO VERBO (Tel, 24/09, duas vezes em minutos). O no so
  // DETECTA; quem reescreve para a forma canonica e o interpretar_comando.
  '92 9454-0289 ennvia todos os apartamentos no condominio verona para este número',
  '92 9951-9275 envia para ela o amazonas flat para locação de 2k',
  '92 9951-9275 manda pra ele o 5737',
  '92 9454-0289 mannda o 3827 e o 3921',
  // O GRUPO ALTO PADRAO (Tel, 25/09). Nasceu morto no `Comando do Tel`: o
  // NAO_PESSOA_RE contem `grupos?` e descarta de proposito.
  'Nay envia para o grupo alto padrão 4567',
  'posta no grupo alto padrão 4567',
  'Nay publica no alto padrão easy o 4567',
  'Nay manda o 5750 pro Sergio',       // a forma com preposicao, de sempre
  'Posta no grupo anunciar easy 3227',
  // O GRUPO COMERCIAL (Tel, 27/09). Mesma familia do alto padrao: se o
  // roteador nao reconhecer, a frase vai ao modelo e o imovel nao sai.
  'posta no grupo comercial 5763',
  'Nay posta no grupo comercial o 5763',
  'posta 5763 no grupo comercial',
  'posta lista de sala comercial no grupo comercial',
  'posta lista de sala comercial para locação no grupo comercial',
  'posta lista de sala comercial para locação no grupo comercial todo dia as 08h',
]) {
  checar('"' + frase + '"', rota(rotear(frase)) === 'tel_antigo',
         JSON.stringify(rotear(frase)).slice(0, 120));
}

console.log();
console.log('--- e o que NAO e comando segue para a NAI ---');
for (const frase of ['bom dia Nay', 'tem algo no Aleixo?',
                     'envia 92 99462-9241 45', 'envia 92 99462-9241 os 2',
                     // telefone sozinho, sem verbo de envio: e so um numero
                     '92 9951-9275 bom dia', '92 9951-9275 é o número dela']) {
  checar('"' + frase + '"', rota(rotear(frase)) !== 'tel_antigo',
         JSON.stringify(rotear(frase)).slice(0, 120));
}

console.log();
console.log('--- as paredes do cabecalho, ainda de pe ---');
// Todo portao deste projeto falha FECHADO: so passa quem prova que pode.
checar('sem cabecalho, nada sai',
       Array.isArray(rotear('envia 92 99462-9241 codigo 150', { ok: false })) &&
       rotear('envia 92 99462-9241 codigo 150', { ok: false }).length === 0);
checar('cabecalho indefinido tambem nao passa',
       rotear('envia 92 99462-9241 codigo 150', { ok: undefined }).length === 0);
// Comando da NAI (VISITA, ACESSO...) tem rota propria e nao pode ser roubado.
checar('comando da NAI continua indo para a NAI',
       rota(rotear('VISITA 1039 OK', { comando_nai: true })) === 'tel_nai');

console.log();
if (falhas) { console.log(falhas + ' FALHARAM'); process.exit(1); }
console.log('OS NOS DA NAI PASSARAM');
