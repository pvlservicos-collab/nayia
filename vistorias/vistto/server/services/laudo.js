// Renderização do LAUDO PÚBLICO (link compartilhável e base do PDF)
const QRCode = require('qrcode');
const cfg = require('../config');
const { allNcs } = require('../model');

const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const nl = (s) => esc(s).replace(/\n/g, '<br>');

function fmtDate(iso, withTime = true) {
  if (!iso) return '';
  const d = new Date(iso.includes('T') || iso.includes('Z') ? iso : iso.replace(' ', 'T') + 'Z');
  if (isNaN(d)) return iso;
  const tz = cfg.params().timezone || 'America/Sao_Paulo';
  const o = { timeZone: tz, day: '2-digit', month: '2-digit', year: '2-digit' };
  if (withTime) Object.assign(o, { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
  return new Intl.DateTimeFormat('pt-BR', o).format(d).replace(',', '');
}
function fmtLong(iso) {
  if (!iso) return '';
  const d = new Date(iso.includes('T') ? iso : iso.replace(' ', 'T') + 'Z');
  return new Intl.DateTimeFormat('pt-BR', { timeZone: cfg.params().timezone || 'America/Sao_Paulo', day: '2-digit', month: 'long', year: 'numeric' }).format(d);
}

function markers(m) {
  return (m.markers || []).map((k, i) => `<span class="mk" style="left:${(k.x * 100).toFixed(2)}%;top:${(k.y * 100).toFixed(2)}%;width:${((k.r || 0.07) * 200).toFixed(2)}%"><b>${i + 1}</b></span>`).join('');
}

let LAZY = 'lazy';
function mediaTile(m, extraLabel = '') {
  if (m.kind === 'audio') return '';
  const date = esc(fmtDate(m.taken_at));
  if (m.kind === 'video') {
    return `<figure class="ph vid" data-full="${esc(m.url)}" data-kind="video" data-cap="${esc(extraLabel)}"><video src="${esc(m.url)}#t=0.5" preload="metadata" muted playsinline></video><span class="dt">${date}</span><span class="play"></span>${extraLabel ? `<figcaption>${esc(extraLabel)}</figcaption>` : ''}</figure>`;
  }
  return `<figure class="ph" data-full="${esc(m.url)}" data-kind="photo" data-cap="${esc(extraLabel)}"><div class="imgw"><img src="${esc(m.url)}" loading="${LAZY}" alt="">${markers(m)}</div><span class="dt">${date}</span>${extraLabel ? `<figcaption>${esc(extraLabel)}</figcaption>` : ''}</figure>`;
}
function gallery(list, labelFn) {
  const v = (list || []).filter((m) => m.kind !== 'audio');
  if (!v.length) return '';
  return `<div class="gal">${v.map((m) => mediaTile(m, labelFn ? labelFn(m) : '')).join('')}</div>`;
}
function audios(list, print) {
  const a = (list || []).filter((m) => m.kind === 'audio');
  if (!a.length) return '';
  return a.map((m) => `<div class="audio">${print ? '' : `<audio controls preload="none" src="${esc(m.url)}"></audio>`}${m.transcript ? `<div class="tr"><span>Relato do vistoriador:</span> “${esc(m.transcript)}”</div>` : ''}</div>`).join('');
}

function stateDot(cond) {
  const c = cfg.CONDITIONS[cond];
  if (!c) return '';
  return `<span class="dot" style="background:${c.color}"></span><b>${esc(c.long)}</b>`;
}

function personLine(p) {
  return [p.name && `<b>${esc(p.name)}</b>`, p.cpf && `CPF ${esc(p.cpf)}`, p.rg && `RG ${esc(p.rg)}`, p.email && esc(p.email), p.phone && esc(p.phone)].filter(Boolean).join(' · ');
}

const ICONS = {
  build: '<svg viewBox="0 0 24 24"><path d="M5 3h14v18h-5v-4h-4v4H5V3zm3 3v2h2V6H8zm6 0v2h2V6h-2zm-6 4v2h2v-2H8zm6 0v2h2v-2h-2z"/></svg>',
  note: '<svg viewBox="0 0 24 24"><path d="M4 3h16v12l-6 6H4V3zm10 12v5l5-5h-5z"/></svg>',
  home: '<svg viewBox="0 0 24 24"><path d="M12 3 1 12h3v9h6v-6h4v6h6v-9h3L12 3z"/></svg>',
  people: '<svg viewBox="0 0 24 24"><path d="M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm8 0a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM1 20c0-3.3 3.6-6 8-6s8 2.7 8 6v1H1v-1zm17-5.9c2.9.4 5 2.4 5 4.9v1h-4v-1c0-1.9-.4-3.4-1-4.9z"/></svg>',
  alert: '<svg viewBox="0 0 24 24"><path d="M12 2 1 21h22L12 2zm-1 7h2v6h-2V9zm0 8h2v2h-2v-2z"/></svg>',
  bolt: '<svg viewBox="0 0 24 24"><path d="M13 2 4 14h6l-1 8 9-12h-6l1-8z"/></svg>',
  pen: '<svg viewBox="0 0 24 24"><path d="M3 17.2V21h3.8L17.8 10 14 6.2 3 17.2zM20.7 7a1 1 0 0 0 0-1.4l-2.3-2.3a1 1 0 0 0-1.4 0L15.2 5 19 8.8 20.7 7z"/></svg>',
};
const H = (icon, title, id = '') => `<h2 class="sec" ${id ? `id="${id}"` : ''}><i>${ICONS[icon]}</i>${esc(title)}</h2>`;

async function renderLaudo(ins, { print = false, baseUrl = '' } = {}) {
  const c = cfg.company();
  const t = cfg.texts();
  const color = c.color || '#FF1F7D';
  const p = ins.property || {};
  const pa = ins.parties || {};
  const type = cfg.TYPES[ins.type] || cfg.TYPES.entrada;
  const addr = [p.type && p.type.toUpperCase(), p.street, p.number, p.complement, p.district, p.city, p.state].filter(Boolean).join(' - ').toUpperCase();
  const mapQ = encodeURIComponent([p.street, p.number, p.district, p.city, p.state, p.cep].filter(Boolean).join(', '));
  const link = `${baseUrl}/v/${ins.public_token}`;
  const mediaLink = `${link}#fotos`;
  const contestLink = `${baseUrl}/c/${ins.contest_token}`;
  const qrOpts = { margin: 0, width: 220, color: { dark: '#111111', light: '#ffffff' } };
  const [qrMedia, qrContest] = await Promise.all([QRCode.toDataURL(mediaLink, qrOpts), QRCode.toDataURL(contestLink, qrOpts)]);
  LAZY = print ? 'eager' : 'lazy'; // definido após o await: o restante da renderização é síncrono
  const ncs = allNcs(ins);
  const allPhotos = [];
  ins.rooms.forEach((r) => {
    r.media.forEach((m) => allPhotos.push({ ...m, _room: r.name, _label: r.name }));
    r.ncs.forEach((n) => n.media.forEach((m) => allPhotos.push({ ...m, _room: r.name, _label: `${r.name} · ${n.title}` })));
    r.items.forEach((it) => {
      it.media.forEach((m) => allPhotos.push({ ...m, _room: r.name, _label: `${r.name} · ${it.name}` }));
      it.ncs.forEach((n) => n.media.forEach((m) => allPhotos.push({ ...m, _room: r.name, _label: `${r.name} · ${it.name} · ${n.title}` })));
    });
  });
  const visualCount = allPhotos.filter((m) => m.kind !== 'audio').length;
  const signed = ins.status === 'assinada';

  // ---------- Ambientes ----------
  const roomsHtml = ins.rooms.map((r, ri) => {
    const n = ri + 1;
    const roomNcs = r.ncs.length ? `<div class="nc"><div class="ncl"><span class="dot red"></span><b>Inconformidade:</b></div><ol>${r.ncs.map((x) => `<li><b>${esc(x.title)}</b>${x.description ? `<p>${nl(x.description)}</p>` : ''}${gallery(x.media)}</li>`).join('')}</ol></div>` : '';
    const items = r.items.map((it, ii) => {
      const src = it.source && ins.type === 'saida' && cfg.CONDITIONS[it.source.condition] ? `<span class="was">Na entrada: ${esc(cfg.CONDITIONS[it.source.condition].long.toLowerCase())}</span>` : '';
      const st = [it.condition ? stateDot(it.condition) : '', it.quantity ? `<b>Quantidade: ${esc(it.quantity)}</b>` : '', it.functioning ? `<span class="fn ${it.functioning}">${esc(cfg.FUNCTIONING[it.functioning] || '')}</span>` : '', src].filter(Boolean).join(' ');
      const itNcs = it.ncs.length ? `<div class="nc"><div class="ncl"><span class="dot red"></span><b>Inconformidade:</b></div><ol>${it.ncs.map((x) => `<li><b>${esc(x.title)}</b>${x.description ? `<p>${nl(x.description)}</p>` : ''}${gallery(x.media)}</li>`).join('')}</ol></div>` : '';
      return `<div class="item"><div class="it"><span class="num">${n}.${ii + 1}</span> <b>${esc(it.name)}:</b></div>${st ? `<div class="st">${st}</div>` : ''}${it.notes ? `<div class="obs">${nl(it.notes)}</div>` : ''}${audios(it.media, print)}${itNcs}${gallery(it.media)}</div>`;
    }).join('');
    return `<section class="room" id="room-${n}"><h3>${n}. ${esc(r.name)}:</h3>${roomNcs}${items}${r.notes ? `<div class="obs room-obs"><b>Observações do cômodo:</b> ${nl(r.notes)}</div>` : ''}${audios(r.media, print)}${gallery(r.media)}</section>`;
  }).join('');

  // ---------- Avarias (resumo final com cômodo acima do título) ----------
  const avariasHtml = ncs.length ? ncs.map((x, i) => `<div class="av"><div class="avroom">${esc(x.roomIndex)}. ${esc(x.room)}${x.item ? ` <span>›</span> ${esc(x.item)}` : ''}</div><div class="avt"><span class="dot red"></span>${i + 1}. ${esc(x.title)}</div>${x.description ? `<p>${nl(x.description)}</p>` : ''}${gallery(x.media)}</div>`).join('') : '<p class="muted">Nenhuma avaria registrada nesta vistoria.</p>';

  // ---------- Medidores ----------
  const mt = ins.meters || {};
  const meterRow = (k, label) => mt[k] && (mt[k].reading || mt[k].number) ? `<tr><td><b>${label}</b></td><td>${esc(mt[k].number || '—')}</td><td>${esc(mt[k].reading || '—')}</td></tr>` : '';
  const meterRows = meterRow('energia', 'Energia elétrica') + meterRow('agua', 'Água') + meterRow('gas', 'Gás');
  const meterPhotos = (ins.media_general || []).filter((m) => m.scope === 'meter');

  // ---------- Partes ----------
  const group = (label, arr) => (arr || []).filter((x) => x && x.name).length ? `<div class="pg"><div class="pgl">${label}</div>${arr.filter((x) => x && x.name).map((x) => `<div>${personLine(x)}</div>`).join('')}</div>` : '';
  const partiesHtml = group('Locador(es)', pa.locadores) + group('Locatário(s)', pa.locatarios) + group('Fiador(es)', pa.fiadores) + group('Testemunha(s)', pa.testemunhas)
    + (ins.inspector ? `<div class="pg"><div class="pgl">Vistoriador</div><div><b>${esc(ins.inspector.name)}</b>${pa.executed_by ? ` · ${esc(pa.executed_by)}` : ''}</div></div>` : '');

  const signers = ins.signers || [];
  const sigHtml = signers.length ? `<div class="sigs">${signers.map((s) => `<div class="sig ${s.status === 'assinado' ? 'ok' : ''}"><div class="line"></div><b>${esc(s.name)}</b><span>${esc((s.role || '').replace('locatario', 'Locatário(a)').replace('locador', 'Locador(a)').replace('fiador', 'Fiador(a)').replace('testemunha', 'Testemunha'))}${s.cpf ? ` · CPF ${esc(s.cpf)}` : ''}</span><em>${s.status === 'assinado' ? `✔ Assinado eletronicamente em ${esc(fmtDate(s.signed_at))}` : 'Aguardando assinatura'}</em></div>`).join('')}</div>` : '';

  const paramList = `<ul class="params"><li><b style="color:#1D4ED8">NOVO:</b> nunca foi utilizado/imóvel novo.</li><li><b style="color:#15803D">BOM:</b> apresenta pouco desgaste.</li><li><b style="color:#CA8A04">REGULAR:</b> apresenta sinais de desgastes aparentes.</li><li><b style="color:#DC2626">MAU:</b> apresenta grandes sinais de deterioração.</li></ul>`;
  const bullets = (txt) => `<ul>${String(txt || '').split('\n').filter(Boolean).map((l) => `<li>${esc(l).replace(/\b(NOVA|BOM|REGULAR)\b/g, (w) => `<b class="kw-${w.toLowerCase()}">${w}</b>`)}</li>`).join('')}</ul>`;
  const contestTxt = String(t.contest || '').split('\n').filter(Boolean).map((l) => `<p>${esc(l)}</p>`).join('');
  const obsTxt = String(t.observations || '').split('\n').filter(Boolean).map((l) => `<p>${esc(l)}</p>`).join('');

  const photosTab = ins.rooms.map((r, ri) => {
    const list = allPhotos.filter((m) => m._room === r.name && m.kind !== 'audio');
    return list.length ? `<h3 class="gh">${ri + 1}. ${esc(r.name)} <small>${list.length} mídia(s)</small></h3>${gallery(list, (m) => m._label.split(' · ').slice(1).join(' · '))}` : '';
  }).join('') + (meterPhotos.length ? `<h3 class="gh">Medidores</h3>${gallery(meterPhotos, (m) => m.caption || '')}` : '');

  const ncTab = ins.rooms.map((r, ri) => {
    const list = ncs.filter((x) => x.roomIndex === ri + 1);
    if (!list.length) return '';
    return `<div class="ncroom"><h3 class="gh">${ri + 1}. ${esc(r.name)} <small>${list.length} inconformidade(s)</small></h3>${list.map((x) => `<div class="av"><div class="avroom">${esc(r.name)}${x.item ? ` › ${esc(x.item)}` : ''}</div><div class="avt"><span class="dot red"></span>${esc(x.title)}</div>${x.description ? `<p>${nl(x.description)}</p>` : ''}${gallery(x.media)}</div>`).join('')}</div>`;
  }).join('') || '<p class="muted">Nenhuma inconformidade registrada.</p>';

  const logo = c.logo ? `<img src="${esc(c.logo)}" alt="">` : `<span class="initials">${esc((c.name || 'V').split(/\s+/).map((w) => w[0]).slice(0, 2).join(''))}</span>`;

  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(type.title)} · ${esc(p.identification || '#' + ins.code)}</title>
<meta name="robots" content="noindex">
<meta property="og:title" content="${esc(type.title)} — ${esc(p.identification || '')}"><meta property="og:description" content="${esc(c.name)} · Laudo nº ${ins.code}">
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700;900&display=swap" rel="stylesheet">
<link rel="stylesheet" href="/laudo/laudo.css">
<style>:root{--brand:${esc(color)}}</style></head>
<body class="${print ? 'print' : ''}">
<div class="sheet">
  ${print ? '' : `<div class="toolbar"><div class="tb-left">${signed ? '<span class="badge ok">✔ Laudo assinado</span>' : ins.status === 'em_assinatura' ? '<span class="badge wait">Aguardando assinaturas</span>' : ''}</div><div class="tb-right">
    <button class="btn" id="share">${'<svg viewBox="0 0 24 24"><path d="M18 16a3 3 0 0 0-2.4 1.2l-6.7-3.4a3 3 0 0 0 0-1.6l6.7-3.4A3 3 0 1 0 15 7l-6.7 3.4a3 3 0 1 0 0 3.2L15 17a3 3 0 1 0 3-1z"/></svg>'}Compartilhar</button>
    <a class="btn" href="/v/${esc(ins.public_token)}/pdf" target="_blank">${'<svg viewBox="0 0 24 24"><path d="M6 2h9l5 5v15H6V2zm8 1.5V8h4.5L14 3.5zM8 13h8v2H8v-2zm0 4h8v2H8v-2z"/></svg>'}${signed ? 'Baixar PDF assinado' : 'Imprimir / Gerar PDF'}</a></div></div>`}
  <header class="hd">
    <div class="hd-top"><div class="logo">${logo}</div>
      <div class="co"><b>${esc(c.name)}</b><span>CNPJ: ${esc(c.cnpj)} &nbsp;CRECI: ${esc(c.creci)}</span><span>${esc(c.address)}</span></div>
      <div class="ct">${(c.phones || []).map((x) => `<span>☎ ${esc(x)}</span>`).join('')}${c.email ? `<span>✉ ${esc(c.email)}</span>` : ''}${c.site ? `<span>🔗 ${esc(c.site)}</span>` : ''}</div></div>
    <h1>${esc(type.title)}</h1>
  </header>
  <div class="meta"><span>Laudo nº <b>${String(ins.code).padStart(4, '0')}</b></span><span>Vistoria realizada em <b>${esc(fmtLong(ins.inspected_at || ins.created_at))}</b></span>${ins.inspector ? `<span>Vistoriador: <b>${esc(ins.inspector.name)}</b></span>` : ''}<span>${ins.stats.rooms} ambientes · ${ins.stats.photos} fotos · ${ins.stats.ncs} inconformidades</span></div>
  ${print ? '' : `<nav class="tabs" id="tabs"><button data-tab="laudo" class="on">Laudo completo</button><button data-tab="fotos">Fotos <i>${visualCount}</i></button><button data-tab="inconf">Inconformidades <i class="r">${ncs.length}</i></button></nav>`}

  <main class="pane on" id="tab-laudo">
    ${H('build', 'Imóvel')}
    <div class="kv"><div><b>IDENTIFICAÇÃO:</b> ${esc(p.identification || '—')}</div><div><b>CEP:</b> ${esc(p.cep || '—')}</div><div><b>ESTADO:</b> ${esc(p.state || '—')}</div><div><b>ENDEREÇO:</b> ${esc(addr || '—')}</div><div><b>FINALIDADE:</b> ${esc((p.purpose || '—').toUpperCase())}</div><div class="two"><span><b>METRAGEM:</b> ${esc(p.area ? `${p.area} M²` : '—')}</span><span><b>MOBILIADO:</b> ${esc((p.furnished || '—').toUpperCase())}</span></div>${p.iptu ? `<div><b>INSCRIÇÃO IPTU:</b> ${esc(p.iptu)}</div>` : ''}</div>
    ${mapQ ? `<div class="map"><iframe loading="lazy" src="https://maps.google.com/maps?q=${mapQ}&z=15&output=embed" referrerpolicy="no-referrer-when-downgrade"></iframe></div>` : ''}
    ${partiesHtml ? H('people', 'Partes envolvidas') + `<div class="parties">${partiesHtml}</div>` : ''}
    ${H('note', 'Introdução')}
    <p class="just">${nl(t.intro)}</p>
    <h4>Parâmetros de Avaliação/Condição do Imóvel/Estado</h4>${paramList}
    <h4>Critérios de avaliação de pintura</h4>${bullets(t.paint)}
    <h4>Critérios de avaliação da limpeza</h4>${bullets(t.cleaning)}
    <h4>Contestação</h4><div class="contest just">${contestTxt}</div>
    ${meterRows || meterPhotos.length ? H('bolt', 'Leitura dos medidores') + (meterRows ? `<table class="tbl"><tr><th>Medidor</th><th>Nº / Matrícula</th><th>Leitura</th></tr>${meterRows}</table>` : '') + gallery(meterPhotos, (m) => m.caption || '') : ''}
    ${H('home', 'Ambientes')}
    ${roomsHtml || '<p class="muted">Nenhum ambiente registrado.</p>'}
    ${H('alert', `Avarias e inconformidades (${ncs.length})`, 'avarias')}
    <div class="avlist">${avariasHtml}</div>
    ${H('note', 'Observações')}
    <div class="just obsx">${obsTxt}${ins.general_notes ? `<p>${nl(ins.general_notes)}</p>` : ''}</div>
    ${sigHtml ? H('pen', 'Assinaturas') + sigHtml : ''}
    <div class="qrs">
      <div class="qr"><div class="qrh">QRCODE PARA ACESSO ÀS MÍDIAS</div><div class="qrb"><img src="${qrMedia}" alt=""><a href="${esc(mediaLink)}">${esc(mediaLink.replace(/^https?:\/\//, ''))}</a></div></div>
      <div class="qr"><div class="qrh">QRCODE PARA REALIZAR CONTESTAÇÃO</div><div class="qrb"><img src="${qrContest}" alt=""><a href="${esc(contestLink)}">${esc(contestLink.replace(/^https?:\/\//, ''))}</a></div></div>
    </div>
  </main>
  ${print ? '' : `<main class="pane" id="tab-fotos">${H('home', `Todas as fotos (${visualCount})`)}${photosTab || '<p class="muted">Sem fotos.</p>'}</main>
  <main class="pane" id="tab-inconf">${H('alert', `Inconformidades por cômodo (${ncs.length})`)}${ncTab}</main>`}
  <footer class="ft">Documento gerado eletronicamente por ${esc(c.name)} · ${esc(cfg.APP_NAME)} · ${esc(fmtDate(new Date().toISOString()))}</footer>
</div>
${print ? '' : `<div class="lb" id="lb"><button class="x" aria-label="Fechar">×</button><button class="pv" aria-label="Anterior">‹</button><div class="lbc"></div><button class="nx" aria-label="Próxima">›</button><div class="lbcap"></div></div><script src="/laudo/laudo.js" defer></script>`}
</body></html>`;
}

function renderContest(ins, { done = false, error = '' } = {}) {
  const c = cfg.company();
  const p = ins.property || {};
  const rooms = ins.rooms.map((r) => `<option>${esc(r.name)}</option>`).join('');
  return `<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Contestação · Laudo ${ins.code}</title>
<link href="https://fonts.googleapis.com/css2?family=Roboto:wght@400;500;700&display=swap" rel="stylesheet"><link rel="stylesheet" href="/laudo/laudo.css"><style>:root{--brand:${esc(c.color || '#FF1F7D')}}</style></head>
<body><div class="sheet narrow"><header class="hd"><h1 style="font-size:20px">CONTESTAÇÃO DE VISTORIA</h1></header><main class="pane on" style="padding:22px">
<p><b>${esc(p.identification || '')}</b><br><span class="muted">Laudo nº ${ins.code} · ${esc(c.name)}</span></p>
${done ? '<div class="okbox">Contestação enviada com sucesso. O retorno será feito por e-mail em até 72 horas.</div>' : `
${error ? `<div class="errbox">${esc(error)}</div>` : ''}
<form method="post" enctype="multipart/form-data" class="cform">
<label>Seu nome<input name="name" required></label>
<label>E-mail<input name="email" type="email" required></label>
<label>Telefone<input name="phone"></label>
<label>Ambiente<select name="room"><option value="">Geral</option>${rooms}</select></label>
<label>Descreva a divergência (apenas o que não consta no laudo)<textarea name="message" rows="6" required></textarea></label>
<label>Fotos (opcional)<input type="file" name="files" accept="image/*,video/*" multiple></label>
<button class="btn primary" type="submit">Enviar contestação</button>
<p class="muted small">Será considerado apenas o primeiro chamado. Envie todas as divergências de uma só vez.</p>
</form>`}
<p><a href="/v/${esc(ins.public_token)}">← Voltar ao laudo</a></p></main></div></body></html>`;
}

module.exports = { renderLaudo, renderContest, fmtDate };
