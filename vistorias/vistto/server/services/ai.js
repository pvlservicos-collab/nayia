// IA: leitura do contrato (extração de dados) e descrição de itens por foto.
// Usa a API da Anthropic (Claude) quando ANTHROPIC_API_KEY está configurada; caso contrário,
// usa um extrator local por regras (funciona offline e sem custo) para contratos de locação padrão.
const fs = require('fs');
const cfg = require('../config');

async function pdfText(file) {
  const pdfjs = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const data = new Uint8Array(fs.readFileSync(file));
  const doc = await pdfjs.getDocument({ data, useSystemFonts: true, isEvalSupported: false }).promise;
  let out = '';
  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p);
    const tc = await page.getTextContent();
    let lastY = null;
    for (const it of tc.items) {
      const y = it.transform ? it.transform[5] : null;
      if (lastY !== null && y !== null && Math.abs(y - lastY) > 2) out += '\n';
      out += it.str;
      lastY = y;
    }
    out += '\n\n';
  }
  return out;
}

const PROMPT = `Você é um assistente que lê contratos imobiliários brasileiros (locação, compra e venda) e extrai dados para um laudo de vistoria.
Responda SOMENTE com um JSON válido, sem comentários, no formato:
{
  "property": {"identification": "nome curto do imóvel em MAIÚSCULAS ex: SMART TOWER ITAPORANGA - TORRE 2 APTO 708", "type": "Apartamento|Casa|Sobrado|Kitnet/Studio|Sala Comercial|Galpão|Terreno|Rancho|Outro", "purpose": "Residencial|Comercial", "street": "", "number": "", "complement": "", "district": "", "city": "", "state": "UF", "cep": "00000-000", "iptu": "", "area": "", "furnished": "Mobiliado|Semimobiliado|Não mobiliado|"},
  "parties": {
    "locadores": [{"name": "", "cpf": "", "rg": "", "email": "", "phone": "", "nationality": "", "civil_status": "", "profession": "", "address": ""}],
    "locatarios": [{"name": "", "cpf": "", "rg": "", "email": "", "phone": "", "nationality": "", "civil_status": "", "profession": "", "address": ""}],
    "fiadores": [],
    "imobiliaria": {"name": "", "cnpj": "", "creci": "", "representative": ""}
  },
  "contract": {"kind": "locação|compra e venda|temporada", "rent": "R$ 0,00", "due_day": "", "start": "AAAA-MM-DD", "end": "AAAA-MM-DD", "months": "", "deposit": "", "guarantee": "caução|fiador|seguro fiança|título de capitalização|", "readjust_index": "", "condo_included": true, "notes": "resumo em 1-2 frases das obrigações relevantes para a vistoria"}
}
Use string vazia quando não houver a informação. Nomes em MAIÚSCULAS como no contrato.`;

async function claudeExtract(file) {
  const { key, model } = cfg.integrations().ai;
  const data = fs.readFileSync(file).toString('base64');
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({
      model, max_tokens: 2500,
      messages: [{ role: 'user', content: [
        { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data } },
        { type: 'text', text: PROMPT },
      ] }],
    }),
  });
  if (!r.ok) throw new Error(`IA respondeu ${r.status}: ${(await r.text()).slice(0, 300)}`);
  const j = await r.json();
  const txt = (j.content || []).map((c) => c.text || '').join('');
  const m = txt.match(/\{[\s\S]*\}/);
  if (!m) throw new Error('IA não retornou JSON');
  return JSON.parse(m[0]);
}

// ---------- Extrator local por regras ----------
const UP = 'A-ZÁÉÍÓÚÂÊÔÃÕÇÀÜ';
const MONTHS = { janeiro: 1, fevereiro: 2, 'março': 3, marco: 3, abril: 4, maio: 5, junho: 6, julho: 7, agosto: 8, setembro: 9, outubro: 10, novembro: 11, dezembro: 12 };

function dateBR(s) {
  if (!s) return '';
  let m = s.match(/(\d{1,2})\s+de\s+([a-zç]+)\s+de\s+(\d{4})/i);
  if (m && MONTHS[m[2].toLowerCase()]) return `${m[3]}-${String(MONTHS[m[2].toLowerCase()]).padStart(2, '0')}-${m[1].padStart(2, '0')}`;
  m = s.match(/(\d{2})\/(\d{2})\/(\d{4})/);
  if (m) return `${m[3]}-${m[2]}-${m[1]}`;
  return '';
}

function person(chunk) {
  const name = (chunk.match(new RegExp(`^\\s*([${UP}][${UP}\\s.]{4,}?)\\s*,`)) || [])[1] || '';
  const g = (re) => ((chunk.match(re) || [])[1] || '').trim();
  return {
    name: name.replace(/\s+/g, ' ').trim().split(/\.\s+/).pop().trim(),
    nationality: g(/,\s*(brasileir[oa]|estrangeir[oa])/i),
    civil_status: g(/,\s*(solteir[oa]|casad[oa]|divorciad[oa]|viúv[oa]|convivente[^,]*|separad[oa])/i),
    profession: (() => { const m = chunk.match(/brasileir[oa],\s*([^,]+),\s*(?:solteir|casad|divorciad|viúv|convivente|separad)/i); return m ? m[1].trim() : ''; })(),
    rg: g(/RG\s*n?[°º.]*\s*([\d.\-\/xX]+(?:\s*[A-Z]{2,4}[\/-][A-Z]{2})?)/),
    cpf: g(/CPF\s*n?[°º.]*\s*(\d{3}\.?\d{3}\.?\d{3}-?\d{2})/),
    email: g(/([\w.+-]+@[\w-]+(?:\.[\w-]+)+)/),
    phone: g(/(\(?\d{2}\)?\s*9?\d{4}-?\d{4})/),
    address: g(/(?:residente e domiciliad[oa]|com endereço empresarial|endereço empresarial|com endereço)\s*(?:na|no|em)?\s+([^;]+?)(?:,\s*onde|\.\s|$)/i),
  };
}

function people(section) {
  if (!section) return [];
  const re = new RegExp(`([${UP}][${UP}\\s.]{4,}?),\\s*(?:brasileir|estrangeir)`, 'g');
  const starts = [];
  let m;
  while ((m = re.exec(section))) starts.push(m.index);
  return starts.map((s, i) => person(section.slice(s, starts[i + 1] || section.length))).filter((p) => p.name);
}

function ruleExtract(text) {
  const t = text.replace(/[ \t]+/g, ' ').replace(/\n(?=[a-zà-ú(,.])/g, ' ').replace(/\s*\n\s*/g, '\n');
  const flat = t.replace(/\n/g, ' ');
  const sect = (a, b) => { const i = flat.search(a); if (i < 0) return ''; const rest = flat.slice(i); const j = rest.slice(10).search(b); return j < 0 ? rest : rest.slice(0, j + 10); };

  const loc = sect(/PARTE LOCADORA|LOCADOR(?:A)?\s*:/i, /PARTE LOCAT[ÁA]RIA|LOCAT[ÁA]RIO(?:S|A)?\s*:/i);
  const lct = sect(/PARTE LOCAT[ÁA]RIA|LOCAT[ÁA]RIO(?:S|A)?\s*:/i, /PARTE INTERVENIENTE|FIADOR|T[êe]m entre si|CL[ÁA]USULA/i);
  const fia = sect(/PARTE FIADORA|FIADOR(?:ES|A)?\s*:/i, /PARTE INTERVENIENTE|T[êe]m entre si|CL[ÁA]USULA/i);
  const intv = sect(/PARTE INTERVENIENTE|IMOBILI[ÁA]RIA\s*:/i, /T[êe]m entre si|CL[ÁA]USULA/i);

  const obj = sect(/BEM IM[ÓO]VEL|DO OBJETO/i, /CL[ÁA]USULA 2|DA UTILIZA/i);
  const g = (s, re) => ((s.match(re) || [])[1] || '').trim();
  const unit = obj.match(/(Apartamento|Casa|Sala|Loja|Kitnet|Studio|Sobrado|Galp[ãa]o|Terreno)\s*n?[°º.]*\s*(\w+)/i);
  const tower = g(obj, /(Torre\s*\w+|Bloco\s*\w+)/i);
  const condo = g(obj, /Condom[íi]nio\s+([^,]+?)(?:,|\s+na\s|\s+no\s)/i);
  const street = obj.match(/(?:na|no|à)\s+((?:Rua|Avenida|Av\.|Travessa|Alameda|Estrada|Rodovia|Beco|Praça)\s[^,]+?),\s*n?[°º.]*\s*(\d+\w?)/i);
  const cityUf = obj.match(/,\s*([A-Za-zÀ-ú' ]{3,})\s*[\/-]\s*([A-Z]{2})\b/);
  const typeMap = { apartamento: 'Apartamento', casa: 'Casa', sala: 'Sala Comercial', loja: 'Sala Comercial', kitnet: 'Kitnet/Studio', studio: 'Kitnet/Studio', sobrado: 'Sobrado', galpão: 'Galpão', galpao: 'Galpão', terreno: 'Terreno' };
  const type = unit ? typeMap[unit[1].toLowerCase()] || 'Outro' : '';
  const complement = [unit ? `${type === 'Apartamento' ? 'Apto' : unit[1]} ${unit[2]}` : '', tower].filter(Boolean).join(', ');
  const identification = [condo, tower, unit ? `${type === 'Apartamento' ? 'APTO' : unit[1].toUpperCase()} ${unit[2]}` : ''].filter(Boolean).join(' - ').toUpperCase();

  const vig = sect(/VIG[ÊE]NCIA/i, /CL[ÁA]USULA 5|4\.2/i);
  const startEnd = vig.match(/iniciando-se em\s+([^,]+?)\s+e\s+findando-se em\s+([^,.]+)/i);
  const months = g(vig, /vig[êe]ncia de\s*(\d+)/i);
  const rent = g(flat, /(?:valor da loca[çc][ãa]o|valor do aluguel|aluguel mensal)[\s\S]{0,160}?(R\$\s*[\d.]+,\d{2})/i);
  const depM = flat.match( /cau[çc][ãa]o em dinheiro[\s\S]{0,160}?(R\$\s*[\d.]+,\d{2})|cau[çc][ãa]o[\s\S]{0,120}?(R\$\s*[\d.]+,\d{2})/i);
  const deposit = depM ? (depM[1] || depM[2] || "").trim() : "";
  const due = g(flat, /todo dia\s*(\d{1,2})/i);
  const purpose = /residencial/i.test(flat) ? 'Residencial' : /comercial/i.test(flat) ? 'Comercial' : '';
  const furnished = /semimobiliad/i.test(flat) ? 'Semimobiliado' : /mobiliad/i.test(flat) ? 'Mobiliado' : '';
  const imob = intv ? { name: g(intv, /nome fantasia\s+([^.]+)\./i) || g(intv, new RegExp(`([${UP}][${UP}\\s]{4,}?),\\s*pessoa jur`)), cnpj: g(intv, /CNPJ\s*n?[°º.]*\s*([\d./-]{14,18})/), creci: g(intv, /CRECI\s*([A-Z/ ]*n?[°º]?\s*\d+\s*\w*)/), representative: g(intv, new RegExp(`representada por seu \\w+\\s+([${UP}][${UP}\\s]+?),`)) } : {};

  return {
    property: {
      identification, type, purpose, complement,
      street: street ? street[1].trim() : '', number: street ? street[2] : '',
      district: g(obj, /bairro\s+([^,]+)/i), cep: g(obj, /CEP:?\s*(\d{2}\.?\d{3}-?\d{3})/i),
      city: cityUf ? cityUf[1].trim() : '', state: cityUf ? cityUf[2] : '',
      iptu: g(obj, /IPTU:?\s*n?[°º.]*\s*(\d+)/i), area: g(flat, /(\d+[.,]?\d*)\s*m[²2]/i), furnished,
    },
    parties: { locadores: people(loc), locatarios: people(lct), fiadores: people(fia), imobiliaria: imob },
    contract: {
      kind: /CONTRATO DE LOCA/i.test(flat) ? (/temporada/i.test(flat.slice(0, 400)) ? 'temporada' : 'locação') : /compra e venda/i.test(flat) ? 'compra e venda' : 'locação',
      rent, due_day: due, start: startEnd ? dateBR(startEnd[1]) : '', end: startEnd ? dateBR(startEnd[2]) : '', months,
      deposit, guarantee: deposit ? 'caução' : /fiador/i.test(flat) ? 'fiador' : '', readjust_index: g(flat, /(IGP-?M|IPCA|INPC)/), condo_included: /condom[íi]nio\s+EST[ÁA]\s+INCLU[ÍI]DA/i.test(flat), notes: '',
    },
  };
}

async function extractContract(file) {
  const ai = cfg.integrations().ai;
  let text = '';
  try { text = await pdfText(file); } catch (e) { text = ''; }
  if (ai.key) {
    try { const r = await claudeExtract(file); return { engine: 'claude', model: ai.model, data: r, text_chars: text.length }; } catch (e) {
      const r = ruleExtract(text); return { engine: 'regras', warning: `IA indisponível (${e.message}). Usado extrator local.`, data: r, text_chars: text.length };
    }
  }
  if (!text.trim()) return { engine: 'regras', warning: 'PDF sem texto (digitalizado). Configure a chave de IA para ler PDFs escaneados.', data: { property: {}, parties: {}, contract: {} } };
  return { engine: 'regras', data: ruleExtract(text), text_chars: text.length };
}

// Descrição de item/cômodo a partir de fotos (opcional, requer chave de IA)
async function describeImages(files, context) {
  const ai = cfg.integrations().ai;
  if (!ai.key) throw new Error('Configure a chave da IA (ANTHROPIC_API_KEY) para gerar descrições automáticas.');
  const content = files.slice(0, 8).map((f) => ({ type: 'image', source: { type: 'base64', media_type: f.mime || 'image/jpeg', data: fs.readFileSync(f.path).toString('base64') } }));
  content.push({ type: 'text', text: `Você é um vistoriador de imóveis. Descreva objetivamente, em português, em 1 a 3 frases curtas, o estado de conservação de "${context}" visto nas fotos (material, cor, desgastes, avarias). Não invente o que não aparece. Responda só o texto.` });
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-api-key': ai.key, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({ model: ai.model, max_tokens: 400, messages: [{ role: 'user', content }] }),
  });
  if (!r.ok) throw new Error(`IA respondeu ${r.status}`);
  const j = await r.json();
  return (j.content || []).map((c) => c.text || '').join('').trim();
}

module.exports = { extractContract, ruleExtract, pdfText, describeImages };
