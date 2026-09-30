/*
 * Ordem de envio quando o corretor pede VARIOS imoveis -- no
 * `Preparar envio do agente`.
 *
 * O CASO (Gustavo, 30/08): ela listou tres imoveis, ele disse "me passa as
 * informacoes dos 3", e ela repetiu "qual codigo voce quer receber
 * primeiro?". Duas causas: a instrucao da lista mandava perguntar, e o
 * fluxo so sabia lidar com UM codigo -- os outros dois nao teriam fotos.
 *
 * Aqui se prova a ordem: CARD, fotos daquele imovel, proximo CARD. Jogar
 * tres textos e depois trinta fotos soltas nao diz de quem e cada foto.
 *
 * Uso (precisa do Node do container):
 *   scp teste_intercalar_envio.js root@SERVIDOR:/tmp/i.js
 *   ssh root@SERVIDOR 'docker cp /tmp/i.js n8n-viux-n8n-1:/tmp/i.js \
 *     && docker exec n8n-viux-n8n-1 node /tmp/i.js'
 */
// Espelha o `Preparar envio do agente` depois de 30/08: cada card sai
// seguido das fotos DAQUELE imovel, nao tres textos e trinta fotos soltas.
function montar(texto, linhas) {
  const saida = [];
  const porCodigo = new Map();
  for (const l of linhas) {
    const k = String(l.codigo);
    if (!porCodigo.has(k)) porCodigo.set(k, []);
    porCodigo.get(k).push(l.url);
  }
  const blocos = [];
  const re = /C[óo]digo:\s*(\d{3,5})/gi;
  let ini = 0, m;
  while ((m = re.exec(texto)) !== null) {
    const fim = m.index + m[0].length;
    blocos.push({ codigo: m[1], texto: texto.slice(ini, fim).trim() });
    ini = fim;
  }
  const resto = texto.slice(ini).trim();
  if (blocos.length === 0) {
    if (texto.trim()) saida.push('TEXTO: ' + texto.trim().slice(0, 30));
    for (const us of porCodigo.values()) for (const u of us) saida.push('FOTO ' + u);
  } else {
    for (const b of blocos) {
      if (b.texto) saida.push('CARD ' + b.codigo);
      for (const u of (porCodigo.get(b.codigo) || [])) saida.push('FOTO ' + u);
    }
    if (resto) saida.push('TEXTO FINAL');
  }
  return saida;
}

const TRES = 'Harmonia 4946\nCódigo: 4946\nHarmonia 3495\nCódigo: 3495\nHarmonia 3471\nCódigo: 3471\n\nqualquer duvida me chama';
const fotos3 = [
  {codigo:'4946',url:'a1'},{codigo:'4946',url:'a2'},
  {codigo:'3495',url:'b1'},
  {codigo:'3471',url:'c1'},{codigo:'3471',url:'c2'},
];

console.log('--- CASO REAL: os 3 do Gustavo, com fotos ---');
const r1 = montar(TRES, fotos3);
r1.forEach(x => console.log('   ' + x));
const ordemOk = JSON.stringify(r1) === JSON.stringify([
  'CARD 4946','FOTO a1','FOTO a2',
  'CARD 3495','FOTO b1',
  'CARD 3471','FOTO c1','FOTO c2',
  'TEXTO FINAL']);
console.log(ordemOk ? '   OK: cada card seguido das fotos dele' : '   FALHOU: ordem errada');

console.log('\n--- um imovel so, sem foto (consentimento nao veio) ---');
const r2 = montar('Harmonia\nCódigo: 3495\n\nquer as fotos?', []);
r2.forEach(x => console.log('   ' + x));
const semFoto = r2.filter(x => x.startsWith('FOTO')).length === 0 && r2.includes('CARD 3495');
console.log(semFoto ? '   OK: card sem fotos' : '   FALHOU');

console.log('\n--- resposta sem card nenhum ---');
const r3 = montar('bom dia, gustavo!', []);
r3.forEach(x => console.log('   ' + x));
const soTexto = r3.length === 1 && r3[0].startsWith('TEXTO:');
console.log(soTexto ? '   OK: so o texto' : '   FALHOU');

const falhas = [ordemOk, semFoto, soTexto].filter(x => !x).length;
console.log('\n' + (falhas ? falhas + ' FALHARAM' : 'TODOS OS 3 CENARIOS PASSARAM'));
process.exit(falhas ? 1 : 0);
