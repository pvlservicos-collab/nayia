// Integração ClickSign (API v3 — envelopes). Sem token configurado, roda em MODO SIMULAÇÃO:
// o fluxo completo funciona e cada assinatura pode ser confirmada manualmente no painel.
const fs = require('fs');
const path = require('path');
const cfg = require('../config');
const { UPLOAD_DIR } = require('../db');

function base() { return cfg.integrations().clicksign.env === 'production' ? 'https://app.clicksign.com' : 'https://sandbox.clicksign.com'; }
function enabled() { return !!cfg.integrations().clicksign.token; }

async function api(method, url, body) {
  const r = await fetch(`${base()}/api/v3${url}`, {
    method,
    headers: { Authorization: cfg.integrations().clicksign.token, 'Content-Type': 'application/vnd.api+json', Accept: 'application/vnd.api+json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const txt = await r.text();
  let j = {}; try { j = txt ? JSON.parse(txt) : {}; } catch { j = { raw: txt }; }
  if (!r.ok) throw new Error(`ClickSign ${method} ${url} → ${r.status}: ${(j.errors && JSON.stringify(j.errors)) || txt.slice(0, 300)}`);
  return j;
}

// Cria envelope, documento, signatários e requisitos; ativa e notifica.
async function createEnvelope({ name, pdfFile, signers, message }) {
  const env = await api('POST', '/envelopes', { data: { type: 'envelopes', attributes: { name, locale: 'pt-BR', auto_close: true, remind_interval: 3, block_after_refusal: true } } });
  const envelopeId = env.data.id;
  const b64 = fs.readFileSync(path.join(UPLOAD_DIR, pdfFile)).toString('base64');
  const doc = await api('POST', `/envelopes/${envelopeId}/documents`, { data: { type: 'documents', attributes: { filename: `${name}.pdf`.replace(/[^\w.\- ]/g, ''), content_base64: `data:application/pdf;base64,${b64}` } } });
  const documentId = doc.data.id;
  const out = [];
  for (const s of signers) {
    const attrs = { name: s.name, email: s.email, has_documentation: false, refusable: true, communicate_events: { signature_request: 'email', signature_reminder: 'email', document_signed: 'email' } };
    if (s.phone) attrs.phone_number = s.phone.replace(/\D/g, '').replace(/^55/, '');
    const sg = await api('POST', `/envelopes/${envelopeId}/signers`, { data: { type: 'signers', attributes: attrs } });
    const signerId = sg.data.id;
    await api('POST', `/envelopes/${envelopeId}/requirements`, { data: { type: 'requirements', attributes: { action: 'agree', role: s.role === 'testemunha' ? 'witness' : 'sign' },
      relationships: { document: { data: { type: 'documents', id: documentId } }, signer: { data: { type: 'signers', id: signerId } } } } });
    await api('POST', `/envelopes/${envelopeId}/requirements`, { data: { type: 'requirements', attributes: { action: 'provide_evidence', auth: 'email' },
      relationships: { document: { data: { type: 'documents', id: documentId } }, signer: { data: { type: 'signers', id: signerId } } } } });
    out.push({ local_id: s.id, external_id: signerId });
  }
  await api('PATCH', `/envelopes/${envelopeId}`, { data: { id: envelopeId, type: 'envelopes', attributes: { status: 'running' } } });
  await api('POST', `/envelopes/${envelopeId}/notifications`, { data: { type: 'notifications', attributes: { message: message || 'Por favor, assine o laudo de vistoria.' } } });
  return { envelopeId, documentId, signers: out };
}

async function envelopeStatus(envelopeId) {
  const env = await api('GET', `/envelopes/${envelopeId}`);
  const signers = await api('GET', `/envelopes/${envelopeId}/signers`);
  return { status: env.data.attributes.status, signers: (signers.data || []).map((s) => ({ id: s.id, email: s.attributes.email, signed: !!(s.attributes.signed_at || s.attributes.status === 'signed'), signed_at: s.attributes.signed_at })) };
}

async function downloadSigned(envelopeId, documentId, outFile) {
  const d = await api('GET', `/envelopes/${envelopeId}/documents/${documentId}`);
  const files = (d.data.attributes.links && d.data.attributes.links.files) || {};
  const url = files.signed || files.original;
  if (!url) throw new Error('Documento assinado ainda não disponível');
  const r = await fetch(url);
  fs.writeFileSync(path.join(UPLOAD_DIR, outFile), Buffer.from(await r.arrayBuffer()));
  return outFile;
}

module.exports = { enabled, createEnvelope, envelopeStatus, downloadSigned };
