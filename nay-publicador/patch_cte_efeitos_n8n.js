// Os CTEs de efeito colateral do `Gravar na fila` nunca rodaram.
//
// O CASO (01/09): a Regiane conversa com a Nay ha dias e `corretores.nome`
// dela esta VAZIO -- embora `mensagens.nome` traga "Regiane Monteiro"
// desde a primeira mensagem, e `nay_sincronizar_nome` funcione quando
// chamada direto (provado no banco).
//
// A CAUSA: o Postgres NAO executa CTE de SELECT que ninguem referencia.
// O `Gravar na fila` tem
//     nomeia  AS (SELECT nay_sincronizar_nome(...))
//     congela AS (SELECT nay_congelar_lembretes(...))
// e o SELECT final le so `ins` e `antes`. Os dois nunca rodaram. (O
// `dbgimg` roda porque e um INSERT -- CTE que MODIFICA dado sempre
// executa; o de SELECT, nao.)
//
// CONSEQUENCIAS MEDIDAS: 967 corretores sem nome, e o comando "manda o
// 2014 pra Regiane" nao acha ninguem. E o congelamento de lembrete nunca
// rodou -- a tabela `lembrete` esta vazia hoje, entao ninguem foi cobrado
// depois de ja ter respondido, mas rodaria assim que ela fosse usada.
//
// O CONSERTO: referenciar os dois no SELECT final. Uma subconsulta
// escalar sobre o CTE forca a execucao e NAO pode mudar o numero de
// linhas -- diferente de por os CTEs no FROM, onde um deles voltando
// vazio zeraria o resultado inteiro e derrubaria toda mensagem.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const gr = wf.nodes.find((x) => x.name === 'Gravar na fila');
if (!gr) throw new Error('Gravar na fila nao encontrado');

if (gr.parameters.query.includes('efeitos_colaterais')) {
  console.log('  (ja aplicado)');
} else {
  const de = "       nay_codigos_citados(coalesce(NULLIF($4,'null'),'')) AS codigos_citados";
  if (!gr.parameters.query.includes(de)) throw new Error('ancora mudou');
  gr.parameters.query = gr.parameters.query.replace(de,
    de + ',\n' +
    "       -- OBRIGA os CTEs de efeito colateral a rodar. O Postgres nao\n" +
    "       -- executa CTE de SELECT que ninguem referencia, e por isso a\n" +
    "       -- sincronizacao de nome e o congelamento de lembrete NUNCA\n" +
    "       -- rodaram -- 967 corretores ficaram sem nome. Subconsulta\n" +
    "       -- escalar forca a execucao sem poder mudar o numero de linhas;\n" +
    "       -- por os CTEs no FROM zeraria o resultado quando um voltasse\n" +
    "       -- vazio, e ai TODA mensagem morreria aqui.\n" +
    "       (SELECT count(*) FROM nomeia) + (SELECT count(*) FROM congela)\n" +
    "         AS efeitos_colaterais");
  console.log('  Gravar na fila: os CTEs passam a rodar');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
