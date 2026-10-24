// Servidor principal
const path = require('path');
// carrega o arquivo .env (Node 22+), quando existir — no Docker as variáveis já vêm do compose
try { process.loadEnvFile(path.join(__dirname, '..', '.env')); } catch {}
const fs = require('fs');
const express = require('express');
const { UPLOAD_DIR, get } = require('./db');
const cfg = require('./config');

// primeira execução: cria dados iniciais (admin, modelos, configurações)
if (!get('SELECT id FROM users LIMIT 1')) require('./seed').seed({ demo: process.env.SEED_DEMO !== 'false' });

const app = express();
app.set('trust proxy', true);
app.disable('x-powered-by');

app.use(require('./routes/public')); // laudo público, contestação e webhook (corpo bruto, antes do json)
app.use(express.json({ limit: '25mb' }));
app.use(express.urlencoded({ extended: true }));

const PUB = path.join(__dirname, '..', 'public');
const noCache = { setHeaders: (res, p) => { if (/\.(html|js|css|webmanifest)$/.test(p)) res.setHeader('Cache-Control', 'no-cache'); } };
app.use('/shared', express.static(path.join(PUB, 'shared'), { maxAge: '7d' }));
app.use('/laudo', express.static(path.join(PUB, 'laudo'), noCache));
app.use('/app', express.static(path.join(PUB, 'app'), noCache));
app.use('/admin', express.static(path.join(PUB, 'admin'), noCache));
app.use('/media', express.static(UPLOAD_DIR, { maxAge: '30d', index: false, dotfiles: 'deny' }));

app.use('/api', require('./routes/api'));

app.get('/', (req, res) => {
  const mobile = /Android|iPhone|iPad|iPod|Mobile/i.test(req.get('user-agent') || '');
  res.redirect(mobile ? '/app/' : '/admin/');
});
app.get('/health', (req, res) => res.json({ ok: true, app: cfg.APP_NAME }));

app.use('/api', (req, res) => res.status(404).json({ error: 'Rota não encontrada' }));
app.use((err, req, res, next) => { console.error(err); res.status(500).json({ error: err.message || 'Erro interno' }); });

const PORT = Number(process.env.PORT || 3000);
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n  ${cfg.APP_NAME} rodando em http://localhost:${PORT}`);
  console.log(`  Painel:  http://localhost:${PORT}/admin/`);
  console.log(`  App:     http://localhost:${PORT}/app/\n`);
});

process.on('unhandledRejection', (e) => console.error('unhandledRejection', e));
