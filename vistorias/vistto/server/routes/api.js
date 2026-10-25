// API REST (app mobile + painel administrativo)
const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { all, get, run, tx, J, uid, hashPassword, checkPassword, getSetting, setSetting, logEvent, nextCode, UPLOAD_DIR } = require('../db');
const { auth, admin, sign } = require('../auth');
const cfg = require('../config');
const M = require('../model');
const ai = require('../services/ai');
const wf = require('../services/workflow');
const mailer = require('../services/mailer');
const clicksign = require('../services/clicksign');

const r = express.Router();
const upload = multer({ dest: path.join(UPLOAD_DIR, '.tmp'), limits: { fileSize: 300 * 1024 * 1024 } });
const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch((e) => { console.error(e); res.status(e.status || 500).json({ error: e.message || 'Erro' }); });

const EXT = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp', 'image/heic': 'heic', 'video/mp4': 'mp4', 'video/quicktime': 'mov', 'video/webm': 'webm', 'audio/webm': 'webm', 'audio/mp4': 'm4a', 'audio/mpeg': 'mp3', 'audio/ogg': 'ogg', 'audio/wav': 'wav', 'application/pdf': 'pdf' };
function storeFile(tmp, id, mime, original) {
  const ext = EXT[(mime || '').split(';')[0]] || (path.extname(original || '').slice(1) || 'bin');
  const name = `${id}.${ext}`;
  fs.renameSync(tmp, path.join(UPLOAD_DIR, name));
  return name;
}
function canSee(req, insId) {
  if (req.user.role === 'admin') return true;
  const i = get('SELECT inspector_id FROM inspections WHERE id=?', insId);
  return !i || i.inspector_id === req.user.id;
}

// ---------------- Auth ----------------
r.post('/auth/login', (req, res) => {
  const { email, password } = req.body || {};
  const u = get('SELECT * FROM users WHERE lower(email)=lower(?) AND active=1', String(email || '').trim());
  if (!u || !checkPassword(String(password || ''), u.password)) return res.status(401).json({ error: 'E-mail ou senha inválidos' });
  const tok = sign(u);
  res.setHeader('Set-Cookie', `vt=${encodeURIComponent(tok)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${60 * 60 * 24 * 60}`);
  res.json({ token: tok, user: { id: u.id, name: u.name, email: u.email, role: u.role } });
});
r.post('/auth/logout', (req, res) => { res.setHeader('Set-Cookie', 'vt=; Path=/; Max-Age=0'); res.json({ ok: true }); });
r.get('/auth/me', auth(), (req, res) => res.json({ user: req.user }));

// ---------------- App (vistoriador) ----------------
r.get('/app/bootstrap', auth(), (req, res) => {
  const c = cfg.company();
  res.json({
    user: req.user,
    app_name: cfg.APP_NAME,
    company: { name: c.name, color: c.color, logo: c.logo },
    types: cfg.TYPES, conditions: cfg.CONDITIONS, functioning: cfg.FUNCTIONING,
    vocab: {
      rooms: [...new Set([...cfg.ROOM_NAMES, ...all("SELECT name FROM vocab WHERE kind='room' ORDER BY uses DESC, name").map((x) => x.name)])],
      items: [...new Set([...all("SELECT name FROM vocab WHERE kind='item' ORDER BY uses DESC, name").map((x) => x.name), ...cfg.ITEM_NAMES])],
      customRooms: all("SELECT name FROM vocab WHERE kind='room' ORDER BY uses DESC, name").map((x) => x.name),
    },
    templates: all('SELECT id,name,type,rooms FROM templates WHERE active=1 ORDER BY name').map((t) => ({ ...t, rooms: J(t.rooms, []) })),
    witnesses: M.savedWitnesses(),
    params: cfg.params(),
  });
});

r.get('/app/inspections', auth(), (req, res) => {
  const list = req.user.role === 'admin' ? M.listInspections('i.inspector_id=? OR 1=1', [req.user.id]) : M.listInspections('i.inspector_id=?', [req.user.id]);
  res.json(list.slice(0, 200));
});

r.post('/app/sync', auth(), wrap(async (req, res) => {
  const p = req.body;
  if (!p || !p.id) return res.status(400).json({ error: 'Dados inválidos' });
  // vocabulário novo vira lista permanente
  if (cfg.params().app_can_add_vocab) {
    for (const rm of p.rooms || []) {
      const base = rm.name.replace(/\s+\d+$/, '').trim();
      if (base && !cfg.ROOM_NAMES.includes(base)) run("INSERT INTO vocab(id,kind,name,uses) VALUES(?,?,?,1) ON CONFLICT(kind,name) DO UPDATE SET uses=uses+1", uid(), 'room', base);
      for (const it of rm.items || []) if (it.name && !cfg.ITEM_NAMES.includes(it.name)) run("INSERT INTO vocab(id,kind,name,uses) VALUES(?,?,?,1) ON CONFLICT(kind,name) DO UPDATE SET uses=uses+1", uid(), 'item', it.name.trim());
    }
  }
  res.json(M.syncFromApp(req.user, p));
}));

r.post('/app/inspections/:id/submit', auth(), wrap(async (req, res) => {
  const i = get('SELECT * FROM inspections WHERE id=?', req.params.id);
  if (!i) return res.status(404).json({ error: 'Vistoria não encontrada' });
  if (!canSee(req, i.id)) return res.status(403).json({ error: 'Sem acesso' });
  if (['rascunho', 'enviada'].includes(i.status)) {
    run("UPDATE inspections SET status='enviada', review_stage=1, submitted_at=datetime('now'), updated_at=datetime('now') WHERE id=?", i.id);
    logEvent(i.id, 'enviada', 'Vistoria enviada pelo vistoriador para aprovação', req.user.id);
    const admins = all("SELECT email,name FROM users WHERE role='admin' AND active=1");
    for (const a of admins) await mailer.queue({ to: a.email, subject: `Nova vistoria para aprovação — #${i.code}`, body: `Olá, ${a.name}!\n\n${req.user.name} enviou a vistoria #${i.code} para aprovação.\n\nAcesse o painel: ${cfg.baseUrl(req)}/admin/#/vistorias/${i.id}`, inspection_id: i.id, kind: 'interno' });
  }
  res.json({ ok: true });
}));

r.post('/vocab', auth(), (req, res) => {
  const { kind, name } = req.body || {};
  if (!['room', 'item'].includes(kind) || !name) return res.status(400).json({ error: 'Dados inválidos' });
  run("INSERT INTO vocab(id,kind,name,uses) VALUES(?,?,?,1) ON CONFLICT(kind,name) DO UPDATE SET uses=uses+1", uid(), kind, String(name).trim());
  res.json({ ok: true });
});
r.get('/vocab', auth(), (req, res) => res.json(all('SELECT * FROM vocab ORDER BY kind, uses DESC, name')));
r.delete('/vocab/:id', auth(), admin, (req, res) => { run('DELETE FROM vocab WHERE id=?', req.params.id); res.json({ ok: true }); });

// ---------------- Mídias ----------------
r.post('/media', auth(), upload.single('file'), wrap(async (req, res) => {
  const b = req.body || {};
  const id = b.id || uid();
  if (b.inspection_id && !canSee(req, b.inspection_id)) return res.status(403).json({ error: 'Sem acesso' });
  const existing = get('SELECT * FROM media WHERE id=?', id);
  let file = existing ? existing.file : null;
  if (req.file) {
    if (existing) fs.unlinkSync(req.file.path); else file = storeFile(req.file.path, id, req.file.mimetype, req.file.originalname);
  }
  if (!file) return res.status(400).json({ error: 'Arquivo ausente' });
  const kind = b.kind || (req.file && req.file.mimetype.startsWith('video') ? 'video' : req.file && req.file.mimetype.startsWith('audio') ? 'audio' : 'photo');
  if (existing) {
    run('UPDATE media SET room_id=?, item_id=?, nc_id=?, scope=?, markers=?, transcript=?, caption=?, position=? WHERE id=?', b.room_id || null, b.item_id || null, b.nc_id || null, b.scope || existing.scope, b.markers || existing.markers, b.transcript ?? existing.transcript, b.caption ?? existing.caption, Number(b.position || existing.position || 0), id);
  } else {
    run('INSERT INTO media(id,inspection_id,room_id,item_id,nc_id,scope,kind,file,mime,size,taken_at,transcript,markers,caption,position) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      id, b.inspection_id || null, b.room_id || null, b.item_id || null, b.nc_id || null, b.scope || 'room', kind, file, req.file ? req.file.mimetype : null, req.file ? req.file.size : 0,
      b.taken_at || new Date().toISOString(), b.transcript || null, b.markers || '[]', b.caption || null, Number(b.position || 0));
  }
  res.json(M.mediaRow(get('SELECT * FROM media WHERE id=?', id)));
}));

r.patch('/media/:id', auth(), (req, res) => {
  const m = get('SELECT * FROM media WHERE id=?', req.params.id);
  if (!m) return res.status(404).json({ error: 'Mídia não encontrada' });
  if (m.inspection_id && !canSee(req, m.inspection_id)) return res.status(403).json({ error: 'Sem acesso' });
  const b = req.body || {};
  const f = (k, v) => (k in b ? v : m[k]);
  run('UPDATE media SET room_id=?, item_id=?, nc_id=?, scope=?, markers=?, transcript=?, caption=?, position=?, taken_at=? WHERE id=?',
    f('room_id', b.room_id), f('item_id', b.item_id), f('nc_id', b.nc_id), f('scope', b.scope), 'markers' in b ? JSON.stringify(b.markers || []) : m.markers,
    f('transcript', b.transcript), f('caption', b.caption), f('position', b.position), f('taken_at', b.taken_at), m.id);
  res.json(M.mediaRow(get('SELECT * FROM media WHERE id=?', m.id)));
});
r.delete('/media/:id', auth(), (req, res) => {
  const m = get('SELECT * FROM media WHERE id=?', req.params.id);
  if (!m) return res.json({ ok: true });
  if (m.inspection_id && !canSee(req, m.inspection_id)) return res.status(403).json({ error: 'Sem acesso' });
  run('DELETE FROM media WHERE id=?', m.id);
  try { fs.unlinkSync(path.join(UPLOAD_DIR, m.file)); } catch {}
  res.json({ ok: true });
});

// ---------------- IA ----------------
r.post('/ai/contract', auth(), upload.single('file'), wrap(async (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Envie o PDF do contrato' });
  const id = req.body.id || uid();
  const file = storeFile(req.file.path, id, req.file.mimetype || 'application/pdf', req.file.originalname);
  const result = await ai.extractContract(path.join(UPLOAD_DIR, file));
  const insId = req.body.inspection_id;
  if (insId && get('SELECT id FROM inspections WHERE id=?', insId)) {
    if (!get('SELECT id FROM media WHERE id=?', id)) run("INSERT INTO media(id,inspection_id,scope,kind,file,mime,size,caption) VALUES(?,?,?,?,?,?,?,?)", id, insId, 'contract', 'pdf', file, 'application/pdf', req.file.size, req.file.originalname);
    const cur = J(get('SELECT contract FROM inspections WHERE id=?', insId).contract);
    run('UPDATE inspections SET contract=? WHERE id=?', JSON.stringify({ ...cur, ...result.data.contract, media_id: id, file_url: `/media/${file}`, filename: req.file.originalname, extracted: result.data, engine: result.engine, extracted_at: new Date().toISOString() }), insId);
    logEvent(insId, 'ia', `Contrato lido pela IA (${result.engine === 'claude' ? 'Claude' : 'extrator local'})`, req.user.id);
  }
  res.json({ ...result, media_id: id, file_url: `/media/${file}`, filename: req.file.originalname });
}));

r.post('/ai/describe', auth(), wrap(async (req, res) => {
  const { media_ids = [], context = 'item' } = req.body || {};
  const files = media_ids.map((id) => get('SELECT file, mime FROM media WHERE id=? AND kind=?', id, 'photo')).filter(Boolean).map((m) => ({ path: path.join(UPLOAD_DIR, m.file), mime: m.mime }));
  if (!files.length) return res.status(400).json({ error: 'Selecione fotos' });
  res.json({ text: await ai.describeImages(files, context) });
}));

// ---------------- Suporte ----------------
r.post('/support', auth(), wrap(async (req, res) => {
  const { subject, message } = req.body || {};
  const admins = all("SELECT email FROM users WHERE role='admin' AND active=1");
  for (const a of admins) await mailer.queue({ to: a.email, subject: `[Suporte] ${subject || 'Mensagem do app'}`, body: `${req.user.name} (${req.user.email}) escreveu:\n\n${message || ''}`, kind: 'suporte' });
  res.json({ ok: true });
}));

// ================= ADMIN =================
r.use('/admin', auth(), admin);

r.get('/admin/dashboard', (req, res) => {
  const month = new Date().toISOString().slice(0, 7);
  const byMonth = all(`SELECT strftime('%Y-%m', created_at) m, COUNT(*) n,
      SUM(CASE WHEN type='entrada' THEN 1 ELSE 0 END) entrada, SUM(CASE WHEN type='saida' THEN 1 ELSE 0 END) saida,
      SUM(CASE WHEN type NOT IN ('entrada','saida') THEN 1 ELSE 0 END) outras
    FROM inspections GROUP BY m ORDER BY m DESC LIMIT 12`);
  const mediaByMonth = Object.fromEntries(all("SELECT strftime('%Y-%m', created_at) m, COUNT(*) n, SUM(size) s FROM media GROUP BY m").map((x) => [x.m, x]));
  const contestByMonth = Object.fromEntries(all("SELECT strftime('%Y-%m', created_at) m, COUNT(*) n FROM contestations GROUP BY m").map((x) => [x.m, x.n]));
  const storage = get('SELECT COALESCE(SUM(size),0) s, COUNT(*) n FROM media');
  res.json({
    kpis: {
      month: get("SELECT COUNT(*) n FROM inspections WHERE strftime('%Y-%m', created_at)=?", month).n,
      media_month: get("SELECT COUNT(*) n FROM media WHERE strftime('%Y-%m', created_at)=?", month).n,
      storage_bytes: storage.s, media_total: storage.n,
      contest_open: get("SELECT COUNT(*) n FROM contestations WHERE status='aberta'").n,
      pending_approval: get("SELECT COUNT(*) n FROM inspections WHERE status IN ('enviada','em_revisao')").n,
      awaiting_sign: get("SELECT COUNT(*) n FROM inspections WHERE status='em_assinatura'").n,
      signed: get("SELECT COUNT(*) n FROM inspections WHERE status='assinada'").n,
      total: get('SELECT COUNT(*) n FROM inspections').n,
    },
    byMonth: byMonth.map((x) => ({ ...x, media: (mediaByMonth[x.m] || {}).n || 0, contest: contestByMonth[x.m] || 0 })),
    byStatus: all('SELECT status, COUNT(*) n FROM inspections GROUP BY status'),
    inspectors: all(`SELECT u.id, u.name, COUNT(i.id) n, SUM(CASE WHEN i.status='assinada' THEN 1 ELSE 0 END) signed,
       (SELECT COUNT(*) FROM contestations c JOIN inspections x ON x.id=c.inspection_id WHERE x.inspector_id=u.id) contests
       FROM users u LEFT JOIN inspections i ON i.inspector_id=u.id WHERE u.role IN ('vistoriador','admin') GROUP BY u.id ORDER BY n DESC`),
    queue: M.listInspections("i.status IN ('enviada','em_revisao','em_assinatura')").slice(0, 8),
    recent: all('SELECT e.*, i.code FROM events e LEFT JOIN inspections i ON i.id=e.inspection_id ORDER BY e.id DESC LIMIT 12'),
  });
});

r.get('/admin/inspections', (req, res) => {
  const w = ['1=1'], p = [];
  if (req.query.status) { w.push('i.status=?'); p.push(req.query.status); }
  if (req.query.type) { w.push('i.type=?'); p.push(req.query.type); }
  if (req.query.inspector) { w.push('i.inspector_id=?'); p.push(req.query.inspector); }
  let list = M.listInspections(w.join(' AND '), p);
  if (req.query.q) { const q = String(req.query.q).toLowerCase(); list = list.filter((x) => JSON.stringify([x.code, x.address, x.property.identification, x.people, x.inspector_name]).toLowerCase().includes(q)); }
  res.json(list);
});

r.post('/admin/inspections', (req, res) => {
  const b = req.body || {};
  const id = uid();
  run('INSERT INTO inspections(id,code,type,status,inspector_id,property,parties,inspected_at) VALUES(?,?,?,?,?,?,?,?)', id, nextCode(), b.type || 'entrada', 'rascunho', b.inspector_id || req.user.id, JSON.stringify(b.property || {}), JSON.stringify(b.parties || {}), new Date().toISOString());
  if (b.template_id) {
    const t = get('SELECT rooms FROM templates WHERE id=?', b.template_id);
    J(t && t.rooms, []).forEach((rm, ri) => { const rid = uid(); run('INSERT INTO rooms(id,inspection_id,name,position) VALUES(?,?,?,?)', rid, id, rm.name, ri); (rm.items || []).forEach((n, ii) => run('INSERT INTO items(id,inspection_id,room_id,name,position) VALUES(?,?,?,?,?)', uid(), id, rid, n, ii)); });
  }
  logEvent(id, 'criada', 'Vistoria criada no painel', req.user.id);
  res.json({ id });
});

// 24-25/10 (Pedro): importar uma vistoria de outro lugar (PDF ou link): o Gemini lê e sai um rascunho (services/importar.js)
r.post('/admin/inspections/import', upload.single('file'), wrap(async (req, res) => {
  const b = req.body || {};
  if (!req.file && !b.url) return res.status(400).json({ error: 'Mande o PDF ou o link do laudo' });
  const r2 = await require('../services/importar').importar({ arquivo: req.file, url: b.url, type: b.type || null,
    inspector_id: b.inspector_id || req.user.id, user_id: req.user.id });
  res.json(r2);
}));

r.get('/admin/inspections/:id', (req, res) => {
  const ins = M.loadInspection(req.params.id);
  if (!ins) return res.status(404).json({ error: 'Não encontrada' });
  ins.completeness = M.completeness(ins);
  ins.recipients = wf.recipients(ins);
  ins.clicksign_enabled = clicksign.enabled();
  ins.public_url = ins.public_token ? `${cfg.baseUrl(req)}/v/${ins.public_token}` : null;
  res.json(ins);
});

r.patch('/admin/inspections/:id', (req, res) => {
  const i = get('SELECT * FROM inspections WHERE id=?', req.params.id);
  if (!i) return res.status(404).json({ error: 'Não encontrada' });
  const b = req.body || {};
  const sets = [], p = [];
  for (const k of ['property', 'parties', 'meters', 'contract', 'extra']) if (k in b) { sets.push(`${k}=?`); p.push(JSON.stringify(b[k] || {})); }
  for (const k of ['type', 'status', 'review_stage', 'general_notes', 'inspector_id', 'inspected_at']) if (k in b) { sets.push(`${k}=?`); p.push(b[k]); }
  if (!sets.length) return res.json({ ok: true });
  if (b.status === 'em_revisao' && i.status === 'enviada') logEvent(i.id, 'revisao', 'Revisão iniciada pelo administrador', req.user.id);
  run(`UPDATE inspections SET ${sets.join(',')}, updated_at=datetime('now') WHERE id=?`, ...p, i.id);
  res.json({ ok: true });
});

r.delete('/admin/inspections/:id', (req, res) => {
  const files = all('SELECT file FROM media WHERE inspection_id=?', req.params.id);
  run('DELETE FROM inspections WHERE id=?', req.params.id);
  files.forEach((f) => { try { fs.unlinkSync(path.join(UPLOAD_DIR, f.file)); } catch {} });
  res.json({ ok: true });
});

// Estrutura (cômodos / itens / avarias) — edição no painel
r.post('/admin/inspections/:id/rooms', (req, res) => {
  const pos = (get('SELECT MAX(position) m FROM rooms WHERE inspection_id=?', req.params.id).m ?? -1) + 1;
  const id = uid();
  run('INSERT INTO rooms(id,inspection_id,name,position) VALUES(?,?,?,?)', id, req.params.id, req.body.name || 'Novo cômodo', pos);
  res.json({ id });
});
r.patch('/admin/rooms/:id', (req, res) => {
  const x = get('SELECT * FROM rooms WHERE id=?', req.params.id); if (!x) return res.status(404).json({ error: 'Não encontrado' });
  const b = req.body;
  run('UPDATE rooms SET name=?, notes=?, position=? WHERE id=?', b.name ?? x.name, b.notes ?? x.notes, b.position ?? x.position, x.id);
  res.json({ ok: true });
});
r.delete('/admin/rooms/:id', (req, res) => { run('DELETE FROM media WHERE room_id=?', req.params.id); run('DELETE FROM rooms WHERE id=?', req.params.id); res.json({ ok: true }); });
r.post('/admin/rooms/reorder', (req, res) => { tx(() => (req.body.ids || []).forEach((id, i) => run('UPDATE rooms SET position=? WHERE id=?', i, id))); res.json({ ok: true }); });
r.post('/admin/rooms/:id/items', (req, res) => {
  const room = get('SELECT * FROM rooms WHERE id=?', req.params.id); if (!room) return res.status(404).json({ error: 'Cômodo não encontrado' });
  const pos = (get('SELECT MAX(position) m FROM items WHERE room_id=?', room.id).m ?? -1) + 1;
  const id = uid();
  run('INSERT INTO items(id,inspection_id,room_id,name,position,condition) VALUES(?,?,?,?,?,?)', id, room.inspection_id, room.id, req.body.name || 'Novo item', pos, req.body.condition || null);
  res.json({ id });
});
r.patch('/admin/items/:id', (req, res) => {
  const x = get('SELECT * FROM items WHERE id=?', req.params.id); if (!x) return res.status(404).json({ error: 'Não encontrado' });
  const b = req.body, v = (k) => (k in b ? b[k] : x[k]);
  run('UPDATE items SET name=?, condition=?, functioning=?, quantity=?, notes=?, has_nc=?, position=?, room_id=? WHERE id=?', v('name'), v('condition'), v('functioning'), v('quantity'), v('notes'), 'has_nc' in b ? (b.has_nc ? 1 : 0) : x.has_nc, v('position'), v('room_id'), x.id);
  res.json({ ok: true });
});
r.delete('/admin/items/:id', (req, res) => { run('DELETE FROM media WHERE item_id=?', req.params.id); run('DELETE FROM items WHERE id=?', req.params.id); res.json({ ok: true }); });
r.post('/admin/ncs', (req, res) => {
  const b = req.body || {};
  const room = get('SELECT * FROM rooms WHERE id=?', b.room_id); if (!room) return res.status(400).json({ error: 'Cômodo inválido' });
  const id = uid();
  run('INSERT INTO ncs(id,inspection_id,room_id,item_id,title,description,position) VALUES(?,?,?,?,?,?,?)', id, room.inspection_id, room.id, b.item_id || null, b.title || 'Avaria', b.description || '', 99);
  if (b.item_id) run('UPDATE items SET has_nc=1 WHERE id=?', b.item_id);
  for (const mid of b.media_ids || []) run("UPDATE media SET nc_id=?, item_id=?, room_id=?, scope='nc' WHERE id=?", id, b.item_id || null, room.id, mid);
  res.json({ id });
});
r.patch('/admin/ncs/:id', (req, res) => {
  const x = get('SELECT * FROM ncs WHERE id=?', req.params.id); if (!x) return res.status(404).json({ error: 'Não encontrada' });
  run('UPDATE ncs SET title=?, description=? WHERE id=?', req.body.title ?? x.title, req.body.description ?? x.description, x.id);
  res.json({ ok: true });
});
r.delete('/admin/ncs/:id', (req, res) => {
  const x = get('SELECT * FROM ncs WHERE id=?', req.params.id);
  if (x) { run("UPDATE media SET nc_id=NULL, scope=CASE WHEN item_id IS NULL THEN 'room' ELSE 'item' END WHERE nc_id=?", x.id); run('DELETE FROM ncs WHERE id=?', x.id);
    if (x.item_id && !get('SELECT id FROM ncs WHERE item_id=?', x.item_id)) run('UPDATE items SET has_nc=0 WHERE id=?', x.item_id); }
  res.json({ ok: true });
});

r.post('/admin/inspections/:id/apply-contract', (req, res) => {
  const i = get('SELECT * FROM inspections WHERE id=?', req.params.id); if (!i) return res.status(404).json({ error: 'Não encontrada' });
  const b = req.body || {};
  const merge = (cur, inc) => { const out = { ...cur }; for (const [k, v] of Object.entries(inc || {})) if (v !== '' && v != null && !(Array.isArray(v) && !v.length)) out[k] = v; return out; };
  run('UPDATE inspections SET property=?, parties=?, contract=?, updated_at=datetime(\'now\') WHERE id=?',
    JSON.stringify(merge(J(i.property), b.property)), JSON.stringify(merge(J(i.parties), b.parties)), JSON.stringify(merge(J(i.contract), b.contract)), i.id);
  logEvent(i.id, 'ia', 'Dados extraídos do contrato aplicados ao laudo', req.user.id);
  res.json({ ok: true });
});

r.post('/admin/inspections/:id/approve', wrap(async (req, res) => {
  res.json(await wf.approve(req.params.id, req.user, { sendEmail: req.body.send_email !== false, baseUrl: cfg.baseUrl(req) }));
}));
r.post('/admin/inspections/:id/signature', wrap(async (req, res) => {
  res.json(await wf.sendToSignature(req.params.id, req.user, { signers: req.body.signers, baseUrl: cfg.baseUrl(req) }));
}));
r.post('/admin/signers/:id/simulate', wrap(async (req, res) => { await wf.markSigned(req.params.id, null, cfg.baseUrl(req)); res.json({ ok: true }); }));
r.post('/admin/inspections/:id/sync-signature', wrap(async (req, res) => res.json(await wf.syncClicksign(req.params.id, cfg.baseUrl(req)))));
r.post('/admin/inspections/:id/resend', wrap(async (req, res) => {
  const ins = M.loadInspection(req.params.id, { withEvents: false });
  if (!ins.public_token) return res.status(400).json({ error: 'Aprove o laudo antes de enviar' });
  const kind = req.body.kind || (ins.type === 'saida' ? 'final' : 'initial');
  const att = kind === 'signed' && ins.signed_pdf ? [{ filename: `Laudo-vistoria-${ins.code}-assinado.pdf`, file: ins.signed_pdf }] : [];
  const n = await mailer.sendTemplate(kind, ins, req.body.recipients || wf.recipients(ins), `${cfg.baseUrl(req)}/v/${ins.public_token}`, att);
  logEvent(ins.id, 'email', `E-mail (${kind}) reenviado para ${n.length} destinatário(s)`, req.user.id);
  res.json({ sent: n.length });
}));
r.post('/admin/inspections/:id/reopen', (req, res) => {
  run("UPDATE inspections SET status='em_revisao', review_stage=4, updated_at=datetime('now') WHERE id=?", req.params.id);
  logEvent(req.params.id, 'reaberta', 'Laudo reaberto para edição', req.user.id);
  res.json({ ok: true });
});
r.post('/admin/inspections/:id/clone-exit', (req, res) => res.json({ id: M.cloneForExit(req.params.id, req.user) }));
r.post('/admin/inspections/:id/preview', (req, res) => {
  wf.ensureTokens(req.params.id);
  const i = get('SELECT public_token FROM inspections WHERE id=?', req.params.id);
  res.json({ url: `/v/${i.public_token}` });
});
r.post('/admin/inspections/:id/pdf', wrap(async (req, res) => {
  wf.ensureTokens(req.params.id);
  const i = get('SELECT code, public_token FROM inspections WHERE id=?', req.params.id);
  const file = `laudo-${i.code}-previa-${Date.now()}.pdf`;
  await require('../services/pdf').renderLaudoPdf(i.public_token, file);
  res.json({ url: `/media/${file}` });
}));

// Contestações
r.get('/admin/contestations', (req, res) => res.json(all(`SELECT c.*, i.code, i.property FROM contestations c JOIN inspections i ON i.id=c.inspection_id ORDER BY c.created_at DESC`).map((c) => ({ ...c, files: J(c.files, []), property: J(c.property) }))));
r.patch('/admin/contestations/:id', wrap(async (req, res) => {
  const c = get('SELECT * FROM contestations WHERE id=?', req.params.id); if (!c) return res.status(404).json({ error: 'Não encontrada' });
  run('UPDATE contestations SET status=?, response=? WHERE id=?', req.body.status || c.status, req.body.response ?? c.response, c.id);
  if (req.body.response && c.email && req.body.notify) await mailer.queue({ to: c.email, subject: 'Resposta à sua contestação de vistoria', body: `Olá, ${c.name || ''}!\n\n${req.body.response}\n\nAtenciosamente,\n${cfg.company().name}`, inspection_id: c.inspection_id, kind: 'contestacao' });
  logEvent(c.inspection_id, 'contestacao', `Contestação marcada como ${req.body.status || c.status}`, req.user.id);
  res.json({ ok: true });
}));

// Cadastros genéricos
function crud(name, table, cols, jsonCols = []) {
  r.get(`/admin/${name}`, (req, res) => res.json(all(`SELECT * FROM ${table} ORDER BY ${cols[0]}`).map((x) => { jsonCols.forEach((c) => (x[c] = J(x[c], c === 'rooms' ? [] : {}))); delete x.password; return x; })));
  r.post(`/admin/${name}`, (req, res) => {
    const b = req.body || {}; const id = b.id || uid();
    const vals = cols.map((c) => (jsonCols.includes(c) ? JSON.stringify(b[c] ?? (c === 'rooms' ? [] : {})) : b[c] === true ? 1 : b[c] === false ? 0 : b[c] ?? null));
    run(`INSERT INTO ${table}(id,${cols.join(',')}) VALUES(?,${cols.map(() => '?').join(',')}) ON CONFLICT(id) DO UPDATE SET ${cols.map((c) => `${c}=excluded.${c}`).join(',')}`, id, ...vals);
    res.json({ id });
  });
  r.delete(`/admin/${name}/:id`, (req, res) => { run(`DELETE FROM ${table} WHERE id=?`, req.params.id); res.json({ ok: true }); });
}
crud('people', 'people', ['name', 'cpf', 'rg', 'email', 'phone', 'kind']);
crud('properties', 'properties', ['identification', 'data'], ['data']);
crud('templates', 'templates', ['name', 'type', 'rooms', 'active'], ['rooms']);
crud('requests', 'requests', ['title', 'address', 'type', 'client', 'scheduled_at', 'inspector_id', 'status', 'notes', 'inspection_id']);

r.get('/admin/users', (req, res) => res.json(all('SELECT id,name,email,role,phone,active,created_at FROM users ORDER BY name')));
r.post('/admin/users', (req, res) => {
  const b = req.body || {};
  if (!b.name || !b.email) return res.status(400).json({ error: 'Nome e e-mail obrigatórios' });
  if (b.id) {
    run('UPDATE users SET name=?, email=?, role=?, phone=?, active=? WHERE id=?', b.name, b.email, b.role || 'vistoriador', b.phone || null, b.active === false ? 0 : 1, b.id);
    if (b.password) run('UPDATE users SET password=? WHERE id=?', hashPassword(b.password), b.id);
    return res.json({ id: b.id });
  }
  if (!b.password) return res.status(400).json({ error: 'Defina uma senha' });
  const id = uid();
  try { run('INSERT INTO users(id,name,email,password,role,phone) VALUES(?,?,?,?,?,?)', id, b.name, b.email, hashPassword(b.password), b.role || 'vistoriador', b.phone || null); } catch (e) { return res.status(400).json({ error: 'E-mail já cadastrado' }); }
  res.json({ id });
});
r.delete('/admin/users/:id', (req, res) => { if (req.params.id === req.user.id) return res.status(400).json({ error: 'Você não pode remover a si mesmo' }); run('UPDATE users SET active=0 WHERE id=?', req.params.id); res.json({ ok: true }); });

r.get('/admin/emails', (req, res) => res.json(all('SELECT e.id,e.inspection_id,e.kind,e.to_addr,e.subject,e.status,e.error,e.created_at,e.sent_at,i.code FROM emails e LEFT JOIN inspections i ON i.id=e.inspection_id ORDER BY e.created_at DESC LIMIT 300')));
r.get('/admin/emails/:id', (req, res) => res.json(get('SELECT * FROM emails WHERE id=?', req.params.id) || {}));
r.post('/admin/emails/:id/retry', wrap(async (req, res) => { await mailer.deliver(req.params.id); res.json(get('SELECT id,status,error FROM emails WHERE id=?', req.params.id)); }));

r.get('/admin/settings', (req, res) => {
  const integ = getSetting('integrations', {});
  const mask = (s) => (s ? '••••••' + String(s).slice(-4) : '');
  res.json({
    company: cfg.company(), texts: cfg.texts(), emails: cfg.emails(), params: cfg.params(),
    integrations: {
      clicksign: { env: (integ.clicksign || {}).env || 'sandbox', token: mask((integ.clicksign || {}).token), env_token: !!process.env.CLICKSIGN_TOKEN, enabled: clicksign.enabled() },
      smtp: { ...(integ.smtp || {}), pass: mask((integ.smtp || {}).pass), env: !!process.env.SMTP_HOST, enabled: !!cfg.integrations().smtp.host },
      ai: { model: cfg.integrations().ai.model, key: mask((integ.ai || {}).key), env_key: !!process.env.ANTHROPIC_API_KEY, enabled: !!cfg.integrations().ai.key },
    },
    webhook_url: `${cfg.baseUrl(req)}/api/webhooks/clicksign`,
    chrome: !!require('../services/pdf').findChrome(),
  });
});
r.put('/admin/settings/:key', (req, res) => {
  const key = req.params.key;
  if (!['company', 'texts', 'emails', 'params', 'integrations'].includes(key)) return res.status(400).json({ error: 'Chave inválida' });
  let v = req.body || {};
  if (key === 'integrations') {
    const cur = getSetting('integrations', {});
    const keep = (sec, f) => { if (v[sec] && typeof v[sec][f] === 'string' && v[sec][f].startsWith('••••')) v[sec][f] = (cur[sec] || {})[f]; };
    keep('clicksign', 'token'); keep('smtp', 'pass'); keep('ai', 'key');
    v = { ...cur, ...v };
  }
  setSetting(key, v);
  res.json({ ok: true });
});
r.post('/admin/test-email', wrap(async (req, res) => {
  const id = await mailer.queue({ to: req.body.to || req.user.email, subject: 'Teste de e-mail', body: 'Se você recebeu esta mensagem, o SMTP está configurado corretamente. ✔', kind: 'teste' });
  res.json(get('SELECT status, error FROM emails WHERE id=?', id));
}));
r.post('/admin/logo', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'Envie uma imagem' });
  const file = storeFile(req.file.path, 'logo-' + Date.now(), req.file.mimetype, req.file.originalname);
  res.json({ url: `/media/${file}` });
});

module.exports = r;
