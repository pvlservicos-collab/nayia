// `listar_no_condominio` filtrava LOCACAO pelo valor de VENDA.
//
// A query usa `COALESCE(i.valor_venda, i.valor_aluguel)` para filtrar por
// teto, ordenar e marcar "(acima do teto)". Num imovel que esta a venda E
// para alugar, o valor de venda ganha -- entao o corretor que procura
// locacao no Condominio Karine com teto de R$ 6.000 nunca ve o 1966, que
// aluga por 5.500, porque a comparacao usa os 610.000 da venda.
//
// Sao 7 imoveis disponiveis e nossos com os dois valores, e sao alugueis
// altos: de R$ 5.500 a R$ 50.000 por mes. Achado na auditoria de 01/09.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;

const no = wf.nodes.find((x) => x.name === 'listar_no_condominio');
if (!no) throw new Error('no listar_no_condominio nao encontrado');

const VALOR_DO_NEGOCIO = "CASE WHEN $2 = 'locacao' THEN i.valor_aluguel ELSE i.valor_venda END";
const antes = 'COALESCE(i.valor_venda, i.valor_aluguel)';

if (no.parameters.query.includes(VALOR_DO_NEGOCIO)) {
  console.log('  (ja aplicado)');
} else {
  const n = no.parameters.query.split(antes).length - 1;
  if (n !== 4) throw new Error('esperava 4 ocorrencias, achei ' + n);
  no.parameters.query = no.parameters.query.split(antes).join(VALOR_DO_NEGOCIO);
  console.log('  listar_no_condominio: ' + n + ' comparacoes passam a usar o valor do negocio');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
