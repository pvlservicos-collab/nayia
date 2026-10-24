// Armazenamento local (IndexedDB): vistorias, fotos, áudios e vídeos ficam no aparelho até sincronizar.
// Em modo demonstração (?demo=1, usado na aba "Telas" do painel) tudo fica só em memória.
export const DEMO = new URLSearchParams(location.search).has('demo');

const DB_NAME = 'vistto';
let dbp = null;
function idb() {
  if (dbp) return dbp;
  dbp = new Promise((res, rej) => {
    const r = indexedDB.open(DB_NAME, 1);
    r.onupgradeneeded = () => {
      const d = r.result;
      if (!d.objectStoreNames.contains('inspections')) d.createObjectStore('inspections', { keyPath: 'id' });
      if (!d.objectStoreNames.contains('media')) { const s = d.createObjectStore('media', { keyPath: 'id' }); s.createIndex('inspection_id', 'inspection_id'); }
      if (!d.objectStoreNames.contains('kv')) d.createObjectStore('kv');
    };
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
  return dbp;
}
function req2p(r) { return new Promise((res, rej) => { r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error); }); }
async function os(name, mode = 'readonly') { const d = await idb(); return d.transaction(name, mode).objectStore(name); }

// ---------- memória (demo) ----------
const mem = { inspections: new Map(), media: new Map(), kv: new Map() };

export const uid = () => (crypto.randomUUID ? crypto.randomUUID() : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => { const r = (Math.random() * 16) | 0; return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16); }));

export const kv = {
  async get(k, d = null) { if (DEMO) return mem.kv.has(k) ? mem.kv.get(k) : d; const v = await req2p((await os('kv')).get(k)); return v === undefined ? d : v; },
  async set(k, v) { if (DEMO) return mem.kv.set(k, v); return req2p((await os('kv', 'readwrite')).put(v, k)); },
  async del(k) { if (DEMO) return mem.kv.delete(k); return req2p((await os('kv', 'readwrite')).delete(k)); },
};

export const inspections = {
  async all() {
    const list = DEMO ? [...mem.inspections.values()] : await req2p((await os('inspections')).getAll());
    return list.sort((a, b) => (b.updated_at || '').localeCompare(a.updated_at || ''));
  },
  async get(id) { if (DEMO) return structuredClone(mem.inspections.get(id) || null); return (await req2p((await os('inspections')).get(id))) || null; },
  async put(ins) { ins.updated_at = new Date().toISOString(); if (DEMO) return mem.inspections.set(ins.id, structuredClone(ins)); return req2p((await os('inspections', 'readwrite')).put(ins)); },
  async del(id) {
    if (DEMO) { mem.inspections.delete(id); return; }
    await req2p((await os('inspections', 'readwrite')).delete(id));
    for (const m of await media.byInspection(id)) await media.del(m.id);
  },
};

export const media = {
  async get(id) { if (DEMO) return mem.media.get(id) || null; return (await req2p((await os('media')).get(id))) || null; },
  async put(m) { if (DEMO) return mem.media.set(m.id, m); return req2p((await os('media', 'readwrite')).put(m)); },
  async patch(id, data) { const m = await media.get(id); if (!m) return; Object.assign(m, data); await media.put(m); return m; },
  async del(id) { urls.delete(id); if (DEMO) return mem.media.delete(id); return req2p((await os('media', 'readwrite')).delete(id)); },
  async byInspection(id) { if (DEMO) return [...mem.media.values()].filter((m) => m.inspection_id === id); return req2p((await os('media')).index('inspection_id').getAll(id)); },
};

// URLs de exibição (blob: ou url remota)
const urls = new Map();
export async function mediaUrl(id) {
  if (urls.has(id)) return urls.get(id);
  const m = await media.get(id);
  if (!m) return '';
  const u = m.blob ? URL.createObjectURL(m.blob) : m.url || '';
  urls.set(id, u);
  return u;
}

export async function storageEstimate() {
  try { const e = await navigator.storage.estimate(); return e; } catch { return null; }
}
export async function persist() { try { if (navigator.storage && navigator.storage.persist) await navigator.storage.persist(); } catch {} }

export function seedDemo(state) {
  for (const i of state.inspections) mem.inspections.set(i.id, i);
  for (const m of state.media) mem.media.set(m.id, m);
  for (const [k, v] of Object.entries(state.kv || {})) mem.kv.set(k, v);
}
