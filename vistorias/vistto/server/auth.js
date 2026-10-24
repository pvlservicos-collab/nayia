// Autenticação por token assinado (HMAC) — funciona offline no app, sem sessão no servidor
const crypto = require('crypto');
const { get } = require('./db');
const { secret } = require('./config');

const TTL = 1000 * 60 * 60 * 24 * 60; // 60 dias (o vistoriador pode ficar dias offline)

function sign(user) {
  const payload = Buffer.from(JSON.stringify({ id: user.id, role: user.role, exp: Date.now() + TTL })).toString('base64url');
  const sig = crypto.createHmac('sha256', secret()).update(payload).digest('base64url');
  return `${payload}.${sig}`;
}

function verify(tok) {
  if (!tok || !tok.includes('.')) return null;
  const [payload, sig] = tok.split('.');
  const exp = crypto.createHmac('sha256', secret()).update(payload).digest('base64url');
  if (sig.length !== exp.length || !crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(exp))) return null;
  try {
    const data = JSON.parse(Buffer.from(payload, 'base64url').toString());
    if (data.exp < Date.now()) return null;
    return data;
  } catch { return null; }
}

function readToken(req) {
  const h = req.get('authorization') || '';
  if (h.startsWith('Bearer ')) return h.slice(7);
  const c = (req.get('cookie') || '').split(';').map((s) => s.trim()).find((s) => s.startsWith('vt='));
  if (c) return decodeURIComponent(c.slice(3));
  return req.query.t || null;
}

function auth(required = true) {
  return (req, res, next) => {
    const data = verify(readToken(req));
    if (data) {
      const u = get('SELECT id,name,email,role,phone FROM users WHERE id=? AND active=1', data.id);
      if (u) req.user = u;
    }
    if (required && !req.user) return res.status(401).json({ error: 'Não autenticado' });
    next();
  };
}

function admin(req, res, next) {
  if (!req.user || req.user.role !== 'admin') return res.status(403).json({ error: 'Acesso restrito ao administrador' });
  next();
}

module.exports = { sign, verify, auth, admin };
