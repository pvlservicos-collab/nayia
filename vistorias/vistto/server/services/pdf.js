// Geração do PDF do laudo a partir da própria página pública (mesmo visual do link)
const fs = require('fs');
const path = require('path');
const { UPLOAD_DIR } = require('../db');

function findChrome() {
  const c = [process.env.CHROME_PATH, '/usr/bin/chromium', '/usr/bin/chromium-browser', '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable'];
  for (const p of c) if (p && fs.existsSync(p)) return p;
  for (const base of [process.env.PLAYWRIGHT_BROWSERS_PATH, '/opt/pw-browsers', path.join(require('os').homedir(), '.cache/ms-playwright')]) {
    if (!base || !fs.existsSync(base)) continue;
    for (const d of fs.readdirSync(base).filter((x) => x.startsWith('chromium')).sort().reverse()) {
      for (const sub of ['chrome-linux64/chrome', 'chrome-linux/chrome']) { const f = path.join(base, d, sub); if (fs.existsSync(f)) return f; }
    }
  }
  return null;
}

let browserP = null;
async function browser() {
  const puppeteer = require('puppeteer-core');
  const exe = findChrome();
  if (!exe) throw new Error('Chromium não encontrado. Instale o chromium na VPS ou defina CHROME_PATH (o Docker já inclui).');
  if (!browserP) browserP = puppeteer.launch({ executablePath: exe, headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage', '--font-render-hinting=none'] });
  try { const b = await browserP; if (!b.connected) throw new Error('closed'); return b; } catch { browserP = null; return browser(); }
}

function renderToken(publicToken) {
  return require('crypto').createHmac('sha256', require('../config').secret()).update('render:' + publicToken).digest('hex').slice(0, 24);
}

async function renderLaudoPdf(publicToken, filename) {
  const port = process.env.PORT || 3000;
  const b = await browser();
  const page = await b.newPage();
  try {
    await page.goto(`http://127.0.0.1:${port}/v/${publicToken}?print=1&rt=${renderToken(publicToken)}`, { waitUntil: 'networkidle0', timeout: 120000 });
    await page.emulateMediaType('print');
    // 24/10: o mapa do Google (iframe) termina de desenhar depois do networkidle; sem esta espera saía um quadro cinza
    await new Promise((r) => setTimeout(r, 3000));
    const out = path.join(UPLOAD_DIR, filename);
    await page.pdf({ path: out, format: 'A4', printBackground: true, margin: { top: '12mm', bottom: '14mm', left: '10mm', right: '10mm' },
      displayHeaderFooter: true, headerTemplate: '<span></span>',
      footerTemplate: '<div style="font-size:7px;width:100%;text-align:center;color:#94A3B8;font-family:Arial">Página <span class="pageNumber"></span> de <span class="totalPages"></span></div>' });
    return filename;
  } finally { await page.close(); }
}

module.exports = { renderLaudoPdf, findChrome, renderToken };
