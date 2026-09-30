// O card de imóvel administrado passa a mostrar o endereço SEM o número.
//
// DECISÃO DO TEL (01/09): "casa não pode falar o número dela". Hoje o
// único imóvel administrado com logradouro é "Av. Curaçao", que não tem
// número -- mas 34 logradouros do catálogo têm, e o dia em que um desses
// virar administrado o número sai sozinho. A proteção fica na query, não
// na sorte do cadastro.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;

const no = wf.nodes.find((x) => x.name === 'imovel_por_codigo');
if (!no) throw new Error('imovel_por_codigo nao encontrado');

const de = "THEN E'\\n• Endereço: ' || i.logradouro ELSE '' END";
const para = "THEN E'\\n• Endereço: ' || nay_endereco_sem_numero(i.logradouro) ELSE '' END";

if (no.parameters.query.includes('nay_endereco_sem_numero')) {
  console.log('  (ja aplicado)');
} else {
  if (!no.parameters.query.includes(de)) throw new Error('ancora do endereco mudou');
  no.parameters.query = no.parameters.query.replace(de, para);
  console.log('  imovel_por_codigo: endereco sem o numero');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
