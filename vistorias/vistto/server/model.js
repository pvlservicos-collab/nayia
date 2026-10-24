// Montagem e persistência da árvore de uma vistoria
const { all, get, run, tx, J, uid, nextCode, logEvent } = require('./db');
const { TYPES, STATUSES, CONDITIONS } = require('./defaults');

function mediaRow(m) {
  return {
    id: m.id, room_id: m.room_id, item_id: m.item_id, nc_id: m.nc_id, scope: m.scope, kind: m.kind,
    url: `/media/${m.file}`, file: m.file, mime: m.mime, size: m.size, taken_at: m.taken_at,
    transcript: m.transcript, markers: J(m.markers, []), caption: m.caption, position: m.position,
  };
}

function loadInspection(id, { withEvents = true } = {}) {
  const i = get('SELECT * FROM inspections WHERE id=?', id);
  if (!i) return null;
  const inspector = i.inspector_id ? get('SELECT id,name,email,phone FROM users WHERE id=?', i.inspector_id) : null;
  const rooms = all('SELECT * FROM rooms WHERE inspection_id=? ORDER BY position, rowid', id);
  const items = all('SELECT * FROM items WHERE inspection_id=? ORDER BY position, rowid', id);
  const ncs = all('SELECT * FROM ncs WHERE inspection_id=? ORDER BY position, rowid', id);
  const media = all('SELECT * FROM media WHERE inspection_id=? ORDER BY position, taken_at, rowid', id).map(mediaRow);

  // vistoria de origem (para comparativo entrada x saída)
  let sourceItems = {};
  if (i.source_inspection_id) {
    for (const s of all('SELECT id, condition, functioning FROM items WHERE inspection_id=?', i.source_inspection_id)) sourceItems[s.id] = s;
  }

  const tree = rooms.map((r) => ({
    id: r.id, name: r.name, position: r.position, notes: r.notes || '', done: !!r.done,
    media: media.filter((m) => m.room_id === r.id && !m.item_id && !m.nc_id),
    ncs: ncs.filter((n) => n.room_id === r.id && !n.item_id).map((n) => ({ ...n, media: media.filter((m) => m.nc_id === n.id) })),
    items: items.filter((it) => it.room_id === r.id).map((it) => ({
      id: it.id, name: it.name, position: it.position, condition: it.condition, functioning: it.functioning,
      quantity: it.quantity, notes: it.notes || '', has_nc: !!it.has_nc, source_item_id: it.source_item_id,
      source: it.source_item_id ? sourceItems[it.source_item_id] || null : null,
      media: media.filter((m) => m.item_id === it.id && !m.nc_id),
      ncs: ncs.filter((n) => n.item_id === it.id).map((n) => ({ ...n, media: media.filter((m) => m.nc_id === n.id) })),
    })),
  }));

  const out = {
    id: i.id, code: i.code, type: i.type, typeLabel: (TYPES[i.type] || TYPES.entrada).label,
    status: i.status, statusLabel: (STATUSES[i.status] || {}).label || i.status, review_stage: i.review_stage,
    inspector, property: J(i.property), parties: J(i.parties), meters: J(i.meters), contract: J(i.contract), extra: J(i.extra),
    general_notes: i.general_notes || '', public_token: i.public_token, contest_token: i.contest_token,
    clicksign: J(i.clicksign), unsigned_pdf: i.unsigned_pdf, signed_pdf: i.signed_pdf,
    source_inspection_id: i.source_inspection_id,
    created_at: i.created_at, updated_at: i.updated_at, inspected_at: i.inspected_at, submitted_at: i.submitted_at, approved_at: i.approved_at, signed_at: i.signed_at,
    rooms: tree,
    media_general: media.filter((m) => !m.room_id),
    signers: all('SELECT * FROM signers WHERE inspection_id=? ORDER BY rowid', id),
    contestations: all('SELECT * FROM contestations WHERE inspection_id=? ORDER BY created_at DESC', id).map((c) => ({ ...c, files: J(c.files, []) })),
  };
  out.stats = stats(out);
  if (withEvents) out.events = all('SELECT e.*, u.name user_name FROM events e LEFT JOIN users u ON u.id=e.user_id WHERE inspection_id=? ORDER BY e.id DESC LIMIT 200', id);
  return out;
}

function stats(ins) {
  let photos = 0, audios = 0, videos = 0, items = 0, ncs = 0;
  const count = (arr) => arr.forEach((m) => { if (m.kind === 'photo') photos++; else if (m.kind === 'audio') audios++; else if (m.kind === 'video') videos++; });
  for (const r of ins.rooms) {
    count(r.media); ncs += r.ncs.length; r.ncs.forEach((n) => count(n.media));
    for (const it of r.items) { items++; count(it.media); ncs += it.ncs.length; it.ncs.forEach((n) => count(n.media)); }
  }
  count(ins.media_general || []);
  return { rooms: ins.rooms.length, items, photos, audios, videos, ncs };
}

// Lista de todas as avarias (inconformidades), com cômodo e item
function allNcs(ins) {
  const list = [];
  ins.rooms.forEach((r, ri) => {
    r.ncs.forEach((n) => list.push({ room: r.name, roomIndex: ri + 1, item: null, ...n }));
    r.items.forEach((it) => it.ncs.forEach((n) => list.push({ room: r.name, roomIndex: ri + 1, item: it.name, ...n })));
  });
  return list;
}

// Completude do laudo (o que falta para ficar igual ao modelo)
function completeness(ins) {
  const p = ins.property || {}, pa = ins.parties || {};
  const checks = [
    ['Identificação do imóvel', !!p.identification],
    ['CEP', !!p.cep],
    ['Endereço completo', !!(p.street && p.city)],
    ['Tipo / finalidade', !!(p.type && p.purpose)],
    ['Metragem', !!p.area],
    ['Mobília', !!p.furnished],
    ['Locador(es)', (pa.locadores || []).some((x) => x.name)],
    ['Locatário(s)', (pa.locatarios || []).some((x) => x.name)],
    ['E-mail dos signatários', [...(pa.locadores || []), ...(pa.locatarios || [])].some((x) => x.email)],
    ['Contrato anexado', !!(ins.contract && ins.contract.media_id)],
    ['Cômodos registrados', ins.rooms.length > 0],
    ['Fotos em todos os cômodos', ins.rooms.length > 0 && ins.rooms.every((r) => r.media.length || r.items.some((i) => i.media.length))],
    ['Estado de todos os itens', ins.rooms.every((r) => r.items.every((i) => i.condition))],
    ['Leitura dos medidores', !!(ins.meters && (ins.meters.energia?.reading || ins.meters.agua?.reading || ins.meters.gas?.reading))],
  ];
  const done = checks.filter((c) => c[1]).length;
  return { score: Math.round((done / checks.length) * 100), checks: checks.map(([label, ok]) => ({ label, ok })) };
}

const EDITABLE_BY_APP = ['rascunho', 'enviada'];

// Sincronização vinda do app (idempotente; ids gerados no aparelho)
function syncFromApp(user, p) {
  return tx(() => {
    let ins = get('SELECT * FROM inspections WHERE id=?', p.id);
    if (ins && ins.inspector_id && ins.inspector_id !== user.id && user.role !== 'admin') throw Object.assign(new Error('Vistoria pertence a outro vistoriador'), { status: 403 });
    const structural = !ins || EDITABLE_BY_APP.includes(ins.status);
    if (!ins) {
      run(`INSERT INTO inspections(id,code,type,status,inspector_id,property,parties,meters,extra,general_notes,inspected_at,source_inspection_id)
           VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`, p.id, nextCode(), p.type || 'entrada', 'rascunho', user.id,
      JSON.stringify(p.property || {}), JSON.stringify(p.parties || {}), JSON.stringify(p.meters || {}), JSON.stringify(p.extra || {}), p.general_notes || '', p.inspected_at || new Date().toISOString(), p.source_inspection_id || null);
      logEvent(p.id, 'criada', 'Vistoria criada no app', user.id);
      ins = get('SELECT * FROM inspections WHERE id=?', p.id);
    } else if (structural) {
      run(`UPDATE inspections SET type=?, property=?, parties=?, meters=?, extra=?, general_notes=?, updated_at=datetime('now') WHERE id=?`,
        p.type || ins.type, JSON.stringify(p.property || {}), JSON.stringify(p.parties || {}), JSON.stringify(p.meters || {}), JSON.stringify({ ...J(ins.extra), ...(p.extra || {}) }), p.general_notes || '', p.id);
    }
    if (structural && Array.isArray(p.rooms)) {
      const roomIds = [], itemIds = [], ncIds = [];
      p.rooms.forEach((r, ri) => {
        roomIds.push(r.id);
        run(`INSERT INTO rooms(id,inspection_id,name,position,notes,done) VALUES(?,?,?,?,?,?)
             ON CONFLICT(id) DO UPDATE SET name=excluded.name, position=excluded.position, notes=excluded.notes, done=excluded.done`, r.id, p.id, r.name, ri, r.notes || '', r.done ? 1 : 0);
        (r.items || []).forEach((it, ii) => {
          itemIds.push(it.id);
          run(`INSERT INTO items(id,inspection_id,room_id,name,position,condition,functioning,quantity,notes,has_nc,source_item_id) VALUES(?,?,?,?,?,?,?,?,?,?,?)
               ON CONFLICT(id) DO UPDATE SET room_id=excluded.room_id,name=excluded.name,position=excluded.position,condition=excluded.condition,functioning=excluded.functioning,quantity=excluded.quantity,notes=excluded.notes,has_nc=excluded.has_nc`,
          it.id, p.id, r.id, it.name, ii, it.condition || null, it.functioning || null, it.quantity || null, it.notes || '', it.has_nc ? 1 : 0, it.source_item_id || null);
          (it.has_nc ? it.ncs || [] : []).forEach((n, ni) => {
            ncIds.push(n.id);
            run(`INSERT INTO ncs(id,inspection_id,room_id,item_id,title,description,position) VALUES(?,?,?,?,?,?,?)
                 ON CONFLICT(id) DO UPDATE SET title=excluded.title, description=excluded.description, position=excluded.position, item_id=excluded.item_id, room_id=excluded.room_id`,
            n.id, p.id, r.id, it.id, n.title || 'Avaria', n.description || '', ni);
          });
        });
        (r.ncs || []).forEach((n, ni) => {
          ncIds.push(n.id);
          run(`INSERT INTO ncs(id,inspection_id,room_id,item_id,title,description,position) VALUES(?,?,?,?,?,?,?)
               ON CONFLICT(id) DO UPDATE SET title=excluded.title, description=excluded.description, position=excluded.position`,
          n.id, p.id, r.id, null, n.title || 'Avaria', n.description || '', ni);
        });
      });
      const del = (table, ids) => {
        const existing = all(`SELECT id FROM ${table} WHERE inspection_id=?`, p.id).map((x) => x.id);
        existing.filter((x) => !ids.includes(x)).forEach((x) => run(`DELETE FROM ${table} WHERE id=?`, x));
      };
      del('ncs', ncIds); del('items', itemIds); del('rooms', roomIds);
      // mídias órfãs (cômodo removido no app) são apagadas
      const keepMedia = new Set((p.media_ids || []));
      if (p.media_ids) all('SELECT id FROM media WHERE inspection_id=? AND scope != ?', p.id, 'contract').forEach((m) => { if (!keepMedia.has(m.id)) run('DELETE FROM media WHERE id=?', m.id); });
    }
    const known = all('SELECT id FROM media WHERE inspection_id=?', p.id).map((m) => m.id);
    const cur = get('SELECT id, code, status FROM inspections WHERE id=?', p.id);
    return { id: cur.id, code: cur.code, status: cur.status, known_media: known, structural };
  });
}

function cloneForExit(srcId, user) {
  const src = loadInspection(srcId, { withEvents: false });
  if (!src) return null;
  const id = uid();
  tx(() => {
    run(`INSERT INTO inspections(id,code,type,status,inspector_id,property,parties,meters,contract,source_inspection_id) VALUES(?,?,?,?,?,?,?,?,?,?)`,
      id, nextCode(), 'saida', 'rascunho', src.inspector ? src.inspector.id : user.id, JSON.stringify(src.property), JSON.stringify(src.parties), '{}', JSON.stringify(src.contract || {}), src.id);
    src.rooms.forEach((r, ri) => {
      const rid = uid();
      run('INSERT INTO rooms(id,inspection_id,name,position) VALUES(?,?,?,?)', rid, id, r.name, ri);
      r.items.forEach((it, ii) => run('INSERT INTO items(id,inspection_id,room_id,name,position,quantity,source_item_id) VALUES(?,?,?,?,?,?,?)', uid(), id, rid, it.name, ii, it.quantity, it.id));
    });
    logEvent(id, 'criada', `Vistoria de saída gerada a partir da vistoria #${src.code}`, user.id);
  });
  return id;
}

function listInspections(where = '1=1', params = []) {
  return all(`SELECT i.id, i.code, i.type, i.status, i.review_stage, i.property, i.parties, i.created_at, i.updated_at, i.submitted_at, i.approved_at, i.signed_at, i.public_token,
      u.name inspector_name,
      (SELECT COUNT(*) FROM rooms r WHERE r.inspection_id=i.id) rooms,
      (SELECT COUNT(*) FROM media m WHERE m.inspection_id=i.id AND m.kind='photo') photos,
      (SELECT COUNT(*) FROM ncs n WHERE n.inspection_id=i.id) ncs
    FROM inspections i LEFT JOIN users u ON u.id=i.inspector_id WHERE ${where} ORDER BY i.code DESC`, ...params).map((r) => {
    const p = J(r.property), pa = J(r.parties);
    return { ...r, property: p, typeLabel: (TYPES[r.type] || {}).label, statusLabel: (STATUSES[r.status] || {}).label,
      address: [p.street, p.number, p.complement, p.district, p.city, p.state].filter(Boolean).join(', '),
      people: [...(pa.locadores || []), ...(pa.locatarios || [])].map((x) => x.name).filter(Boolean), parties: undefined };
  });
}

module.exports = { loadInspection, stats, allNcs, completeness, syncFromApp, cloneForExit, listInspections, mediaRow, CONDITIONS };
