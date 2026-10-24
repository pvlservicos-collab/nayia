// Fluxo: aprovação → link público + e-mail → assinatura (ClickSign) → documento assinado salvo e enviado
const { get, run, all, uid, token, J, logEvent } = require('../db');
const { loadInspection } = require('../model');
const cfg = require('../config');
const mailer = require('./mailer');
const pdf = require('./pdf');
const clicksign = require('./clicksign');

function recipients(ins) {
  const pa = ins.parties || {};
  const list = [];
  const add = (arr, role) => (arr || []).forEach((p) => { if (p && p.name && p.email && !list.some((x) => x.email.toLowerCase() === p.email.toLowerCase())) list.push({ name: p.name, email: p.email, phone: p.phone, cpf: p.cpf, role }); });
  add(pa.locatarios, 'locatario'); add(pa.locadores, 'locador'); add(pa.fiadores, 'fiador'); add(pa.testemunhas, 'testemunha');
  return list;
}

function ensureTokens(id) {
  const i = get('SELECT public_token, contest_token FROM inspections WHERE id=?', id);
  if (!i.public_token) run('UPDATE inspections SET public_token=? WHERE id=?', token(8), id);
  if (!i.contest_token) run('UPDATE inspections SET contest_token=? WHERE id=?', token(8), id);
}

async function approve(id, user, { sendEmail = true, baseUrl }) {
  ensureTokens(id);
  run("UPDATE inspections SET status='aprovada', review_stage=5, approved_at=datetime('now'), updated_at=datetime('now') WHERE id=?", id);
  logEvent(id, 'aprovada', 'Laudo aprovado e link público gerado', user && user.id);
  const ins = loadInspection(id, { withEvents: false });
  const link = `${baseUrl}/v/${ins.public_token}`;
  let sent = [];
  if (sendEmail) {
    const kind = ins.type === 'saida' ? 'final' : 'initial';
    sent = await mailer.sendTemplate(kind, ins, recipients(ins), link);
    logEvent(id, 'email', `E-mail de vistoria ${kind === 'final' ? 'final' : 'inicial'} enviado para ${sent.length} destinatário(s)`, user && user.id);
  }
  return { link, emails: sent.length };
}

async function sendToSignature(id, user, { signers, baseUrl }) {
  ensureTokens(id);
  let ins = loadInspection(id, { withEvents: false });
  const list = (signers && signers.length ? signers : recipients(ins)).filter((s) => s.name && s.email);
  if (!list.length) throw Object.assign(new Error('Informe ao menos um signatário com nome e e-mail'), { status: 400 });
  run('DELETE FROM signers WHERE inspection_id=?', id);
  for (const s of list) { s.id = uid(); run('INSERT INTO signers(id,inspection_id,name,email,phone,cpf,role) VALUES(?,?,?,?,?,?,?)', s.id, id, s.name, s.email, s.phone || null, s.cpf || null, s.role || null); }

  const file = `laudo-${ins.code}-${Date.now()}.pdf`;
  await pdf.renderLaudoPdf(ins.public_token, file);
  run('UPDATE inspections SET unsigned_pdf=? WHERE id=?', file, id);

  let cs = { mode: 'simulacao' };
  if (clicksign.enabled()) {
    const name = `Laudo de vistoria #${ins.code} - ${(ins.property && ins.property.identification) || ''}`.trim();
    const r = await clicksign.createEnvelope({ name, pdfFile: file, signers: list, message: `Laudo de vistoria ${ins.typeLabel} — ${cfg.company().name}. Link do laudo: ${baseUrl}/v/${ins.public_token}` });
    for (const s of r.signers) run('UPDATE signers SET external_id=? WHERE id=?', s.external_id, s.local_id);
    cs = { mode: 'clicksign', env: cfg.integrations().clicksign.env, envelope_id: r.envelopeId, document_id: r.documentId };
  }
  run("UPDATE inspections SET status='em_assinatura', review_stage=6, clicksign=?, updated_at=datetime('now') WHERE id=?", JSON.stringify(cs), id);
  logEvent(id, 'assinatura', `Documento enviado para assinatura (${cs.mode === 'clicksign' ? 'ClickSign' : 'modo simulação'}) — ${list.length} signatário(s): ${list.map((s) => s.email).join(', ')}`, user && user.id);
  return { mode: cs.mode, signers: list.length, pdf: file };
}

async function markSigned(signerId, signedAt, baseUrl) {
  const s = get('SELECT * FROM signers WHERE id=?', signerId);
  if (!s || s.status === 'assinado') return;
  run("UPDATE signers SET status='assinado', signed_at=? WHERE id=?", signedAt || new Date().toISOString(), signerId);
  logEvent(s.inspection_id, 'assinado', `${s.name} (${s.email}) assinou o laudo`);
  await maybeFinalize(s.inspection_id, baseUrl);
}

async function maybeFinalize(id, baseUrl) {
  const pending = all("SELECT id FROM signers WHERE inspection_id=? AND status!='assinado'", id);
  const total = all('SELECT id FROM signers WHERE inspection_id=?', id);
  if (!total.length || pending.length) return false;
  const ins0 = get('SELECT * FROM inspections WHERE id=?', id);
  if (ins0.status === 'assinada') return true;
  const cs = J(ins0.clicksign);
  const file = `laudo-${ins0.code}-assinado-${Date.now()}.pdf`;
  run("UPDATE inspections SET status='assinada', signed_at=datetime('now'), updated_at=datetime('now') WHERE id=?", id);
  try {
    if (cs.mode === 'clicksign') await clicksign.downloadSigned(cs.envelope_id, cs.document_id, file);
    else await pdf.renderLaudoPdf(ins0.public_token, file);
    run('UPDATE inspections SET signed_pdf=? WHERE id=?', file, id);
  } catch (e) { logEvent(id, 'erro', `Falha ao salvar documento assinado: ${e.message}`); }
  logEvent(id, 'concluida', 'Todas as partes assinaram. Documento assinado salvo.');
  const ins = loadInspection(id, { withEvents: false });
  const signers = all('SELECT name, email FROM signers WHERE inspection_id=?', id);
  const att = ins.signed_pdf ? [{ filename: `Laudo-vistoria-${ins.code}-assinado.pdf`, file: ins.signed_pdf }] : [];
  await mailer.sendTemplate('signed', ins, signers, `${baseUrl || cfg.baseUrl()}/v/${ins.public_token}`, att);
  logEvent(id, 'email', `Documento assinado enviado por e-mail para ${signers.length} pessoa(s)`);
  return true;
}

// Sincroniza com a ClickSign (usado pelo webhook e pelo botão "Atualizar status")
async function syncClicksign(id, baseUrl) {
  const ins = get('SELECT clicksign FROM inspections WHERE id=?', id);
  const cs = J(ins && ins.clicksign);
  if (cs.mode !== 'clicksign') return { mode: cs.mode || 'simulacao' };
  const st = await clicksign.envelopeStatus(cs.envelope_id);
  for (const s of st.signers) {
    const local = get('SELECT id, status FROM signers WHERE inspection_id=? AND (external_id=? OR lower(email)=lower(?))', id, s.id, s.email);
    if (local && s.signed && local.status !== 'assinado') {
      run("UPDATE signers SET status='assinado', signed_at=? WHERE id=?", s.signed_at || new Date().toISOString(), local.id);
      logEvent(id, 'assinado', `${s.email} assinou o laudo (ClickSign)`);
    }
  }
  await maybeFinalize(id, baseUrl);
  return st;
}

module.exports = { approve, sendToSignature, markSigned, maybeFinalize, syncClicksign, recipients, ensureTokens };
