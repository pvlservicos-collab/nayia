// Dados iniciais: administrador, vistoriador, modelos e (opcional) vistorias de demonstração
try { process.loadEnvFile(require('path').join(__dirname, '..', '.env')); } catch {}
const fs = require('fs');
const path = require('path');
const { run, get, uid, token, hashPassword, setSetting, getSetting, nextCode, logEvent, UPLOAD_DIR, DATA_DIR } = require('./db');
const D = require('./defaults');

function seed({ demo = true } = {}) {
  const adminEmail = process.env.ADMIN_EMAIL || 'admin@vistto.app';
  const adminPass = process.env.ADMIN_PASSWORD || 'admin123';
  const adminId = uid(), inspId = uid();
  run('INSERT INTO users(id,name,email,password,role,phone) VALUES(?,?,?,?,?,?)', adminId, process.env.ADMIN_NAME || 'Administrador', adminEmail, hashPassword(adminPass), 'admin', '');
  run('INSERT INTO users(id,name,email,password,role,phone) VALUES(?,?,?,?,?,?)', inspId, 'Pedro Henrique', 'vistoriador@vistto.app', hashPassword('123456'), 'vistoriador', '(92) 99999-0000');

  if (!Object.keys(getSetting('company', {})).length) setSetting('company', D.COMPANY);
  for (const t of D.DEFAULT_TEMPLATES) run('INSERT INTO templates(id,name,type,rooms) VALUES(?,?,?,?)', uid(), t.name, t.type, JSON.stringify(t.rooms));

  console.log(`\n  ✔ Usuário administrador: ${adminEmail} / ${adminPass}`);
  console.log('  ✔ Vistoriador de exemplo: vistoriador@vistto.app / 123456\n');
  if (demo) demoData(adminId, inspId);
}

function copyPhoto(n, id) {
  const src = path.join(__dirname, 'seed-assets', `p${n}.jpg`);
  const name = `${id}.jpg`;
  fs.copyFileSync(src, path.join(UPLOAD_DIR, name));
  return { name, size: fs.statSync(src).size };
}

function demoData(adminId, inspId) {
  // ---------- Vistoria 1: aprovada, com link público ----------
  const A = uid();
  const t0 = new Date(Date.now() - 1000 * 60 * 60 * 26);
  const ts = (min) => new Date(t0.getTime() + min * 60000).toISOString();
  run(`INSERT INTO inspections(id,code,type,status,review_stage,inspector_id,property,parties,meters,contract,general_notes,public_token,contest_token,inspected_at,submitted_at,approved_at)
       VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,datetime('now','-1 day'),datetime('now','-20 hours'))`,
  A, nextCode(), 'entrada', 'aprovada', 5, inspId,
  JSON.stringify({ identification: 'PARADISE LAKE AP 202 TORRE MICHIGAN', cep: '69033-410', street: 'Rua Manoel Batista', number: '725', complement: 'AP 202 - Torre Michigan', district: 'São Jorge', city: 'Manaus', state: 'AM', type: 'Apartamento', purpose: 'Residencial', area: '64.00', furnished: 'Semimobiliado' }),
  JSON.stringify({ locadores: [{ name: 'MARIA AURINEI PEIXOTO DA SILVA', cpf: '000.000.000-00', email: 'locadora@exemplo.com' }], locatarios: [{ name: 'DIEGO SOARES SOUZA', cpf: '111.111.111-11', email: 'locatario@exemplo.com', phone: '(92) 98209-2645' }], fiadores: [], testemunhas: [], executed_by: 'Próprio Corretor/Imobiliária' }),
  JSON.stringify({ energia: { number: '7845120', reading: '04512 kWh' }, agua: { number: 'HM-22981', reading: '00231 m³' } }),
  JSON.stringify({ rent: 'R$ 2.400,00', start: '2026-10-22', end: '2027-10-22', months: '12' }),
  'Imóvel entregue limpo, com 2 controles do portão e 3 chaves.', token(8), token(8), ts(0));

  const rooms = [
    { name: 'Sala', items: [
      { name: 'Lustre', condition: 'bom' },
      { name: 'Painel de TV', condition: 'regular', notes: 'Painel em MDF na cor carvalho claro com nicho branco.', nc: [{ title: 'Painel com avaria conforme imagem', description: 'Lascado na quina inferior direita e furos de fixação aparentes na parte branca.', photos: [[0, [{ x: 0.3, y: 0.82, r: 0.09 }]], [1, [{ x: 0.82, y: 0.62, r: 0.1 }, { x: 0.86, y: 0.86, r: 0.07 }]], [2, [{ x: 0.62, y: 0.6, r: 0.1 }]]] }], photos: [5, 6] },
      { name: 'Lâmpada da sala', condition: 'bom', quantity: 2 },
      { name: 'Ar condicionado', condition: 'bom', functioning: 'funcionando' },
      { name: 'Rack', condition: 'regular', nc: [{ title: 'Rack esfarelado na base', description: 'Base do rack com MDF esfarelado por umidade.', photos: [[3, [{ x: 0.45, y: 0.55, r: 0.12 }]]] }] },
    ], photos: [4, 7] },
    { name: 'Varanda da sala', items: [
      { name: 'Lâmpada', condition: 'bom', quantity: 1 },
      { name: 'Varal de roupa', condition: 'bom', photos: [9] },
      { name: 'Condensadora de ar', condition: 'bom', functioning: 'funcionando', photos: [10] },
    ], photos: [8] },
    { name: 'Cozinha', items: [
      { name: 'Pia da cozinha', condition: 'bom' },
      { name: 'Armário de baixo da pia', condition: 'bom' },
      { name: 'Cooktop', condition: 'novo', functioning: 'funcionando' },
    ], photos: [] },
  ];
  let minute = 1;
  rooms.forEach((r, ri) => {
    const rid = uid();
    run('INSERT INTO rooms(id,inspection_id,name,position,done) VALUES(?,?,?,?,1)', rid, A, r.name, ri);
    r.photos.forEach((n, pi) => { const id = uid(); const f = copyPhoto(n, id); run('INSERT INTO media(id,inspection_id,room_id,scope,kind,file,mime,size,taken_at,position) VALUES(?,?,?,?,?,?,?,?,?,?)', id, A, rid, 'room', 'photo', f.name, 'image/jpeg', f.size, ts(minute++), pi); });
    r.items.forEach((it, ii) => {
      const iid = uid();
      run('INSERT INTO items(id,inspection_id,room_id,name,position,condition,functioning,quantity,notes,has_nc) VALUES(?,?,?,?,?,?,?,?,?,?)', iid, A, rid, it.name, ii, it.condition, it.functioning || null, it.quantity || null, it.notes || '', it.nc ? 1 : 0);
      (it.photos || []).forEach((n, pi) => { const id = uid(); const f = copyPhoto(n, id); run('INSERT INTO media(id,inspection_id,room_id,item_id,scope,kind,file,mime,size,taken_at,position) VALUES(?,?,?,?,?,?,?,?,?,?,?)', id, A, rid, iid, 'item', 'photo', f.name, 'image/jpeg', f.size, ts(minute++), pi); });
      (it.nc || []).forEach((n, ni) => {
        const nid = uid();
        run('INSERT INTO ncs(id,inspection_id,room_id,item_id,title,description,position) VALUES(?,?,?,?,?,?,?)', nid, A, rid, iid, n.title, n.description, ni);
        n.photos.forEach(([p, mk], pi) => { const id = uid(); const f = copyPhoto(p, id); run('INSERT INTO media(id,inspection_id,room_id,item_id,nc_id,scope,kind,file,mime,size,taken_at,markers,position) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)', id, A, rid, iid, nid, 'nc', 'photo', f.name, 'image/jpeg', f.size, ts(minute++), JSON.stringify(mk), pi); });
      });
    });
  });
  logEvent(A, 'criada', 'Vistoria criada no app', inspId);
  logEvent(A, 'enviada', 'Vistoria enviada pelo vistoriador para aprovação', inspId);
  logEvent(A, 'aprovada', 'Laudo aprovado e link público gerado', adminId);

  // ---------- Vistoria 2: recebida do app, aguardando aprovação ----------
  const B = uid();
  run(`INSERT INTO inspections(id,code,type,status,review_stage,inspector_id,property,parties,inspected_at,submitted_at) VALUES(?,?,?,?,?,?,?,?,?,datetime('now','-2 hours'))`,
    B, nextCode(), 'entrada', 'enviada', 1, inspId, JSON.stringify({ type: 'Apartamento' }), JSON.stringify({ locatarios: [{ name: '' }] }), new Date(Date.now() - 1000 * 60 * 60 * 3).toISOString());
  const rb = [['Sala', [4, 7], [['Painel de TV', 'regular', [[1, [{ x: 0.8, y: 0.6, r: 0.1 }]]]], ['Ar condicionado', 'bom', null]]], ['Varanda', [8], [['Condensadora de ar', 'bom', null]]], ['Cozinha', [], [['Pia', 'bom', null]]], ['Quarto', [], []]];
  rb.forEach(([name, photos, items], ri) => {
    const rid = uid();
    run('INSERT INTO rooms(id,inspection_id,name,position,done) VALUES(?,?,?,?,?)', rid, B, name, ri, photos.length ? 1 : 0);
    photos.forEach((n, pi) => { const id = uid(); const f = copyPhoto(n, id); run('INSERT INTO media(id,inspection_id,room_id,scope,kind,file,mime,size,taken_at,position) VALUES(?,?,?,?,?,?,?,?,?,?)', id, B, rid, 'room', 'photo', f.name, 'image/jpeg', f.size, new Date(Date.now() - 1000 * 60 * (200 - pi)).toISOString(), pi); });
    items.forEach(([iname, cond, nc], ii) => {
      const iid = uid();
      run('INSERT INTO items(id,inspection_id,room_id,name,position,condition,has_nc) VALUES(?,?,?,?,?,?,?)', iid, B, rid, iname, ii, cond, nc ? 1 : 0);
      if (nc) { const nid = uid(); run('INSERT INTO ncs(id,inspection_id,room_id,item_id,title,description,position) VALUES(?,?,?,?,?,?,0)', nid, B, rid, iid, 'Quina lascada', 'Quina do painel lascada próximo ao rodapé.');
        nc.forEach(([p, mk]) => { const id = uid(); const f = copyPhoto(p, id); run('INSERT INTO media(id,inspection_id,room_id,item_id,nc_id,scope,kind,file,mime,size,taken_at,markers) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', id, B, rid, iid, nid, 'nc', 'photo', f.name, 'image/jpeg', f.size, new Date().toISOString(), JSON.stringify(mk)); }); }
    });
  });
  logEvent(B, 'criada', 'Vistoria criada no app', inspId);
  logEvent(B, 'enviada', 'Vistoria enviada pelo vistoriador para aprovação', inspId);

  run("INSERT INTO requests(id,title,address,type,client,scheduled_at,inspector_id,status) VALUES(?,?,?,?,?,?,?,?)", uid(), 'Smart Tower Itaporanga - Apto 708', 'Av. Sérgio Milliet, 85 - Ponta Negra', 'entrada', 'Adriana Dias de Oliveira', new Date(Date.now() + 86400000).toISOString().slice(0, 16), inspId, 'agendada');
  run("INSERT INTO requests(id,title,address,type,client,status) VALUES(?,?,?,?,?,?)", uid(), 'Acquarelle - Torre Ciano 1803', 'Av. Coronel Teixeira, 4475', 'saida', 'Raquel Costa', 'solicitada');
  run("INSERT INTO people(id,name,cpf,email,phone,kind) VALUES(?,?,?,?,?,?)", uid(), 'DIEGO SOARES SOUZA', '111.111.111-11', 'locatario@exemplo.com', '(92) 98209-2645', 'locatario');
  run("INSERT INTO people(id,name,cpf,email,phone,kind) VALUES(?,?,?,?,?,?)", uid(), 'MARIA AURINEI PEIXOTO DA SILVA', '000.000.000-00', 'locadora@exemplo.com', '', 'locador');
}

module.exports = { seed };

if (require.main === module) {
  if (process.argv.includes('--reset')) {
    for (const f of ['vistoria.db', 'vistoria.db-wal', 'vistoria.db-shm']) { try { fs.unlinkSync(path.join(DATA_DIR, f)); } catch {} }
    console.log('Banco apagado. Reinicie o servidor para recriar.');
    process.exit(0);
  }
  if (get('SELECT id FROM users LIMIT 1')) { console.log('Banco já possui dados. Use "npm run reset" para recomeçar.'); process.exit(0); }
  seed({ demo: !process.argv.includes('--no-demo') });
}
