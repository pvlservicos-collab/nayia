// O card que a PROPRIA Nay manda tambem passa a guardar o message_id.
//
// Sem isto, o ciclo da citacao so fechava para o que o publicador manda
// (disparo de grupo e envio comandado pelo Tel). O caminho mais comum --
// ela responde e manda o card -- ficava de fora, e a citacao daquele card
// nao resolveria.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const achar = (n) => { const x = wf.nodes.find((y) => y.name === n); if (!x) throw new Error(n); return x; };

const pr = achar('Preparar registro');
if (pr.parameters.jsCode.includes('messageId')) {
  console.log('  (ja aplicado) Preparar registro');
} else {
  pr.parameters.jsCode = pr.parameters.jsCode.replace(
    'return [{ json: { codigo: codigo, telefone: tel } }];',
    '// O messageId do card que acabou de sair. E ele que volta em\n' +
    '// `referenceMessageId` quando o corretor MARCA esta mensagem, e e\n' +
    '// por igualdade com ele que a Nay descobre de qual imovel ele fala.\n' +
    '// try/catch porque nem todo caminho passa pelo Enviar Z-API.\n' +
    'let msgId = null;\n' +
    'try {\n' +
    "  const r = $('Enviar Z-API').first().json || {};\n" +
    '  msgId = r.messageId || r.id || r.zaapId || null;\n' +
    '} catch (e) { msgId = null; }\n' +
    'return [{ json: { codigo: codigo, telefone: tel, messageId: msgId } }];');
  console.log('  Preparar registro: colhe o messageId');
}

const re = achar('Registrar envio');
if (re.parameters.query.includes('message_id')) {
  console.log('  (ja aplicado) Registrar envio');
} else {
  re.parameters.query = re.parameters.query
    .replace('INSERT INTO envios (codigo, telefone, destino, valor_enviado)',
             'INSERT INTO envios (codigo, telefone, destino, valor_enviado, message_id)')
    .replace("SELECT i.codigo, $2::text, 'corretor', COALESCE(i.valor_venda, i.valor_aluguel, 0)",
             "SELECT i.codigo, $2::text, 'corretor', COALESCE(i.valor_venda, i.valor_aluguel, 0), NULLIF($3::text,'')");
  re.parameters.options = re.parameters.options || {};
  re.parameters.options.queryReplacement =
    "={{ [$json.codigo, $json.telefone, $json.messageId ?? null] }}";
  console.log('  Registrar envio: grava o message_id');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
