// Leitura consolidada de configurações (banco + variáveis de ambiente)
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { getSetting, DATA_DIR } = require('./db');
const D = require('./defaults');

function secret() {
  if (process.env.APP_SECRET) return process.env.APP_SECRET;
  const f = path.join(DATA_DIR, '.secret');
  if (!fs.existsSync(f)) fs.writeFileSync(f, crypto.randomBytes(32).toString('hex'));
  return fs.readFileSync(f, 'utf8').trim();
}

function company() { return { ...D.COMPANY, ...getSetting('company', {}) }; }
function texts() { return { ...D.TEXTS, ...getSetting('texts', {}) }; }
function emails() {
  const s = getSetting('emails', {});
  return { initial: { ...D.EMAILS.initial, ...(s.initial || {}) }, final: { ...D.EMAILS.final, ...(s.final || {}) }, signed: { ...D.EMAILS.signed, ...(s.signed || {}) } };
}
function params() { return { ...D.PARAMS, ...getSetting('params', {}) }; }

function integrations() {
  const s = getSetting('integrations', {});
  const cs = s.clicksign || {};
  const smtp = s.smtp || {};
  const ai = s.ai || {};
  return {
    clicksign: {
      token: process.env.CLICKSIGN_TOKEN || cs.token || '',
      env: process.env.CLICKSIGN_ENV || cs.env || 'sandbox',
      webhook_secret: process.env.CLICKSIGN_WEBHOOK_SECRET || cs.webhook_secret || '',
    },
    smtp: {
      host: process.env.SMTP_HOST || smtp.host || '',
      port: Number(process.env.SMTP_PORT || smtp.port || 587),
      secure: String(process.env.SMTP_SECURE || smtp.secure || 'false') === 'true',
      user: process.env.SMTP_USER || smtp.user || '',
      pass: process.env.SMTP_PASS || smtp.pass || '',
      from: process.env.SMTP_FROM || smtp.from || '',
    },
    ai: {
      key: process.env.ANTHROPIC_API_KEY || ai.key || '',
      model: process.env.AI_MODEL || ai.model || 'claude-sonnet-5-5',
    },
  };
}

function baseUrl(req) {
  if (process.env.PUBLIC_URL) return process.env.PUBLIC_URL.replace(/\/$/, '');
  if (req) return `${req.protocol}://${req.get('host')}`;
  return `http://localhost:${process.env.PORT || 3000}`;
}

module.exports = { secret, company, texts, emails, params, integrations, baseUrl, ...D };
