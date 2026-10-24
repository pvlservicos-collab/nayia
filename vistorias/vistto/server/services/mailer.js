// Envio de e-mails (SMTP via nodemailer). Sem SMTP configurado, os e-mails ficam na Caixa de saída do painel.
const path = require('path');
const nodemailer = require('nodemailer');
const { run, get, uid, J, UPLOAD_DIR } = require('../db');
const cfg = require('../config');

function esc(s) { return String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c])); }

function fill(tpl, vars) { return String(tpl || '').replace(/\{\{\s*(\w+)\s*\}\}/g, (_, k) => (vars[k] ?? '')); }

function layout(bodyText, vars) {
  const c = cfg.company();
  const color = c.color || '#0F1827';
  const html = esc(bodyText).replace(/\n/g, '<br>').replace(/(https?:\/\/[^\s<]+)/g, (u) => `<a href="${u}" style="color:${color};font-weight:600">${u}</a>`);
  const btn = vars.link ? `<p style="margin:28px 0 8px"><a href="${esc(vars.link)}" style="background:${color};color:#fff;text-decoration:none;padding:14px 22px;border-radius:10px;font-weight:600;display:inline-block">Abrir laudo de vistoria</a></p>` : '';
  return `<!doctype html><html><body style="margin:0;background:#F3F5F9;font-family:Poppins,Arial,sans-serif;color:#1E293B">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#F3F5F9;padding:32px 12px"><tr><td align="center">
  <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;background:#fff;border-radius:16px;overflow:hidden;box-shadow:0 6px 24px rgba(15,24,39,.08)">
    <tr><td style="background:${color};padding:22px 28px;color:#fff">
      <div style="font-size:18px;font-weight:700;letter-spacing:.3px">${esc(c.name)}</div>
      <div style="font-size:12px;opacity:.9">${esc(vars.titulo || 'Laudo de vistoria')}</div>
    </td></tr>
    <tr><td style="padding:28px;font-size:14px;line-height:1.65">${html}${btn}</td></tr>
    <tr><td style="padding:16px 28px;background:#F8FAFC;font-size:11px;color:#64748B">${esc(c.legal_name || c.name)} · CNPJ ${esc(c.cnpj)} · CRECI ${esc(c.creci)}<br>${esc(c.address)} · ${esc((c.phones || []).join(' · '))}</td></tr>
  </table></td></tr></table></body></html>`;
}

function transport() {
  const s = cfg.integrations().smtp;
  if (!s.host) return null;
  return nodemailer.createTransport({ host: s.host, port: s.port, secure: s.secure, auth: s.user ? { user: s.user, pass: s.pass } : undefined });
}

async function deliver(id) {
  const e = get('SELECT * FROM emails WHERE id=?', id);
  if (!e) return;
  const t = transport();
  if (!t) { run("UPDATE emails SET status='sem_smtp', error=? WHERE id=?", 'SMTP não configurado — e-mail guardado na caixa de saída', id); return; }
  const s = cfg.integrations().smtp;
  try {
    const attachments = J(e.attachments, []).map((a) => ({ filename: a.filename, path: path.join(UPLOAD_DIR, a.file) }));
    await t.sendMail({ from: s.from || s.user, to: e.to_addr, subject: e.subject, html: e.html, attachments });
    run("UPDATE emails SET status='enviado', error=NULL, sent_at=datetime('now') WHERE id=?", id);
  } catch (err) {
    run("UPDATE emails SET status='erro', error=? WHERE id=?", String(err.message || err), id);
  }
}

async function queue({ to, subject, body, vars = {}, inspection_id = null, kind = null, attachments = [] }) {
  const id = uid();
  run('INSERT INTO emails(id,inspection_id,kind,to_addr,subject,html,attachments) VALUES(?,?,?,?,?,?,?)', id, inspection_id, kind, to, subject, layout(body, vars), JSON.stringify(attachments));
  await deliver(id);
  return id;
}

// Envia um modelo (initial | final | signed) para todos os destinatários
async function sendTemplate(kind, ins, recipients, link, attachments = []) {
  const t = cfg.emails()[kind];
  const c = cfg.company();
  const p = ins.property || {};
  const imovel = p.identification || [p.street, p.number, p.complement].filter(Boolean).join(', ') || `Vistoria #${ins.code}`;
  const ids = [];
  for (const r of recipients) {
    if (!r.email) continue;
    const vars = { nome: r.name || '', imovel, link, empresa: c.name, codigo: ins.code, tipo: ins.typeLabel, titulo: (cfg.TYPES[ins.type] || {}).title };
    ids.push(await queue({ to: r.email, subject: fill(t.subject, vars), body: fill(t.body, vars), vars, inspection_id: ins.id, kind, attachments }));
  }
  return ids;
}

module.exports = { queue, deliver, sendTemplate, fill, layout };
