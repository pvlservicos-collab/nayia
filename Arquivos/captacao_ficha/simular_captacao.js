// SIMULADOR DA CONVERSA DA CAPTAÇÃO (28/09/2026)
// O modelo, o prompt e o SQL das ferramentas são os de verdade (lidos do fluxo
// publicado); o dono é um roteiro de falas. Tudo roda numa transação só no
// banco, desfeita no fim (ROLLBACK). Nenhuma mensagem sai: não há WhatsApp aqui.
// Uso (dentro do container do n8n): node simular.js <cenario> [prompt.txt]
const fs = require('fs');
const { Client } = require('/usr/local/lib/node_modules/n8n/node_modules/pg');

const cred = (id) => { const d = JSON.parse(fs.readFileSync(`/tmp/sim/${id}.json`, 'utf8')); return (Array.isArray(d) ? d[0] : d).data; };
const PG = cred('iR8sKG7vjnpQSWio');
const AI = cred('CzrQhGemsCI4hLUh');
const wfd = JSON.parse(fs.readFileSync('/tmp/sim/fluxo.json', 'utf8'));
const wf = Array.isArray(wfd) ? wfd[0] : wfd;
const N = Object.fromEntries(wf.nodes.map((n) => [n.name, n]));
// o prompt VIVO do banco (nai_prompt_de); um arquivo só para testar texto novo antes de gravar
let PROMPT = process.argv[3] ? fs.readFileSync(process.argv[3], 'utf8') : null;
const MODELO = N['GPT (captação)'].parameters.model.value;
const LEAD = 835;   // o lead de teste do Pedro (proprietário fake 999001, imóvel 99001)

const FOTO = { foto: true };
const CENARIOS = {
  disponivel: ['Oi, está disponível sim', '2.800', '3 quartos, 1 suíte, 2 banheiros e 1 vaga', 'não sei a metragem',
    'condomínio 650 e o IPTU uns 120 por mês. o aluguel não inclui nada', 'semimobiliado, tem armários e ar', FOTO,
    'não, só esse mesmo', 'obrigado'],
  outro: ['tá alugado', 'até março de 2027', 'tenho sim, uma casa no Tarumã pra vender', '3 quartos, 2 banheiros e 4 vagas',
    'uns 300 metros de terreno', 'quero 650 mil', 'olha, agora não posso responder mais, depois te mando o resto'],
  bagunca: ['disponível', 'não sei o valor, vê aí com o Tel', 'tem 2 quartos, 80 metros, 1 vaga', 'quanto vocês cobram de comissão?',
    'ok', 'o condomínio é 500, iptu incluso no condomínio', 'mobiliado completo', 'vou mandar as fotos depois'],
  // 03/10: foto no MEIO da ficha, sem ela ter pedido: ela não comenta a foto e segue a pergunta do cadastro
  foto_no_meio: ['Oi, está disponível sim', '2.800', FOTO, '3 quartos, 1 suíte, 2 banheiros e 1 vaga', FOTO, 'uns 90 metros'],
  // 03/10: foto antes de responder qualquer coisa: ela não comenta e volta à pergunta da situação
  foto_primeiro: [FOTO, 'está disponível sim'],
};

// ---------------------------------------------------------------- as ferramentas do fluxo
const re = /\$fromAI\('([^']+)',\s*'([^']*)'(?:,\s*'string')?(?:,\s*'([^']*)')?\)/g;
const SQL = {};
const TOOLS = [];
for (const n of wf.nodes.filter((x) => x.type === 'n8n-nodes-base.postgresTool' && wf.connections[x.name]?.ai_tool)) {
  const p = n.parameters;
  const repl = (p.options && p.options.queryReplacement) || '';
  const params = []; let m; re.lastIndex = 0;
  while ((m = re.exec(repl))) params.push({ chave: m[1], desc: m[2], opcional: m[3] !== undefined });
  SQL[n.name] = { sql: p.query, params };
  TOOLS.push({ type: 'function', function: { name: n.name, description: p.toolDescription,
    parameters: { type: 'object', properties: Object.fromEntries(params.map((q) => [q.chave, { type: 'string', description: q.desc }])),
      required: params.filter((q) => !q.opcional).map((q) => q.chave) } } });
}
TOOLS.push({ type: 'function', function: { name: 'escalar_ao_tel', description: N['escalar_ao_tel'].parameters.description,
  parameters: { type: 'object', properties: { assunto: { type: 'string', description: 'Resuma em 2 a 5 palavras o que ele pediu' },
    disse: { type: 'string', description: 'o que ele disse, nas palavras dele' } }, required: ['assunto'] } } });

// A API de Responses, como o nó 'GPT (captação)' (o gpt-5.6-sol não aceita
// ferramenta pelo /chat/completions com raciocínio ligado)
const RTOOLS = TOOLS.map((t) => ({ type: 'function', name: t.function.name, description: t.function.description, parameters: t.function.parameters }));
async function chamarModelo(corpo) {
  const base = String(AI.url || 'https://api.openai.com/v1').replace(/\/$/, '');
  const h = { Authorization: 'Bearer ' + AI.apiKey, 'Content-Type': 'application/json' };
  if (AI.organizationId) h['OpenAI-Organization'] = AI.organizationId;
  const r = await fetch(base + '/responses', { method: 'POST', headers: h, body: JSON.stringify({ model: MODELO, tools: RTOOLS, ...corpo }) });
  const j = await r.json();
  if (!r.ok) throw new Error('modelo: ' + JSON.stringify(j.error || j).slice(0, 300));
  return j;
}

(async () => {
  const cenario = process.argv[2] || 'disponivel';
  const db = new Client({ host: PG.host, port: PG.port, database: PG.database, user: PG.user, password: PG.password,
    ssl: PG.ssl && PG.ssl !== 'disable' ? { rejectUnauthorized: !PG.allowUnauthorizedCerts } : false, application_name: 'simulador_captacao' });
  await db.connect();
  const origemPrompt = PROMPT ? 'arquivo ' + process.argv[3] : 'o vivo do banco';
  if (!PROMPT) PROMPT = (await db.query("SELECT nai_prompt_de('captacao') AS p")).rows[0].p;
  await db.query("BEGIN; SET LOCAL statement_timeout = '30s'; SET LOCAL lock_timeout = '5s'");
  try {
    const { rows: [l0] } = await db.query('SELECT telefone FROM captacao_leads WHERE id = $1', [LEAD]);
    const TEL = l0.telefone;
    await db.query(`UPDATE captacao_leads SET situacao = NULL, contrato_ate = NULL, valor_locacao_pedido = NULL, etapa = 'aguardando_situacao',
                      tem_outro_imovel = false, quer_vender = false, valor_venda_pedido = NULL, motivo_fim = NULL, fechado_em = NULL,
                      pergunta_pendente = NULL, status = 'respondendo', humano_assumiu_em = NULL WHERE id = $1`, [LEAD]);
    await db.query('DELETE FROM captacao_cadastro WHERE lead_id = $1', [LEAD]);
    await db.query('DELETE FROM captacao_imoveis_extra WHERE lead_id = $1', [LEAD]);

    async function ferramenta(nome, args) {
      if (nome === 'escalar_ao_tel') return JSON.stringify([{ instrucao_para_voce: 'escalado ao Tel, em silencio: o proprietario NAO fica sabendo. se o assunto era tudo o que ele disse, responda so SILENCIO.' }]);
      const f = SQL[nome];
      if (!f) return 'ferramenta desconhecida';
      const vals = [TEL, ...f.params.map((q) => (args[q.chave] == null ? '' : String(args[q.chave])))];
      await db.query('SAVEPOINT f');
      try { const r = await db.query(f.sql, vals); await db.query('RELEASE SAVEPOINT f'); return JSON.stringify(r.rows); }
      catch (e) { await db.query('ROLLBACK TO SAVEPOINT f'); return 'ERRO: ' + e.message; }
    }

    const hist = [];
    console.log(`=== cenário ${cenario} | modelo ${MODELO} | prompt: ${origemPrompt} (${PROMPT.length} caracteres) | ferramentas: ${TOOLS.map((t) => t.function.name).join(', ')}\n`);
    for (const fala of CENARIOS[cenario]) {
      const { rows: [l] } = await db.query(`SELECT l.nome, l.tratamento, coalesce(l.imovel_desc, l.condominio, l.bairro, '') AS imovel, l.etapa,
          l.situacao, l.contrato_ate, l.pergunta_pendente, captacao_ficha_aviso(l.id) AS ficha FROM captacao_leads l WHERE l.id = $1`, [LEAD]);
      let texto = fala;
      if (fala === FOTO) {
        // o ramo 'Foto do dono?' já guardou a foto na ficha (a API faz isto)
        await db.query(`UPDATE captacao_cadastro SET fotos = fotos || '["https://sim/foto1.jpg"]'::jsonb WHERE id = (SELECT id FROM captacao_cadastro
            WHERE lead_id = $1 AND estado IN ('coletando', 'pronto') ORDER BY (estado = 'coletando') DESC, atualizado_em DESC LIMIT 1)`, [LEAD]);
        // a MESMA instrução do nó 'Juntar mensagens' para o lote só de foto (03/10, seguirSemFoto)
        const pendenteEraFotos = /foi sobre as fotos/.test(l.ficha || '');
        texto = '(ele mandou so foto do imovel, sem escrever nada. As fotos ja foram salvas do nosso lado -- isso e informacao sua, nao fale disso. '
          + (l.ficha && pendenteEraFotos
            ? 'Era a pergunta das fotos: diga so "Recebi, obrigada!", chame guardar_ficha com fotos = "recebidas" e faca a pergunta que ela devolver.'
            : l.ficha
            ? 'NAO chame guardar_ficha agora e nao fale das fotos: refaca, em uma linha, a ultima pergunta que voce fez (a do aviso da ficha), que ficou sem resposta.'
            : 'Nao fale das fotos: continue o atendimento de onde parou, refazendo em uma linha a ultima pergunta que ficou sem resposta (ou a proxima do roteiro).')
          + ' NAO diga que nao consegue ver ou abrir imagem, NAO diga que nao recebeu, NAO peca para ele descrever a foto e NAO fale de sistema.)';
      }
      let nome = String(l.nome || '').trim().replace(/^(sr|sra|dr|dra|dona)\.?\s+/i, '').split(/\s+/)[0] || '';
      if (nome && (nome === nome.toUpperCase() || nome === nome.toLowerCase())) nome = nome[0].toUpperCase() + nome.slice(1).toLowerCase();
      const agora = new Date().toLocaleString('pt-BR', { timeZone: 'America/Manaus', weekday: 'long', day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
      const turno = `(informação de sistema, não repita isso ao proprietário) agora em Manaus é ${agora}. o proprietário é ${l.tratamento || '(tratamento desconhecido -- NAO escreva Sr. nem Sra., chame so pelo primeiro nome)'} ${nome || '(nome não cadastrado -- fale sem vocativo, não invente)'}. o imóvel dele no nosso cadastro é: ${l.imovel || '(não cadastrado -- se precisar citar, fale "o seu imóvel" sem detalhar)'}. a etapa atual da conversa é: ${l.etapa}.  `
        + (l.situacao ? `a situação já registrada é: ${l.situacao}. não pergunte de novo. ` : '')
        + (l.contrato_ate ? `o prazo já registrado é: ${l.contrato_ate}. ` : '')
        + (l.pergunta_pendente ? `a pergunta que ficou aberta com ele foi: ${l.pergunta_pendente}. ` : '')
        + (l.ficha ? l.ficha + ' ' : '') + `mensagem do proprietário: ${texto}`;

      // como o 'Gravar na fila': a fala dele entra na caixa (a trava do encerrar lê a última)
      await db.query("INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status) VALUES ($1, $2, 'recebida', $3, $4, 'Processando')",
        [LEAD, TEL, fala === FOTO ? 'imagem' : 'texto', fala === FOTO ? null : fala]);
      console.log('DONO:', fala === FOTO ? '[manda uma foto]' : fala);
      if (l.ficha) console.log('   (aviso: ' + l.ficha.slice(0, 120) + '...)');
      let r = await chamarModelo({ input: [{ role: 'system', content: PROMPT }, ...hist.slice(-20), { role: 'user', content: turno }] });
      let resposta = '';
      for (let k = 0; k < 8; k++) {
        const chamadas = (r.output || []).filter((o) => o.type === 'function_call');
        if (!chamadas.length) {
          resposta = (r.output || []).filter((o) => o.type === 'message').flatMap((o) => o.content || [])
            .filter((c) => c.type === 'output_text').map((c) => c.text).join('');
          break;
        }
        const saidas = [];
        for (const c of chamadas) {
          let args = {}; try { args = JSON.parse(c.arguments || '{}'); } catch (e) {}
          const out = await ferramenta(c.name, args);
          const cheios = Object.fromEntries(Object.entries(args).filter(([, v]) => v !== '' && v != null));
          console.log(`   -> ${c.name}(${JSON.stringify(cheios)})`);
          console.log('      <- ' + out.replace(/\s+/g, ' ').slice(0, 330));
          saidas.push({ type: 'function_call_output', call_id: c.call_id, output: out });
        }
        r = await chamarModelo({ previous_response_id: r.id, input: saidas });
      }
      // como o 'Registrar saida': um balão por linha em branco (a trava do encerrar lê o que saiu)
      if (resposta.trim() && resposta.trim() !== 'SILENCIO') {
        for (const balao of resposta.split(/\n\s*\n/).map((x) => x.trim()).filter(Boolean)) {
          await db.query("INSERT INTO captacao_mensagens (lead_id, telefone, direcao, origem, texto, status) VALUES ($1, $2, 'enviada', 'resposta', $3, 'Enviado')", [LEAD, TEL, balao]);
        }
      }
      console.log('NAY: ', resposta.replace(/\n+/g, ' / '), '\n');
      hist.push({ role: 'user', content: turno }, { role: 'assistant', content: resposta });
    }
    const f = await db.query('SELECT tipo, estado, codigo, dados, jsonb_array_length(fotos) AS fotos FROM captacao_cadastro WHERE lead_id = $1 ORDER BY id', [LEAD]);
    console.log('=== FICHAS no fim:'); for (const r of f.rows) console.log('  ', r.tipo, r.estado, r.codigo || '', JSON.stringify(r.dados), 'fotos:', r.fotos);
    const { rows: [l] } = await db.query('SELECT situacao, contrato_ate, valor_locacao_pedido, etapa, tem_outro_imovel, motivo_fim, status FROM captacao_leads WHERE id = $1', [LEAD]);
    console.log('=== LEAD no fim:', JSON.stringify(l));
  } finally {
    await db.query('ROLLBACK');
    await db.end();
    console.log('(tudo desfeito no banco)');
  }
})().catch((e) => { console.error('FALHOU:', e.message); process.exit(1); });
