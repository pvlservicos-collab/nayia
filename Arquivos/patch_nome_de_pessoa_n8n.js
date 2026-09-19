// O modelo passa a ver o nome da PESSOA, não o nome de WhatsApp cru.
//
// O CASO (01/09): "OPEN SERVIÇOS" mandou mensagem e ela respondeu "Olá,
// OPEN SERVIÇOS!". A regra [identidade] criada no mesmo dia manda perguntar
// o nome quando for empresa -- mas o que chegava ao modelo era o
// `senderName` cru, e a regra era reavaliada a cada mensagem com o nome
// errado na frente dele.
//
// Agora o dado chega resolvido: `nay_nome_de_pessoa` devolve o primeiro
// nome ou NULL, e NULL já cai no "nao sei o nome dele" que o prompt tem.
// Medido antes de aplicar: de 185 nomes reais em `mensagens`, 5 viram
// pergunta -- "..", "🌸", "H", "T C A" e o próprio "OPEN SERVIÇOS".
//
// E O SEGUNDO BURACO, que fazia a pergunta não valer de nada: o que ela
// aprendia com `guardar_dados_do_corretor` era APAGADO na mensagem
// seguinte. `nay_sincronizar_nome` roda no `Gravar na fila` e sobrescreve
// tudo que não esteja marcado `nome_origem='manual'` -- e a ferramenta não
// marcava. Ela perguntaria o nome a cada mensagem, para sempre.
const fs = require('fs');
const bruto = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const wf = Array.isArray(bruto) ? bruto[0] : bruto;
const nos = Object.fromEntries(wf.nodes.map((x) => [x.name, x]));

// ---------- 1. `Reservar mensagens` traz o nome resolvido ----------
const rm = nos['Reservar mensagens'];
if (!rm) throw new Error('Reservar mensagens nao encontrado');
if (rm.parameters.query.includes('nay_nome_de_pessoa')) {
  console.log('  (ja aplicado) Reservar mensagens');
} else {
  const ancora = '  nay_pede_localizacao_da_unidade(texto) AS pede_unidade,';
  if (!rm.parameters.query.includes(ancora)) throw new Error('ancora do RETURNING mudou');
  rm.parameters.query = rm.parameters.query.replace(ancora,
    '  -- O primeiro nome da pessoa, ou NULL quando o nome e de empresa.\n' +
    '  -- Calculado aqui pelo mesmo motivo dos de baixo: e deste no que o\n' +
    '  -- `Juntar mensagens` le.\n' +
    '  nay_nome_de_pessoa(nome) AS nome_pessoa,\n' + ancora);
  console.log('  Reservar mensagens: + nome_pessoa');
}

// ---------- 2. `Juntar mensagens` carrega o nome resolvido ----------
const jm = nos['Juntar mensagens'];
let c = jm.parameters.jsCode;
if (c.includes('nomePessoa')) {
  console.log('  (ja aplicado) Juntar mensagens');
} else {
  const ancora = 'nome: nomeItem ? nomeItem.nome : null,';
  if (!c.includes(ancora)) throw new Error('a saida do nome mudou');
  // `nome` cru continua saindo: quem grava e quem avisa o Tel usa ele.
  // O que muda e o que o MODELO ve.
  c = c.replace(ancora, ancora +
    " nomePessoa: (itens.map(m => m.nome_pessoa).filter(Boolean)[0]) || null,");
  jm.parameters.jsCode = c;
  console.log('  Juntar mensagens: + nomePessoa');
}

// ---------- 3. o AI Agent le o nome da pessoa ----------
const ag = nos['AI Agent'];
let t = ag.parameters.text;
if (t.includes('nomePessoa')) {
  console.log('  (ja aplicado) AI Agent');
} else {
  const de = "o corretor se chama {{ $('Juntar mensagens').first().json.nome || 'nao sei o nome dele' }}.";
  if (!t.includes(de)) throw new Error('a frase do nome mudou no AI Agent');
  t = t.replace(de,
    "o corretor se chama {{ $('Juntar mensagens').first().json.nomePessoa || 'nao sei o nome dele -- o que veio foi nome de empresa ou nao veio nada. PERGUNTE com quem voce fala antes de tratar por nome' }}.");
  ag.parameters.text = t;
  console.log('  AI Agent: nome da pessoa, e a pergunta quando nao ha');
}

// ---------- 4. o que ela aprende para de ser apagado ----------
const gd = nos['guardar_dados_do_corretor'];
if (!gd) throw new Error('guardar_dados_do_corretor nao encontrado');
if (gd.parameters.query.includes('nome_origem')) {
  console.log('  (ja aplicado) guardar_dados_do_corretor');
} else {
  let q = gd.parameters.query;
  const de1 = 'INSERT INTO corretores (telefone, creci, nome, ultima_interacao)\n  SELECT telefone, creci, nome, now() FROM valida';
  const para1 = '-- `nome_origem` marcado como manual: sem isso o `nay_sincronizar_nome`\n' +
                '  -- do `Gravar na fila` sobrescreve na mensagem seguinte, e ela pergunta\n' +
                '  -- o nome de novo para sempre.\n  ' +
                "INSERT INTO corretores (telefone, creci, nome, nome_origem, ultima_interacao)\n" +
                "  SELECT telefone, creci, nome, CASE WHEN nome IS NOT NULL THEN 'manual' END, now() FROM valida";
  const de2 = 'SET creci = COALESCE(EXCLUDED.creci, corretores.creci),\n         nome  = COALESCE(EXCLUDED.nome,  corretores.nome),';
  const para2 = 'SET creci = COALESCE(EXCLUDED.creci, corretores.creci),\n' +
                '         nome  = COALESCE(EXCLUDED.nome,  corretores.nome),\n' +
                '         nome_origem = COALESCE(EXCLUDED.nome_origem, corretores.nome_origem),';
  if (!q.includes(de1) || !q.includes(de2)) throw new Error('o INSERT do corretor mudou');
  q = q.replace(de1, para1).replace(de2, para2);
  gd.parameters.query = q;
  console.log('  guardar_dados_do_corretor: grava nome_origem = manual');
}

fs.writeFileSync(process.argv[3], JSON.stringify(Array.isArray(bruto) ? [wf] : wf, null, 2));
console.log('  gravado em ' + process.argv[3]);
