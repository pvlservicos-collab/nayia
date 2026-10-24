// Comunicação com o servidor + motor de sincronização offline-first
import { kv, inspections, media, DEMO } from './store.js';

let token = null;
export async function getToken() { if (token) return token; token = await kv.get('token'); return token; }
export async function setSession(t, user) { token = t; await kv.set('token', t); await kv.set('user', user); }
export async function clearSession() { token = null; await kv.del('token'); await kv.del('user'); }

export async function api(path, opts = {}) {
  if (DEMO) throw new Error('Modo demonstração');
  const t = await getToken();
  const headers = { ...(opts.headers || {}) };
  if (t) headers.Authorization = `Bearer ${t}`;
  let body = opts.body;
  if (body && !(body instanceof FormData) && typeof body !== 'string') { headers['Content-Type'] = 'application/json'; body = JSON.stringify(body); }
  const r = await fetch(`/api${path}`, { method: opts.method || (body ? 'POST' : 'GET'), headers, body });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401) { const e = new Error(j.error || 'Sessão expirada'); e.auth = true; throw e; }
  if (!r.ok) throw new Error(j.error || `Erro ${r.status}`);
  return j;
}

export const online = () => navigator.onLine !== false;

export async function bootstrap(force = false) {
  const cached = await kv.get('bootstrap');
  if (!force && cached && !online()) return cached;
  try { const b = await api('/app/bootstrap'); await kv.set('bootstrap', b); return b; } catch (e) { if (e.auth) throw e; return cached; }
}

// Estrutura enviada ao servidor (sem blobs)
function structure(ins, mediaIds) {
  return {
    id: ins.id, type: ins.type, inspected_at: ins.created_at, property: ins.property || {}, parties: ins.parties || {}, meters: stripMeters(ins.meters),
    general_notes: ins.general_notes || '', source_inspection_id: ins.source_inspection_id || null, media_ids: mediaIds,
    rooms: (ins.rooms || []).map((r) => ({ id: r.id, name: r.name, notes: r.notes || '', done: !!r.done,
      // 24/10: a inconformidade do cômodo (toggle "Existe alguma inconformidade?") só vai quando ligada
      ncs: (r.has_nc ? r.ncs || [] : []).map((n) => ({ id: n.id, title: n.title || 'Avaria', description: n.description || '' })),
      items: (r.items || []).map((it) => ({ id: it.id, name: it.name, condition: it.condition || null, functioning: it.functioning || null, quantity: it.quantity || null, notes: it.notes || '', has_nc: !!it.has_nc,
        ncs: (it.ncs || []).map((n) => ({ id: n.id, title: n.title || 'Avaria', description: n.description || '' })) })) })),
  };
}
function stripMeters(m = {}) { const o = {}; for (const [k, v] of Object.entries(m || {})) o[k] = { number: v.number || '', reading: v.reading || '' }; return o; }

// Onde cada mídia está pendurada (cômodo / item / inconformidade / medidor)
export function mediaPlacement(ins) {
  const map = new Map();
  const both = (o) => [...(o.media || []), ...(o.videos || []), ...(o.audios || [])];
  (ins.rooms || []).forEach((r) => {
    both(r).forEach((id, i) => map.set(id, { room_id: r.id, scope: 'room', position: i }));
    (r.has_nc ? r.ncs || [] : []).forEach((n) => both(n).forEach((id, i) => map.set(id, { room_id: r.id, nc_id: n.id, scope: 'nc', position: i })));
    (r.items || []).forEach((it) => {
      both(it).forEach((id, i) => map.set(id, { room_id: r.id, item_id: it.id, scope: 'item', position: i }));
      (it.has_nc ? it.ncs || [] : []).forEach((n) => both(n).forEach((id, i) => map.set(id, { room_id: r.id, item_id: it.id, nc_id: n.id, scope: 'nc', position: i })));
    });
  });
  for (const [k, v] of Object.entries(ins.meters || {})) (v.media || []).forEach((id, i) => map.set(id, { scope: 'meter', caption: { energia: 'Energia elétrica', agua: 'Água', gas: 'Gás' }[k] || k, position: i }));
  return map;
}

let running = null;
export async function syncInspection(id, onProgress = () => {}) {
  if (running) await running.catch(() => {});
  running = (async () => {
    let ins = await inspections.get(id);
    if (!ins) return;
    const place = mediaPlacement(ins);
    const ids = [...place.keys()];
    onProgress({ step: 'dados', done: 0, total: ids.length });
    const res = await api('/app/sync', { body: structure(ins, ids) });
    ins = await inspections.get(id);
    ins.server = { id: res.id, code: res.code, status: res.status, synced_at: new Date().toISOString() };
    ins.code = res.code;
    await inspections.put(ins);
    const known = new Set(res.known_media || []);
    let done = 0;
    for (const mid of ids) {
      const m = await media.get(mid);
      if (!m) { done++; continue; }
      const p = place.get(mid);
      const needFile = !known.has(mid);
      if (needFile || m.dirty || !m.uploaded) {
        const fd = new FormData();
        fd.append('id', m.id); fd.append('inspection_id', id); fd.append('kind', m.kind); fd.append('scope', p.scope);
        if (p.room_id) fd.append('room_id', p.room_id); if (p.item_id) fd.append('item_id', p.item_id); if (p.nc_id) fd.append('nc_id', p.nc_id);
        fd.append('taken_at', m.taken_at || new Date().toISOString()); fd.append('markers', JSON.stringify(m.markers || [])); fd.append('position', String(p.position || 0));
        if (m.transcript) fd.append('transcript', m.transcript);
        if (p.caption) fd.append('caption', p.caption);
        if (needFile && m.blob) fd.append('file', m.blob, `${m.id}.${ext(m.mime)}`);
        await api('/media', { body: fd });
        await media.patch(mid, { uploaded: true, dirty: false });
      }
      done++;
      onProgress({ step: 'midias', done, total: ids.length });
    }
    // contrato anexado no aparelho
    ins = await inspections.get(id);
    if (ins.contract && ins.contract.media_id && !ins.contract.uploaded) {
      const m = await media.get(ins.contract.media_id);
      if (m && m.blob) {
        const fd = new FormData(); fd.append('id', m.id); fd.append('inspection_id', id); fd.append('file', m.blob, ins.contract.filename || 'contrato.pdf');
        await api('/ai/contract', { body: fd });
        ins = await inspections.get(id); ins.contract.uploaded = true; await inspections.put(ins);
      }
    }
    if (ins.local_status === 'queued') {
      onProgress({ step: 'envio', done: ids.length, total: ids.length });
      await api(`/app/inspections/${id}/submit`, { body: {} });
      ins = await inspections.get(id);
      ins.local_status = 'sent'; ins.server.status = 'enviada'; ins.sent_at = new Date().toISOString();
      await inspections.put(ins);
    }
    onProgress({ step: 'ok', done: ids.length, total: ids.length });
    return ins;
  })();
  try { return await running; } finally { running = null; }
}

function ext(mime = '') { if (mime.includes('jpeg')) return 'jpg'; if (mime.includes('png')) return 'png'; if (mime.includes('mp4')) return mime.startsWith('audio') ? 'm4a' : 'mp4'; if (mime.includes('webm')) return 'webm'; if (mime.includes('quicktime')) return 'mov'; if (mime.includes('pdf')) return 'pdf'; return 'bin'; }

// Sincroniza em segundo plano tudo o que está na fila
let bgTimer = null, bgOnline = null;
export async function syncQueued(onEach) {
  if (DEMO || !online() || !(await getToken())) return;
  const list = (await inspections.all()).filter((i) => i.local_status === 'queued');
  for (const i of list) { try { await syncInspection(i.id); onEach && onEach(i.id, null); } catch (e) { onEach && onEach(i.id, e); } }
}
export function startBackgroundSync(cb) {
  if (DEMO) return;
  if (bgOnline) window.removeEventListener('online', bgOnline);
  bgOnline = () => syncQueued(cb);
  window.addEventListener('online', bgOnline);
  clearInterval(bgTimer);
  bgTimer = setInterval(() => syncQueued(cb), 60000);
  setTimeout(() => syncQueued(cb), 2500);
}
