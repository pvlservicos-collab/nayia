// Banco de dados SQLite (módulo nativo node:sqlite — sem dependências nativas para compilar)
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const { DatabaseSync } = require('node:sqlite');

const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, '..', 'data');
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(__dirname, '..', 'uploads');
fs.mkdirSync(DATA_DIR, { recursive: true });
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

const db = new DatabaseSync(path.join(DATA_DIR, 'vistoria.db'));
db.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = 5000;');

db.exec(`
CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'vistoriador',
  phone TEXT,
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS vocab (
  id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  name TEXT NOT NULL,
  uses INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(kind, name)
);
CREATE TABLE IF NOT EXISTS people (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  cpf TEXT, rg TEXT, email TEXT, phone TEXT,
  kind TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS properties (
  id TEXT PRIMARY KEY,
  identification TEXT,
  data TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS templates (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT,
  rooms TEXT NOT NULL DEFAULT '[]',
  active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS requests (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  address TEXT,
  type TEXT,
  client TEXT,
  scheduled_at TEXT,
  inspector_id TEXT,
  status TEXT NOT NULL DEFAULT 'solicitada',
  notes TEXT,
  inspection_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS inspections (
  id TEXT PRIMARY KEY,
  code INTEGER NOT NULL,
  type TEXT NOT NULL DEFAULT 'entrada',
  status TEXT NOT NULL DEFAULT 'rascunho',
  review_stage INTEGER NOT NULL DEFAULT 1,
  inspector_id TEXT,
  property TEXT NOT NULL DEFAULT '{}',
  parties TEXT NOT NULL DEFAULT '{}',
  meters TEXT NOT NULL DEFAULT '{}',
  contract TEXT NOT NULL DEFAULT '{}',
  extra TEXT NOT NULL DEFAULT '{}',
  general_notes TEXT,
  public_token TEXT UNIQUE,
  contest_token TEXT UNIQUE,
  clicksign TEXT NOT NULL DEFAULT '{}',
  unsigned_pdf TEXT,
  signed_pdf TEXT,
  source_inspection_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  inspected_at TEXT,
  submitted_at TEXT,
  approved_at TEXT,
  signed_at TEXT
);
CREATE TABLE IF NOT EXISTS rooms (
  id TEXT PRIMARY KEY,
  inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  notes TEXT,
  done INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS items (
  id TEXT PRIMARY KEY,
  inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  position INTEGER NOT NULL DEFAULT 0,
  condition TEXT,
  functioning TEXT,
  quantity INTEGER,
  notes TEXT,
  has_nc INTEGER NOT NULL DEFAULT 0,
  source_item_id TEXT
);
CREATE TABLE IF NOT EXISTS ncs (
  id TEXT PRIMARY KEY,
  inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
  item_id TEXT REFERENCES items(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  position INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS media (
  id TEXT PRIMARY KEY,
  inspection_id TEXT REFERENCES inspections(id) ON DELETE CASCADE,
  room_id TEXT,
  item_id TEXT,
  nc_id TEXT,
  scope TEXT NOT NULL DEFAULT 'room',
  kind TEXT NOT NULL DEFAULT 'photo',
  file TEXT NOT NULL,
  mime TEXT,
  size INTEGER,
  taken_at TEXT,
  transcript TEXT,
  markers TEXT NOT NULL DEFAULT '[]',
  caption TEXT,
  position INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS signers (
  id TEXT PRIMARY KEY,
  inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  cpf TEXT,
  role TEXT,
  status TEXT NOT NULL DEFAULT 'pendente',
  external_id TEXT,
  signed_at TEXT
);
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  inspection_id TEXT,
  kind TEXT NOT NULL,
  message TEXT,
  user_id TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS emails (
  id TEXT PRIMARY KEY,
  inspection_id TEXT,
  kind TEXT,
  to_addr TEXT NOT NULL,
  subject TEXT NOT NULL,
  html TEXT NOT NULL,
  attachments TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'pendente',
  error TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  sent_at TEXT
);
CREATE TABLE IF NOT EXISTS contestations (
  id TEXT PRIMARY KEY,
  inspection_id TEXT NOT NULL REFERENCES inspections(id) ON DELETE CASCADE,
  name TEXT, email TEXT, phone TEXT,
  room TEXT,
  message TEXT NOT NULL,
  files TEXT NOT NULL DEFAULT '[]',
  status TEXT NOT NULL DEFAULT 'aberta',
  response TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_rooms_insp ON rooms(inspection_id);
CREATE INDEX IF NOT EXISTS idx_items_room ON items(room_id);
CREATE INDEX IF NOT EXISTS idx_media_insp ON media(inspection_id);
CREATE INDEX IF NOT EXISTS idx_ncs_insp ON ncs(inspection_id);
`);

const uid = () => crypto.randomUUID();
const token = (n = 9) => crypto.randomBytes(n).toString('base64url').replace(/[-_]/g, '').slice(0, n).toLowerCase() + crypto.randomBytes(3).toString('hex').slice(0, 3);

function all(sql, ...p) { return db.prepare(sql).all(...p); }
function get(sql, ...p) { return db.prepare(sql).get(...p); }
function run(sql, ...p) { return db.prepare(sql).run(...p); }
function tx(fn) {
  db.exec('BEGIN');
  try { const r = fn(); db.exec('COMMIT'); return r; } catch (e) { db.exec('ROLLBACK'); throw e; }
}
const J = (s, d = {}) => { if (s == null || s === '') return d; try { return JSON.parse(s); } catch { return d; } };

// Senhas com scrypt
function hashPassword(pw) {
  const salt = crypto.randomBytes(16).toString('hex');
  const h = crypto.scryptSync(pw, salt, 64).toString('hex');
  return `${salt}:${h}`;
}
function checkPassword(pw, stored) {
  if (!stored || !stored.includes(':')) return false;
  const [salt, h] = stored.split(':');
  const x = crypto.scryptSync(pw, salt, 64).toString('hex');
  return crypto.timingSafeEqual(Buffer.from(x, 'hex'), Buffer.from(h, 'hex'));
}

// Settings
function getSetting(key, def = {}) { const r = get('SELECT value FROM settings WHERE key=?', key); return r ? J(r.value, def) : def; }
function setSetting(key, value) { run('INSERT INTO settings(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value', key, JSON.stringify(value)); }

function nextCode() { const r = get('SELECT MAX(code) m FROM inspections'); return (r && r.m ? r.m : 0) + 1; }

function logEvent(inspection_id, kind, message, user_id = null) {
  run('INSERT INTO events(inspection_id,kind,message,user_id) VALUES(?,?,?,?)', inspection_id, kind, message, user_id);
}

module.exports = { db, all, get, run, tx, J, uid, token, hashPassword, checkPassword, getSetting, setSetting, nextCode, logEvent, DATA_DIR, UPLOAD_DIR };
