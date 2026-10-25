// IMPORTAR VISTORIA DE OUTRO LUGAR (Pedro, 24/10/2026: "uma função nova na aba Vistorias onde eu, ao invés de iniciar
// uma vistoria do 0, eu subo uma de outro lugar e o nosso sistema entende"). PDF ou link (PDF, Google Drive ou página
// do laudo). Quem lê é o Gemini (25/10, escolha do Pedro: a mesma chave gratuita da revisão da Nay, GEMINI_API_KEY no
// .env). Sai uma vistoria em rascunho com o imóvel, as partes, os cômodos, os itens com estado e funcionamento e as
// avarias. As fotos do laudo de fora NÃO vêm: o vistoriador tira as dele.
const fs = require('fs');
const { run, uid, nextCode, logEvent, tx } = require('../db');

const API = 'https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent';
// o primeiro que responder (o gratuito vive com 503 de "alta demanda" num modelo e não no outro)
const MODELOS = [process.env.GEMINI_MODEL || 'gemini-flash-latest', 'gemini-3.5-flash', 'gemini-flash-lite-latest'];
const MAX_BYTES = 40 * 1024 * 1024;
const ESTADOS = ['novo', 'bom', 'regular', 'mau'];
const FUNC = ['funcionando', 'nao_funcionando', 'nao_testado'];

const PROMPT = `Você lê um LAUDO DE VISTORIA de imóvel feito por outra empresa (Brasil) e passa para o nosso sistema.
Leia tudo e devolva o JSON pedido. Regras:
- Um cômodo por ambiente do laudo (Sala, Cozinha, Quarto 1, Banheiro social, Área de serviço, Varanda...), na ordem do laudo.
- Em cada cômodo, os itens vistoriados (piso, paredes, teto, portas, janelas, tomadas, interruptores, louças, metais,
  armários, eletrodomésticos...). "condition": novo | bom | regular | mau (o mais próximo do que o laudo diz; ótimo e
  excelente = novo; sem dizer = ""). "functioning": funcionando | nao_funcionando | nao_testado | "" (só para o que
  liga, abre ou tem água). "notes": a descrição do laudo, curta (cor, material, observação).
- Avaria, defeito, mancha, trinca, quebrado, faltando: "avaria" com a descrição; sem avaria, "".
- Não invente: o que o laudo não diz fica vazio.`;

const ESQUEMA = {
  type: 'OBJECT',
  properties: {
    type: { type: 'STRING', enum: ['entrada', 'saida', 'temporada', 'compra_venda', 'periodica', 'recebimento'] },
    data_da_vistoria: { type: 'STRING' },
    empresa_de_origem: { type: 'STRING' },
    property: { type: 'OBJECT', properties: {
      identification: { type: 'STRING' }, type: { type: 'STRING' }, purpose: { type: 'STRING' }, street: { type: 'STRING' },
      number: { type: 'STRING' }, complement: { type: 'STRING' }, district: { type: 'STRING' }, city: { type: 'STRING' },
      state: { type: 'STRING' }, cep: { type: 'STRING' }, area: { type: 'STRING' }, furnished: { type: 'STRING' } } },
    locadores: { type: 'ARRAY', items: { type: 'OBJECT', properties: { name: { type: 'STRING' }, cpf: { type: 'STRING' } } } },
    locatarios: { type: 'ARRAY', items: { type: 'OBJECT', properties: { name: { type: 'STRING' }, cpf: { type: 'STRING' } } } },
    medidores: { type: 'OBJECT', properties: { energia: { type: 'STRING' }, agua: { type: 'STRING' }, gas: { type: 'STRING' } } },
    observacoes_gerais: { type: 'STRING' },
    comodos: { type: 'ARRAY', items: { type: 'OBJECT', properties: {
      name: { type: 'STRING' }, notes: { type: 'STRING' },
      items: { type: 'ARRAY', items: { type: 'OBJECT', properties: {
        name: { type: 'STRING' }, condition: { type: 'STRING' }, functioning: { type: 'STRING' }, quantity: { type: 'STRING' },
        notes: { type: 'STRING' }, avaria: { type: 'STRING' } }, required: ['name'] } } }, required: ['name'] } },
  },
  required: ['comodos'],
};

// O link vira o arquivo: o do Google Drive pelo download direto; PDF fica PDF; página vira texto
function linkDireto(url) {
  const m = String(url).match(/drive\.google\.com\/(?:file\/d\/|open\?id=)([\w-]{10,})/);
  return m ? `https://drive.google.com/uc?export=download&id=${m[1]}` : url;
}
async function baixar(url) {
  if (!/^https?:\/\//i.test(url || '')) throw new Error('O link precisa começar com http:// ou https://');
  const r = await fetch(linkDireto(url), { redirect: 'follow', headers: { 'User-Agent': 'Mozilla/5.0 (vistoria Imob Easy)' } });
  if (!r.ok) throw new Error(`O link respondeu ${r.status}`);
  const buf = Buffer.from(await r.arrayBuffer());
  if (buf.length > MAX_BYTES) throw new Error('O arquivo do link passa de 40 MB');
  const tipo = (r.headers.get('content-type') || '').toLowerCase();
  if (tipo.includes('pdf') || buf.slice(0, 5).toString() === '%PDF-') return { pdf: buf };
  const texto = buf.toString('utf8').replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<br\s*\/?>|<\/(p|div|tr|li|h\d)>/gi, '\n').replace(/<[^>]+>/g, ' ').replace(/&nbsp;/g, ' ')
    .replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
  if (texto.length < 200) throw new Error('A página do link não tem o texto do laudo (pode pedir login). Baixe o PDF e suba o arquivo.');
  return { texto: texto.slice(0, 400000) };
}

async function gemini({ pdf, texto }) {
  const key = process.env.GEMINI_API_KEY;
  if (!key) throw new Error('A chave do Gemini (GEMINI_API_KEY) não está no .env da vistoria');
  const partes = pdf ? [{ inline_data: { mime_type: 'application/pdf', data: pdf.toString('base64') } }] : [{ text: 'O LAUDO:\n' + texto }];
  partes.push({ text: PROMPT });
  const corpo = { contents: [{ role: 'user', parts: partes }],
    generationConfig: { temperature: 0.1, responseMimeType: 'application/json', responseSchema: ESQUEMA } };
  let ultimo = '';
  for (let tentativa = 0; tentativa < 6; tentativa++) {
    const modelo = MODELOS[tentativa % MODELOS.length];
    const r = await fetch(API.replace('%s', modelo), { method: 'POST', headers: { 'Content-Type': 'application/json', 'x-goog-api-key': key }, body: JSON.stringify(corpo),
      signal: AbortSignal.timeout(150000) }).catch((e) => ({ ok: false, status: 0, text: async () => `${e.name}: ${e.message}` }));
    if (r.ok) {
      const j = await r.json();
      const txt = (((j.candidates || [])[0] || {}).content || {}).parts?.map((p) => p.text || '').join('') || '';
      try { return JSON.parse(txt); } catch { ultimo = 'o Gemini não devolveu JSON'; continue; }
    }
    ultimo = `o Gemini respondeu ${r.status}: ${(await r.text()).slice(0, 200)}`;
    if (![0, 404, 429, 500, 502, 503].includes(r.status)) break;   // 0: a rede ou o tempo; 404: o modelo saiu
    await new Promise((ok) => setTimeout(ok, 2000 * (tentativa + 1)));
  }
  throw new Error(ultimo || 'o Gemini não respondeu');
}

const limpo = (s) => String(s == null ? '' : s).trim();
function normaliza(d) {
  const comodos = (d.comodos || []).filter((c) => limpo(c.name)).map((c) => ({
    name: limpo(c.name).slice(0, 80), notes: limpo(c.notes),
    items: (c.items || []).filter((i) => limpo(i.name)).map((i) => ({
      name: limpo(i.name).slice(0, 120), condition: ESTADOS.includes(i.condition) ? i.condition : null,
      functioning: FUNC.includes(i.functioning) ? i.functioning : null, quantity: limpo(i.quantity) || null,
      notes: limpo(i.notes), avaria: limpo(i.avaria) })) }));
  return { ...d, property: imovel(d.property || {}), comodos };
}

// O imóvel no padrão do app: o tipo e a mobília como as opções da tela, a UF em duas letras
const TIPOS = ['Apartamento', 'Casa', 'Sobrado', 'Kitnet/Studio', 'Sala Comercial', 'Galpão', 'Terreno', 'Rancho'];
function imovel(p) {
  const n = (x) => limpo(x).normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const tipo = TIPOS.find((t) => n(p.type).startsWith(n(t).split('/')[0])) || (limpo(p.type) ? 'Outro' : '');
  const mob = n(p.furnished);
  const uf = (limpo(p.state).match(/\(([A-Z]{2})\)/) || limpo(p.state).match(/^([A-Za-z]{2})$/) || [])[1];
  const fin = n(p.purpose);
  return { ...p, type: tipo || undefined, state: uf ? uf.toUpperCase() : limpo(p.state).slice(0, 2).toUpperCase() || undefined,
    furnished: mob.startsWith('semi') ? 'Semimobiliado' : mob.startsWith('nao') || mob.startsWith('sem') ? 'Não mobiliado' : mob.startsWith('mob') ? 'Mobiliado' : undefined,
    purpose: fin.startsWith('com') ? 'Comercial' : fin.startsWith('res') ? 'Residencial' : undefined };
}

// A vistoria nova, em rascunho, como o painel cria (rooms, items e as avarias do item em ncs)
function criar(d, quem, origem) {
  const id = uid();
  const p = d.property || {};
  const parties = { locadores: (d.locadores || []).filter((x) => limpo(x.name)), locatarios: (d.locatarios || []).filter((x) => limpo(x.name)), fiadores: [], testemunhas: [] };
  const meters = Object.fromEntries(Object.entries(d.medidores || {}).filter(([, v]) => limpo(v)).map(([k, v]) => [k, { reading: limpo(v), media: [] }]));
  let itens = 0, avarias = 0;
  tx(() => {
    run(`INSERT INTO inspections(id,code,type,status,inspector_id,property,parties,meters,extra,general_notes,inspected_at)
         VALUES(?,?,?,?,?,?,?,?,?,?,?)`, id, nextCode(), quem.type || d.type || 'entrada', 'rascunho', quem.inspector_id,
    JSON.stringify(p), JSON.stringify(parties), JSON.stringify(meters),
    JSON.stringify({ importada_de: origem, empresa_de_origem: limpo(d.empresa_de_origem), data_original: limpo(d.data_da_vistoria) }),
    limpo(d.observacoes_gerais), new Date().toISOString());
    d.comodos.forEach((c, ci) => {
      const rid = uid();
      run('INSERT INTO rooms(id,inspection_id,name,position,notes) VALUES(?,?,?,?,?)', rid, id, c.name, ci, c.notes);
      c.items.forEach((it, ii) => {
        const iid = uid();
        itens++;
        run(`INSERT INTO items(id,inspection_id,room_id,name,position,condition,functioning,quantity,notes,has_nc)
             VALUES(?,?,?,?,?,?,?,?,?,?)`, iid, id, rid, it.name, ii, it.condition, it.functioning, it.quantity, it.notes, it.avaria ? 1 : 0);
        if (it.avaria) {
          avarias++;
          run('INSERT INTO ncs(id,inspection_id,room_id,item_id,title,description,position) VALUES(?,?,?,?,?,?,?)', uid(), id, rid, iid, 'Avaria', it.avaria, 0);
        }
      });
    });
    logEvent(id, 'criada', `Vistoria importada (${origem}): ${d.comodos.length} cômodo(s), ${itens} item(ns), ${avarias} avaria(s)`, quem.user_id);
  });
  return { id, comodos: d.comodos.length, itens, avarias };
}

async function importar({ arquivo, url, type, inspector_id, user_id }) {
  let fonte, origem;
  if (arquivo) {
    const buf = fs.readFileSync(arquivo.path);
    fs.unlink(arquivo.path, () => {});
    if (buf.slice(0, 5).toString() !== '%PDF-') throw new Error('O arquivo precisa ser um PDF');
    fonte = { pdf: buf }; origem = arquivo.originalname || 'PDF';
  } else {
    fonte = await baixar(url); origem = url;
  }
  const d = normaliza(await gemini(fonte));
  if (!d.comodos.length) throw new Error('Não achei cômodos nesse laudo. Ele é mesmo uma vistoria?');
  return criar(d, { type, inspector_id, user_id }, origem);
}

module.exports = { importar, linkDireto, normaliza };
