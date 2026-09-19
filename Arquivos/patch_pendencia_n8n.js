// "descarta 47" passa a ser entendido, nos DOIS nos.
//
// O CASO (01/09, 13h18): o Tel escreveu "descarta 47" e a gramatica so
// conhecia "DESCARTAR". Caiu no agente, que leu o 47 como codigo de
// imovel: "o 47 tem so dois digitos, me passa o codigo completo". Ele
// repetiu tres vezes.
//
// A fonte das variacoes e `regex_pendencia.js` no repo, com 45 casos em
// `casos_comando_pendencia.json`. Este patch cola o MESMO bloco nos dois
// nos que precisam dele -- `Comando do Tel` (executa) e `Rotear para o
// agente` (descarta, senao o Tel recebe resposta dupla).
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const achar = (n) => { const x = wf.nodes.find((y) => y.name === n); if (!x) throw new Error(n); return x; };

// O bloco compartilhado, sem `module.exports` (nó do n8n não tem require).
const BLOCO = fs.readFileSync(process.argv[4], 'utf8')
  .split('if (typeof module')[0]
  .replace(/^\/\/[^\n]*\n/gm, '')      // tira o cabeçalho de comentário
  .trim();

// ---------- Comando do Tel: entende as variacoes ----------
const cmd = achar('Comando do Tel');
if (cmd.parameters.jsCode.includes('ehComandoDePendencia')) {
  console.log('  (ja aplicado) Comando do Tel');
} else {
  const antigo = [
    "  let m = linha.match(/^RESPOSTA\\s+(\\d+)\\s+([\\s\\S]+)$/i);",
    "  if (m) return [{ json: { acao: 'RESPOSTA', p_id: parseInt(m[1],10), p_texto: m[2].trim(), tel_tel: TEL } }];",
  ].join('\n');
  if (!cmd.parameters.jsCode.includes("match(/^RESPOSTA")) throw new Error('ancora do Comando do Tel mudou');
  // Injeta o bloco no topo e troca o trecho de RESPOSTA/DESCARTAR por uma
  // chamada unica, mantendo o resto do no intacto.
  let c = cmd.parameters.jsCode;
  c = BLOCO + '\n\n' + c;
  c = c.replace(/ {2}let m = linha\.match\(\/\^RESPOSTA[\s\S]*?if \(up === 'DESCARTAR TUDO'\) return \[\{ json: \{ acao: 'DESCARTAR TUDO', p_id: null, p_texto: null, tel_tel: TEL \} \}\];/,
    "  // A gramatica de pendencia mora em regex_pendencia.js, com 45 casos\n" +
    "  // em casos_comando_pendencia.json. 'descarta 47' e 'esquece 47' sao\n" +
    "  // formas que o Tel usa de verdade.\n" +
    "  const pend = interpretarPendencia(linha);\n" +
    "  if (pend) return [{ json: { acao: pend.acao, p_id: pend.p_id, p_texto: pend.p_texto, tel_tel: TEL } }];");
  if (c.includes("match(/^RESPOSTA")) throw new Error('a substituicao do Comando do Tel nao pegou');
  cmd.parameters.jsCode = c;
  console.log('  Comando do Tel: entende as variacoes');
}

// ---------- Rotear para o agente: descarta as mesmas ----------
const rot = achar('Rotear para o agente');
if (rot.parameters.jsCode.includes('ehComandoDePendencia')) {
  console.log('  (ja aplicado) Rotear para o agente');
} else {
  // A ancora tem "PENDÊNCIAS" com acento, que nao bate por igualdade
  // literal vindo do JSON exportado. Casa por padrao.
  const de = /if \(ehTel && \/\^\(RESPOSTA\|DESCARTAR[^;]*?\) return \[\];/;
  if (!de.test(rot.parameters.jsCode)) throw new Error('ancora do Rotear mudou');
  rot.parameters.jsCode = BLOCO + '\n\n' + rot.parameters.jsCode.replace(de,
    "// MESMA gramatica do `Comando do Tel`, colada de regex_pendencia.js.\n" +
    "// Divergir aqui faz o Tel receber resposta dupla, ou o comando morrer\n" +
    "// em silencio -- foi o que aconteceu com 'descarta 47' em 01/09.\n" +
    "if (ehTel && ehComandoDePendencia(t)) return [];");
  console.log('  Rotear para o agente: descarta as mesmas');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
