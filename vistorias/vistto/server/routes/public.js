// Rotas públicas: laudo compartilhável, PDF, contestação e webhook da ClickSign
const express = require('express');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const multer = require('multer');
const { get, all, run, uid, J, logEvent, UPLOAD_DIR } = require('../db');
const cfg = require('../config');
const M = require('../model');
const laudo = require('../services/laudo');
const wf = require('../services/workflow');
const mailer = require('../services/mailer');
const pdf = require('../services/pdf');
const { verify } = require('../auth');

const r = express.Router();
const upload = multer({ dest: path.join(UPLOAD_DIR, '.tmp'), limits: { fileSize: 80 * 1024 * 1024, files: 20 } });

function byToken(tok) { return get('SELECT id, status FROM inspections WHERE public_token=?', tok); }

// Pré-visualização do admin (antes da aprovação) usa ?t=<token de login>
function canPreview(req, i) {
  if (['aprovada', 'em_assinatura', 'assinada'].includes(i.status)) return true;
  const c = (req.get('cookie') || '').split(';').map((s) => s.trim()).find((s) => s.startsWith('vt='));
  const data = verify(req.query.t || (c && decodeURIComponent(c.slice(3))));
  if (data) return true;
  // o renderizador de PDF usa um token de renderização assinado
  return !!req.query.rt && req.query.rt === require('../services/pdf').renderToken(req.params.token);
}

r.get('/v/:token', async (req, res, next) => {
  try {
    const i = byToken(req.params.token);
    if (!i) return res.status(404).send(notFound());
    if (!canPreview(req, i)) return res.status(403).send(notFound('Este laudo ainda está em revisão.'));
    const ins = M.loadInspection(i.id, { withEvents: false });
    res.set('Cache-Control', 'no-store');
    res.send(await laudo.renderLaudo(ins, { print: req.query.print === '1', baseUrl: cfg.baseUrl(req) }));
  } catch (e) { next(e); }
});

r.get('/v/:token/pdf', async (req, res, next) => {
  try {
    const i = get('SELECT * FROM inspections WHERE public_token=?', req.params.token);
    if (!i) return res.status(404).send(notFound());
    if (!canPreview(req, i)) return res.status(403).send(notFound('Este laudo ainda está em revisão.'));
    let file = i.signed_pdf;
    if (!file || !fs.existsSync(path.join(UPLOAD_DIR, file))) {
      file = `laudo-${i.code}-${Date.now()}.pdf`;
      await pdf.renderLaudoPdf(i.public_token, file);
    }
    res.download(path.join(UPLOAD_DIR, file), `Laudo-vistoria-${i.code}${i.signed_pdf ? '-assinado' : ''}.pdf`);
  } catch (e) { res.status(500).send(notFound(`Não foi possível gerar o PDF: ${e.message}`)); }
});

r.get('/c/:token', (req, res) => {
  const i = get('SELECT id FROM inspections WHERE contest_token=?', req.params.token);
  if (!i) return res.status(404).send(notFound());
  res.send(laudo.renderContest(M.loadInspection(i.id, { withEvents: false })));
});
r.post('/c/:token', upload.array('files', 20), async (req, res) => {
  const i = get('SELECT id, code FROM inspections WHERE contest_token=?', req.params.token);
  if (!i) return res.status(404).send(notFound());
  const ins = M.loadInspection(i.id, { withEvents: false });
  const b = req.body || {};
  if (!b.message || !b.email) return res.send(laudo.renderContest(ins, { error: 'Preencha e-mail e a descrição.' }));
  const already = get('SELECT id FROM contestations WHERE inspection_id=? AND lower(email)=lower(?)', i.id, b.email);
  if (already) { (req.files || []).forEach((f) => fs.unlink(f.path, () => {})); return res.send(laudo.renderContest(ins, { error: 'Já existe uma contestação registrada com este e-mail. Será considerado apenas o primeiro chamado.' })); }
  const files = (req.files || []).map((f) => { const id = uid(); const ext = path.extname(f.originalname) || '.jpg'; const name = `contest-${id}${ext}`; fs.renameSync(f.path, path.join(UPLOAD_DIR, name)); return { url: `/media/${name}`, name: f.originalname, mime: f.mimetype }; });
  run('INSERT INTO contestations(id,inspection_id,name,email,phone,room,message,files) VALUES(?,?,?,?,?,?,?,?)', uid(), i.id, b.name || '', b.email, b.phone || '', b.room || '', b.message, JSON.stringify(files));
  logEvent(i.id, 'contestacao', `Nova contestação recebida de ${b.name || b.email}`);
  for (const a of all("SELECT email FROM users WHERE role='admin' AND active=1")) await mailer.queue({ to: a.email, subject: `Nova contestação — laudo #${i.code}`, body: `${b.name} (${b.email}) abriu uma contestação${b.room ? ` sobre "${b.room}"` : ''}:\n\n${b.message}`, inspection_id: i.id, kind: 'contestacao' });
  res.send(laudo.renderContest(ins, { done: true }));
});

// Webhook ClickSign: valida HMAC (se configurado) e sincroniza o envelope
r.post('/api/webhooks/clicksign', express.raw({ type: '*/*', limit: '5mb' }), async (req, res) => {
  const raw = Buffer.isBuffer(req.body) ? req.body : Buffer.from(JSON.stringify(req.body || {}));
  const secret = cfg.integrations().clicksign.webhook_secret;
  if (secret) {
    const got = (req.get('content-hmac') || '').replace(/^sha256=/, '');
    const exp = crypto.createHmac('sha256', secret).update(raw).digest('hex');
    if (got !== exp) return res.status(401).json({ error: 'HMAC inválido' });
  }
  res.json({ ok: true });
  try {
    const txt = raw.toString();
    const rows = all("SELECT id, clicksign FROM inspections WHERE status='em_assinatura'");
    for (const row of rows) {
      const cs = J(row.clicksign);
      if (cs.envelope_id && (txt.includes(cs.envelope_id) || (cs.document_id && txt.includes(cs.document_id)))) await wf.syncClicksign(row.id, cfg.baseUrl(req));
    }
  } catch (e) { console.error('webhook clicksign', e); }
});

function notFound(msg = 'Laudo não encontrado.') {
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Laudo</title><body style="font-family:system-ui;display:grid;place-items:center;height:100vh;margin:0;background:#0F1827;color:#E2E8F0"><div style="text-align:center"><div style="font-size:48px">🔎</div><p>${msg}</p></div></body>`;
}

module.exports = r;
