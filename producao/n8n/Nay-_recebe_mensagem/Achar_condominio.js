const j = $('Juntar mensagens').first().json;
const texto = j.texto || '';
if (/c[óo]digo\s*[:\-]?\s*\d{3,5}/i.test(texto) || /^\d{3,5}$/.test(texto.trim())) return [];
const norm = s => (s || '').toString().normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[^a-z0-9\s]/g, ' ').replace(/\s+/g, ' ').trim();
const GEN = /^(condominio|residencial|edificio|ed|cond)\s+/;
const t = norm(texto);
let melhor = null;
for (const item of $input.all()) {
  const nome = item.json.condominio_nome;
  let nuc = norm(nome);
  while (GEN.test(nuc)) nuc = nuc.replace(GEN, '');
  if (nuc.length < 4) continue;
  if (t.includes(nuc) && (!melhor || nuc.length > melhor.nuc.length)) melhor = { nome: nome, nuc: nuc };
}
if (!melhor) return [];
let quartos = 0;
const mq = t.match(/(\d)\s*(quartos?|qts?|qto|dormitorios?)/);
if (mq) quartos = parseInt(mq[1], 10);
let modo = 0;
if (/alug|locac|locar/.test(t)) modo = 1;
else if (/venda|vender|comprar|compra/.test(t)) modo = 2;
return [{ json: { condominio: melhor.nome, quartos: quartos, modo: modo } }];
