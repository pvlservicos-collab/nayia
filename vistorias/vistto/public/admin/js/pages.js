// Páginas do painel
import { html, useState, useEffect } from '/shared/vendor/preact-htm.js';
import { api, toast, modal, closeModal, confirmBox, Modal, Card, Inp, Sel, Switch, Empty, Loading, Status, STATUS, TYPES, fmtDate, fmtBytes, BarChart, Icon } from './ui.js';
import { nav } from './main.js';

const PageHead = ({ title, icon, sub, right }) => html`<div class="ph-head"><div><h1>${icon && html`<${Icon} name=${icon} size=${24} />`}${title}</h1>${sub && html`<p>${sub}</p>`}</div><span class="sp"></span>${right}</div>`;
function useLoad(fn, deps = []) {
  const [data, setData] = useState(null); const [v, setV] = useState(0);
  useEffect(() => { fn().then(setData).catch((e) => toast(e.message, 'err')); }, [...deps, v]);
  return [data, () => setV((x) => x + 1), setData];
}
async function newInspection() {
  const users = await api('/admin/users');
  const tpls = await api('/admin/templates');
  let f = { type: 'entrada', inspector_id: (users.find((u) => u.role === 'vistoriador') || users[0] || {}).id, template_id: '', identification: '' };
  const Form = () => { const [s, set] = useState(f); f = s; const u = (k) => (v) => set({ ...s, [k]: v });
    return html`<div class="grid2"><${Sel} label="Modalidade" value=${s.type} onChange=${u('type')} options=${Object.entries(TYPES)} /><${Sel} label="Vistoriador" value=${s.inspector_id} onChange=${u('inspector_id')} options=${users.filter((x) => x.active).map((x) => [x.id, x.name])} />
      <${Sel} label="Modelo de cômodos" value=${s.template_id} onChange=${u('template_id')} options=${[['', 'Sem modelo'], ...tpls.map((t) => [t.id, t.name])]} /><${Inp} label="Identificação do imóvel" value=${s.identification} onInput=${u('identification')} placeholder="Ex.: Edifício X - Apto 101" /></div>`; };
  modal(html`<${Modal} title="Nova vistoria pelo painel" onClose=${closeModal} footer=${html`<button class="btn ghost" onClick=${closeModal}>Cancelar</button><button class="btn primary" onClick=${async () => { const r = await api('/admin/inspections', { body: { ...f, property: { identification: f.identification } } }); closeModal(); nav(`/vistorias/${r.id}`); }}>Criar</button>`}><p class="muted small">Normalmente as vistorias chegam pelo app. Use isto para montar um laudo manualmente ou enviar fotos pelo computador.</p><${Form} /></${Modal}>`);
}

// 24-25/10 (Pedro): "ao invés de iniciar vistoria do 0, eu subo uma de outro lugar e o nosso sistema entende"
async function importInspection() {
  const users = await api('/admin/users');
  let f = { type: '', inspector_id: (users.find((u) => u.role === 'vistoriador') || users[0] || {}).id, url: '', file: null };
  const Form = () => { const [s, set] = useState(f); f = s; const u = (k) => (v) => set({ ...s, [k]: v });
    return html`<div class="grid2"><${Sel} label="Modalidade" value=${s.type} onChange=${u('type')} options=${[['', 'A do laudo'], ...Object.entries(TYPES)]} /><${Sel} label="Vistoriador" value=${s.inspector_id} onChange=${u('inspector_id')} options=${users.map((x) => [x.id, x.name])} /></div>
      <label class="af" style="margin:10px 0"><span>PDF do laudo</span><input type="file" accept="application/pdf" onChange=${(e) => set({ ...s, file: e.target.files[0] || null })} /></label>
      <${Inp} label="ou o link do laudo (PDF, Google Drive ou a página do laudo)" value=${s.url} onInput=${u('url')} />`; };
  let indo = false;
  const importar = async () => {
    if (indo) return;
    if (!f.file && !f.url.trim()) return toast('Escolha o PDF ou cole o link', 'err');
    indo = true; toast('Lendo o laudo… pode levar até 1 minuto');
    const fd = new FormData();
    if (f.file) fd.append('file', f.file, f.file.name); else fd.append('url', f.url.trim());
    if (f.type) fd.append('type', f.type);
    fd.append('inspector_id', f.inspector_id || '');
    try { const r = await api('/admin/inspections/import', { body: fd }); closeModal(); toast(`Importada: ${r.comodos} cômodo(s), ${r.itens} item(ns), ${r.avarias} avaria(s). Confira e complete.`); nav(`/vistorias/${r.id}`); }
    catch (e) { toast(e.message, 'err'); indo = false; }
  };
  modal(html`<${Modal} title="Importar vistoria de outro lugar" onClose=${closeModal} footer=${html`<button class="btn ghost" onClick=${closeModal}>Cancelar</button><button class="btn primary" onClick=${importar}>Importar</button>`}><p class="muted small">Suba o laudo de outra empresa: o sistema lê os cômodos, os itens, o estado de cada um e as avarias, e monta um rascunho para o vistoriador conferir. As fotos do laudo de fora não vêm.</p><${Form} /></${Modal}>`);
}

// ================= DASHBOARD =================
export function Dashboard() {
  const [d] = useLoad(() => api('/admin/dashboard'));
  if (!d) return html`<${Loading} />`;
  const k = d.kpis;
  const months = [...d.byMonth].reverse().map((m) => ({ ...m, label: new Date(m.m + '-15').toLocaleDateString('pt-BR', { month: 'short', year: '2-digit' }) }));
  const kpi = (label, value, icon, color, sub, href) => html`<a class="kpi-c" style=${`--c:${color}`} href=${href || null}><span class="kpi-ic"><${Icon} name=${icon} size=${20} /></span><small>${label}</small><b>${value}</b>${sub && html`<em>${sub}</em>`}</a>`;
  return html`<div class="pg">
    <${PageHead} title="Dashboard" icon="layers" sub="Visão geral das vistorias, aprovações e assinaturas" right=${html`<button class="btn primary" onClick=${newInspection}><${Icon} name="plus" size=${18} /> Nova vistoria</button>`} />
    <div class="kpi-row">${kpi('Vistorias no mês', k.month, 'clipboard', '#F97316', `${k.total} no total`)}${kpi('Mídias do mês', k.media_month, 'camera', '#5814B8', `${k.media_total} no total`)}${kpi('Armazenamento', fmtBytes(k.storage_bytes), 'box', '#7C3AED')}${kpi('Contestações abertas', k.contest_open, 'alert', '#EF4444', null, '#/contestacoes')}</div>
    <div class="flow-strip">${[['Aguardando aprovação', k.pending_approval, 'checkCircle', '#/aprovacoes'], ['Em assinatura', k.awaiting_sign, 'edit', '#/aprovacoes'], ['Assinadas', k.signed, 'shield', '#/vistorias']].map(([l, n, ic, h]) => html`<a class="fs-i" href=${h}><${Icon} name=${ic} size=${18} /><span>${l}</span><b>${n}</b></a>`)}</div>
    <div class="grid-dash">
      <${Card} title="Vistorias por mês" icon="layers" right=${html`<span class="legend"><i style="background:#8838F8"></i>Entrada<i style="background:#1B1B1E"></i>Saída<i style="background:#A78BFA"></i>Outras</span>`}>
        ${months.length ? html`<${BarChart} data=${months} keys=${['entrada', 'saida', 'outras']} colors=${['#8838F8', '#1B1B1E', '#A78BFA']} />` : html`<${Empty} />`}
      </${Card}>
      <${Card} title="Fila de aprovação" icon="checkCircle" right=${html`<a class="lnk" href="#/aprovacoes">Ver todas →</a>`}>
        ${d.queue.length ? html`<div class="qlist">${d.queue.map((i) => html`<a class="q-i" href=${`#/vistorias/${i.id}`}><span class="q-code">#${i.code}</span><div><b>${i.property.identification || i.address || 'Sem identificação'}</b><small>${i.inspector_name || '—'} · ${i.photos} fotos · ${i.ncs} avarias</small></div><${Status} s=${i.status} /></a>`)}</div>` : html`<${Empty} icon="checkCircle" text="Nenhuma vistoria aguardando" />`}
      </${Card}>
    </div>
    <div class="grid-dash">
      <${Card} title="Dados de vistoria" icon="list" pad=${false}><table class="atable"><thead><tr><th>Período</th><th>Vistorias</th><th>Mídias</th><th>Contestações</th></tr></thead><tbody>${d.byMonth.map((m) => html`<tr><td>${new Date(m.m + '-15').toLocaleDateString('pt-BR', { month: 'long', year: 'numeric' })}</td><td><b>${m.n}</b></td><td>${m.media}</td><td>${m.contest}</td></tr>`)}</tbody></table></${Card}>
      <${Card} title="Vistoriadores" icon="users" pad=${false}><table class="atable"><thead><tr><th>Vistoriador</th><th>Vistorias</th><th>Assinadas</th><th>Contestações</th></tr></thead><tbody>${d.inspectors.map((u) => html`<tr><td><span class="av sm">${u.name[0]}</span> ${u.name}</td><td><b>${u.n}</b></td><td>${u.signed || 0}</td><td>${u.contests}</td></tr>`)}</tbody></table></${Card}>
    </div>
    <${Card} title="Atividade recente" icon="sync"><div class="feed">${d.recent.map((e) => html`<a class="feed-i" href=${e.inspection_id ? `#/vistorias/${e.inspection_id}` : null}><span class=${'fd ' + e.kind}></span><b>${e.code ? `#${e.code}` : ''}</b> ${e.message}<small>${fmtDate(e.created_at)}</small></a>`)}</div></${Card}>
  </div>`;
}

// ================= VISTORIAS =================
export function Inspections() {
  const [q, setQ] = useState(''); const [status, setStatus] = useState(''); const [type, setType] = useState('');
  const [list, reload] = useLoad(() => api(`/admin/inspections?status=${status}&type=${type}`), [status, type]);
  const shown = (list || []).filter((i) => !q || JSON.stringify([i.code, i.address, i.property.identification, i.people, i.inspector_name]).toLowerCase().includes(q.toLowerCase()));
  return html`<div class="pg">
    <${PageHead} title="Vistorias" icon="home" sub=${list ? `${list.length} vistoria(s)` : ''} right=${html`<button class="btn ghost" onClick=${importInspection}><${Icon} name="file" size=${18} /> Importar vistoria</button> <button class="btn primary" onClick=${newInspection}><${Icon} name="plus" size=${18} /> Nova vistoria</button>`} />
    <div class="acard filters"><div class="search-a"><${Icon} name="search" size=${18} /><input placeholder="Pesquisar por código, endereço, pessoas, vistoriador…" value=${q} onInput=${(e) => setQ(e.target.value)} /></div>
      <${Sel} value=${status} onChange=${setStatus} options=${[['', 'Todos os status'], ...Object.entries(STATUS).map(([k, v]) => [k, v[0]])]} /><${Sel} value=${type} onChange=${setType} options=${[['', 'Todos os tipos'], ...Object.entries(TYPES)]} /></div>
    ${!list ? html`<${Loading} />` : shown.length ? html`<div class="acard"><table class="atable hover"><thead><tr><th>Código</th><th>Status</th><th>Imóvel</th><th>Tipo</th><th>Vistoriador</th><th>Pessoas</th><th>Mídias</th><th>Atualizado</th><th></th></tr></thead><tbody>
      ${shown.map((i) => html`<tr onClick=${() => nav(`/vistorias/${i.id}`)}><td><b>#${i.code}</b></td><td><${Status} s=${i.status} /></td><td class="wrap"><b>${i.property.identification || '—'}</b><small>${i.address}</small></td><td>${TYPES[i.type]}</td><td>${i.inspector_name || '—'}</td><td class="wrap small">${i.people.slice(0, 3).join(', ') || '—'}</td><td><span class="mini"><${Icon} name="camera" size=${14} />${i.photos}</span> ${i.ncs ? html`<span class="mini red"><${Icon} name="alert" size=${14} />${i.ncs}</span>` : ''}</td><td class="small">${fmtDate(i.updated_at)}</td>
      <td>${i.public_token ? html`<a class="ib" title="Laudo público" href=${`/v/${i.public_token}`} target="_blank" onClick=${(e) => e.stopPropagation()}><${Icon} name="link" size=${17} /></a>` : ''}</td></tr>`)}</tbody></table></div>` : html`<${Empty} text="Nenhuma vistoria encontrada" />`}
  </div>`;
}

// ================= APROVAÇÕES (fluxo em etapas) =================
export function Approvals() {
  const [list, reload] = useLoad(() => api('/admin/inspections'));
  if (!list) return html`<${Loading} />`;
  const cols = [['enviada', 'Recebidas do app', 'cloud'], ['em_revisao', 'Em revisão', 'edit'], ['aprovada', 'Aprovadas · link público', 'link'], ['em_assinatura', 'Em assinatura', 'send'], ['assinada', 'Assinadas', 'shield']];
  return html`<div class="pg">
    <${PageHead} title="Fluxo de aprovação" icon="checkCircle" sub="Toda vistoria enviada pelo vistoriador passa por estas etapas antes de virar laudo público e ir para assinatura." />
    <div class="kanban">${cols.map(([s, l, ic]) => { const items = list.filter((i) => i.status === s); return html`<div class="kcol"><div class="kcol-h"><${Icon} name=${ic} size=${17} /><b>${l}</b><span class="count">${items.length}</span></div>
      <div class="kcol-b">${items.length ? items.map((i) => html`<a class="kcard" href=${`#/vistorias/${i.id}`}><div class="kc-top"><b>#${i.code}</b><span class="pill gray">${TYPES[i.type]}</span></div><p>${i.property.identification || i.address || 'Imóvel sem identificação'}</p>
        <div class="kc-meta"><span><${Icon} name="user" size=${13} />${i.inspector_name || '—'}</span><span><${Icon} name="camera" size=${13} />${i.photos}</span>${i.ncs ? html`<span class="red"><${Icon} name="alert" size=${13} />${i.ncs}</span>` : ''}</div>
        <small>${fmtDate(i.submitted_at || i.updated_at)}</small></a>`) : html`<div class="kempty">Vazio</div>`}</div></div>`; })}</div>
  </div>`;
}

// ================= SOLICITAÇÕES =================
const RSTAT = [['solicitada', 'Solicitada'], ['agendada', 'Agendada'], ['em_andamento', 'Em andamento'], ['concluida', 'Concluída'], ['cancelada', 'Cancelada']];
export function Requests() {
  const [list, reload] = useLoad(() => api('/admin/requests'));
  const [users] = useLoad(() => api('/admin/users'));
  const [drag, setDrag] = useState(null);
  function edit(r = { status: 'solicitada', type: 'entrada' }) {
    let f = { ...r };
    const F = () => { const [s, set] = useState(f); f = s; const u = (k) => (v) => set({ ...s, [k]: v });
      return html`<div class="grid2"><${Inp} cls="full" label="Título / imóvel" value=${s.title} onInput=${u('title')} /><${Inp} cls="full" label="Endereço" value=${s.address} onInput=${u('address')} />
      <${Sel} label="Tipo" value=${s.type} onChange=${u('type')} options=${Object.entries(TYPES)} /><${Inp} label="Cliente" value=${s.client} onInput=${u('client')} />
      <${Inp} label="Data e hora" type="datetime-local" value=${s.scheduled_at} onInput=${u('scheduled_at')} /><${Sel} label="Vistoriador" value=${s.inspector_id} onChange=${u('inspector_id')} options=${[['', '—'], ...(users || []).map((x) => [x.id, x.name])]} />
      <${Sel} label="Status" value=${s.status} onChange=${u('status')} options=${RSTAT} /><${Inp} cls="full" area label="Observações" value=${s.notes} onInput=${u('notes')} /></div>`; };
    modal(html`<${Modal} title=${r.id ? 'Editar solicitação' : 'Nova solicitação'} onClose=${closeModal} footer=${html`${r.id && html`<button class="btn ghost danger-t" onClick=${async () => { await api(`/admin/requests/${r.id}`, { method: 'DELETE' }); closeModal(); reload(); }}>Excluir</button>`}<span class="sp"></span><button class="btn ghost" onClick=${closeModal}>Cancelar</button><button class="btn primary" onClick=${async () => { if (!f.title) return toast('Informe o título', 'err'); await api('/admin/requests', { body: f }); closeModal(); reload(); toast('Solicitação salva'); }}>Salvar</button>`}><${F} /></${Modal}>`);
  }
  async function drop(status) { if (!drag || drag.status === status) return; await api('/admin/requests', { body: { ...drag, status } }); setDrag(null); reload(); }
  const uname = (id) => ((users || []).find((u) => u.id === id) || {}).name;
  return html`<div class="pg">
    <${PageHead} title="Minhas solicitações" icon="calendar" sub="Agende vistorias e distribua para os vistoriadores. Arraste os cartões entre as colunas." right=${html`<button class="btn primary" onClick=${() => edit()}><${Icon} name="plus" size=${18} /> Nova solicitação</button>`} />
    ${!list ? html`<${Loading} />` : html`<div class="kanban">${RSTAT.map(([s, l]) => { const items = list.filter((x) => x.status === s); return html`<div class="kcol" onDragOver=${(e) => e.preventDefault()} onDrop=${() => drop(s)}><div class="kcol-h"><b>${l}</b><span class="count">${items.length}/${list.length}</span></div>
      <div class="kcol-b">${items.map((x) => html`<div class="kcard" draggable="true" onDragStart=${() => setDrag(x)} onClick=${() => edit(x)}><div class="kc-top"><b>${x.title}</b><span class="pill gray">${TYPES[x.type] || ''}</span></div><p>${x.address || ''}</p><div class="kc-meta">${x.scheduled_at ? html`<span><${Icon} name="calendar" size=${13} />${fmtDate(x.scheduled_at)}</span>` : ''}${x.inspector_id ? html`<span><${Icon} name="user" size=${13} />${uname(x.inspector_id)}</span>` : ''}</div>${x.client && html`<small>Cliente: ${x.client}</small>`}</div>`)}${!items.length ? html`<div class="kempty">Solte aqui</div>` : ''}</div></div>`; })}</div>`}
  </div>`;
}

// ================= CONTESTAÇÕES =================
export function Contestations() {
  const [list, reload] = useLoad(() => api('/admin/contestations'));
  return html`<div class="pg"><${PageHead} title="Contestações" icon="alert" sub="Divergências enviadas pelos locatários através do QR Code do laudo." />
    ${!list ? html`<${Loading} />` : list.length ? list.map((c) => html`<${ContestCard} key=${c.id} c=${c} reload=${reload} />`) : html`<${Empty} icon="alert" text="Nenhuma contestação recebida" />`}</div>`;
}
function ContestCard({ c, reload }) {
  const [resp, setResp] = useState(c.response || ''); const [st, setSt] = useState(c.status); const [notify, setNotify] = useState(true);
  return html`<div class="acard contest"><div class="ct-h"><span class=${'pill ' + ({ aberta: 'red', em_analise: 'amber', procedente: 'green', improcedente: 'gray' }[c.status] || 'gray')}>${c.status.replace('_', ' ')}</span><b>Laudo #${c.code}</b><span class="muted">${c.property.identification || ''}</span><span class="sp"></span><small class="muted">${fmtDate(c.created_at)}</small></div>
    <div class="ct-b"><div><p class="ct-who"><b>${c.name}</b> · ${c.email} ${c.phone ? `· ${c.phone}` : ''}${c.room ? html` · <span class="pill blue">${c.room}</span>` : ''}</p><p class="ct-msg">${c.message}</p>
      ${c.files.length ? html`<div class="ct-files">${c.files.map((f) => html`<a href=${f.url} target="_blank">${(f.mime || '').startsWith('image') ? html`<img src=${f.url} />` : html`<span><${Icon} name="file" size=${20} />${f.name}</span>`}</a>`)}</div>` : ''}</div>
      <div class="ct-r"><${Sel} label="Situação" value=${st} onChange=${setSt} options=${[['aberta', 'Aberta'], ['em_analise', 'Em análise'], ['procedente', 'Procedente'], ['improcedente', 'Improcedente']]} />
        <${Inp} area rows=${3} label="Resposta" value=${resp} onInput=${setResp} placeholder="Resposta enviada ao locatário por e-mail" />
        <${Switch} on=${notify} onChange=${setNotify} label="Enviar resposta por e-mail" />
        <button class="btn primary" onClick=${async () => { await api(`/admin/contestations/${c.id}`, { method: 'PATCH', body: { status: st, response: resp, notify } }); toast('Contestação atualizada'); reload(); }}>Salvar</button></div></div></div>`;
}

// ================= MODELOS =================
export function Templates() {
  const [list, reload] = useLoad(() => api('/admin/templates'));
  function edit(t = { name: '', type: 'entrada', rooms: [], active: 1 }) {
    let f = { ...t, rooms: (t.rooms || []).map((r) => ({ name: r.name, items: (r.items || []).join(', ') })) };
    const F = () => { const [s, set] = useState(f); f = s;
      return html`<div class="grid2"><${Inp} label="Nome do modelo" value=${s.name} onInput=${(v) => set({ ...s, name: v })} /><${Sel} label="Modalidade" value=${s.type} onChange=${(v) => set({ ...s, type: v })} options=${Object.entries(TYPES)} /></div>
        <div class="tpl-rooms">${s.rooms.map((r, i) => html`<div class="tpl-r"><input class="tr-n" value=${r.name} placeholder="Cômodo" onInput=${(e) => { const rooms = [...s.rooms]; rooms[i] = { ...r, name: e.target.value }; set({ ...s, rooms }); }} /><input value=${r.items} placeholder="Itens separados por vírgula: Piso, Paredes, Lâmpada…" onInput=${(e) => { const rooms = [...s.rooms]; rooms[i] = { ...r, items: e.target.value }; set({ ...s, rooms }); }} /><button class="ib" onClick=${() => set({ ...s, rooms: s.rooms.filter((_, j) => j !== i) })}><${Icon} name="trash" size=${16} /></button></div>`)}
        <button class="btn ghost sm" onClick=${() => set({ ...s, rooms: [...s.rooms, { name: '', items: '' }] })}><${Icon} name="plus" size=${16} /> Adicionar cômodo</button></div>`; };
    modal(html`<${Modal} width=${820} title=${t.id ? 'Editar modelo' : 'Novo modelo de vistoria'} onClose=${closeModal} footer=${html`<button class="btn ghost" onClick=${closeModal}>Cancelar</button><button class="btn primary" onClick=${async () => { await api('/admin/templates', { body: { ...f, rooms: f.rooms.filter((r) => r.name).map((r) => ({ name: r.name, items: r.items.split(',').map((x) => x.trim()).filter(Boolean) })) } }); closeModal(); reload(); toast('Modelo salvo'); }}>Salvar</button>`}><${F} /></${Modal}>`);
  }
  return html`<div class="pg"><${PageHead} title="Modelos de vistoria" icon="clipboard" sub="Cômodos e itens pré-definidos que o vistoriador aplica com um toque no app." right=${html`<button class="btn primary" onClick=${() => edit()}><${Icon} name="plus" size=${18} /> Novo modelo</button>`} />
    ${!list ? html`<${Loading} />` : html`<div class="acard"><table class="atable hover"><thead><tr><th>Modelo</th><th>Tipo</th><th>Cômodos</th><th>Itens</th><th>Ativo</th><th></th></tr></thead><tbody>${list.map((t) => html`<tr onClick=${() => edit(t)}><td><b>${t.name}</b></td><td>${TYPES[t.type] || '—'}</td><td>${t.rooms.length}</td><td>${t.rooms.reduce((a, r) => a + (r.items || []).length, 0)}</td>
      <td onClick=${(e) => e.stopPropagation()}><${Switch} on=${!!t.active} onChange=${async (v) => { await api('/admin/templates', { body: { ...t, active: v ? 1 : 0 } }); reload(); }} /></td><td><button class="ib" onClick=${async (e) => { e.stopPropagation(); if (await confirmBox({ title: 'Excluir modelo?', danger: true, ok: 'Excluir' })) { await api(`/admin/templates/${t.id}`, { method: 'DELETE' }); reload(); } }}><${Icon} name="trash" size=${17} /></button></td></tr>`)}</tbody></table></div>`}</div>`;
}

// ================= TELAS DO APP =================
const SCREENS = [
  ['Boas-vindas', '/onboarding'], ['Login', '/login'], ['Início', '/home'], ['Lista de vistorias', '/vistorias'],
  ['1 · Modalidade', '/v/demo/0'], ['2 · Cômodos (lista personalizada)', '/v/demo/1'], ['3 · Registro dos cômodos', '/v/demo/2'], ['Cômodo — fotos e itens', '/v/demo/room/r1'],
  ['Item com inconformidade', '/v/demo/room/r1?open=i2'], ['Destacar avaria (bolinhas)', '/v/demo/room/r1?marker=m6'], ['Comentário com áudio', '/v/demo/room/r1?open=i3&rec=1'], ['Câmera', '/camera'],
  ['4 · Dados + IA do contrato', '/v/demo/3'], ['5 · Revisão', '/v/demo/4'], ['Envio / sincronização', '/v/demo/send'], ['Central de sincronização', '/sync'],
  ['Suporte', '/suporte'], ['Perfil', '/perfil'],
];
export function Screens() {
  const [zoom, setZoom] = useState(0.62);
  return html`<div class="pg"><${PageHead} title="Telas do app" icon="eye" sub="Todas as telas do app do vistoriador, ao vivo e interativas (dados de demonstração — nada é gravado)." right=${html`<div class="seg-a">${[[0.5, 'P'], [0.62, 'M'], [0.8, 'G']].map(([z, l]) => html`<button class=${zoom === z ? 'on' : ''} onClick=${() => setZoom(z)}>${l}</button>`)}</div><a class="btn ghost" href="/app/?demo=1#/home" target="_blank"><${Icon} name="link" size=${16} /> Abrir demo</a>`} />
    <div class="phones" style=${`--z:${zoom}`}>${SCREENS.map(([l, r], i) => html`<div class="phone-w"><div class="phone"><div class="notch"></div><iframe loading="lazy" src=${`/app/?demo=1#${r}`} title=${l}></iframe></div><div class="phone-l"><span>${String(i + 1).padStart(2, '0')}</span>${l}<a href=${`/app/?demo=1#${r}`} target="_blank" title="Abrir"><${Icon} name="link" size=${14} /></a></div></div>`)}</div></div>`;
}

// ================= E-MAILS =================
export function Emails() {
  const [list, reload] = useLoad(() => api('/admin/emails'));
  async function open(e) { const full = await api(`/admin/emails/${e.id}`); modal(html`<${Modal} width=${760} title=${full.subject} onClose=${closeModal} footer=${html`<span class="muted small">Para: ${full.to_addr} · ${fmtDate(full.created_at)}</span><span class="sp"></span>${full.status !== 'enviado' && html`<button class="btn primary" onClick=${async () => { const r = await api(`/admin/emails/${e.id}/retry`, { body: {} }); toast(r.status === 'enviado' ? 'E-mail enviado' : r.error || r.status, r.status === 'enviado' ? 'ok' : 'err'); closeModal(); reload(); }}>Reenviar</button>`}`}><iframe class="mail-prev" srcdoc=${full.html}></iframe></${Modal}>`); }
  const ST = { enviado: 'green', sem_smtp: 'amber', erro: 'red', pendente: 'gray' };
  return html`<div class="pg"><${PageHead} title="E-mails" icon="mail" sub="E-mails de vistoria inicial, final, documento assinado e avisos. Sem SMTP configurado, eles ficam guardados aqui." right=${html`<a class="btn ghost" href="#/config/parametros?tab=emails">Editar modelos</a>`} />
    ${!list ? html`<${Loading} />` : list.length ? html`<div class="acard"><table class="atable hover"><thead><tr><th>Status</th><th>Tipo</th><th>Para</th><th>Assunto</th><th>Laudo</th><th>Data</th></tr></thead><tbody>${list.map((e) => html`<tr onClick=${() => open(e)}><td><span class=${'pill ' + (ST[e.status] || 'gray')}>${e.status === 'sem_smtp' ? 'Sem SMTP' : e.status}</span></td><td>${{ initial: 'Vistoria inicial', final: 'Vistoria final', signed: 'Doc. assinado', interno: 'Interno', contestacao: 'Contestação', suporte: 'Suporte', teste: 'Teste' }[e.kind] || e.kind || '—'}</td><td>${e.to_addr}</td><td class="wrap">${e.subject}</td><td>${e.code ? `#${e.code}` : '—'}</td><td class="small">${fmtDate(e.created_at)}</td></tr>`)}</tbody></table></div>` : html`<${Empty} icon="mail" text="Nenhum e-mail enviado ainda" />`}</div>`;
}

// ================= CONFIGURAÇÕES =================
export function Settings() {
  const [d, reload, setD] = useLoad(() => api('/admin/settings'));
  const [tab, setTab] = useState(new URLSearchParams(location.hash.split('?')[1] || '').get('tab') || 'empresa');
  if (!d) return html`<${Loading} />`;
  const upd = (sec, k, v) => setD({ ...d, [sec]: { ...d[sec], [k]: v } });
  const save = async (sec, body) => { await api(`/admin/settings/${sec}`, { method: 'PUT', body: body || d[sec] }); toast('Configurações salvas'); reload(); };
  const c = d.company, t = d.texts, em = d.emails, ig = d.integrations, pr = d.params;
  const tabs = [['empresa', 'Empresa / laudo', 'building'], ['termo', 'Termo', 'file'], ['emails', 'E-mails', 'mail'], ['integracoes', 'Integrações', 'link'], ['app', 'App', 'camera']];
  const intg = (sec, k, v) => setD({ ...d, integrations: { ...ig, [sec]: { ...ig[sec], [k]: v } } });
  return html`<div class="pg"><${PageHead} title="Parâmetros do sistema" icon="shield" />
    <div class="tabs-a">${tabs.map(([k, l, ic]) => html`<button class=${tab === k ? 'on' : ''} onClick=${() => setTab(k)}><${Icon} name=${ic} size=${16} />${l}</button>`)}</div>
    ${tab === 'empresa' && html`<${Card} title="Dados da imobiliária (cabeçalho do laudo)" icon="building"><div class="grid2">
      <${Inp} label="Nome fantasia" value=${c.name} onInput=${(v) => upd('company', 'name', v)} /><${Inp} label="Razão social" value=${c.legal_name} onInput=${(v) => upd('company', 'legal_name', v)} />
      <${Inp} label="CNPJ" value=${c.cnpj} onInput=${(v) => upd('company', 'cnpj', v)} /><${Inp} label="CRECI" value=${c.creci} onInput=${(v) => upd('company', 'creci', v)} />
      <${Inp} cls="full" label="Endereço" value=${c.address} onInput=${(v) => upd('company', 'address', v)} />
      <${Inp} label="Telefones (separados por vírgula)" value=${(c.phones || []).join(', ')} onInput=${(v) => upd('company', 'phones', v.split(',').map((x) => x.trim()).filter(Boolean))} /><${Inp} label="E-mail" value=${c.email} onInput=${(v) => upd('company', 'email', v)} />
      <${Inp} label="Site" value=${c.site} onInput=${(v) => upd('company', 'site', v)} />
      <label class="af"><span>Cor do laudo</span><div class="color-row"><input type="color" value=${c.color} onInput=${(e) => upd('company', 'color', e.target.value)} /><input value=${c.color} onInput=${(e) => upd('company', 'color', e.target.value)} /></div></label>
      <label class="af full"><span>Logo (PNG/SVG com fundo transparente)</span><div class="logo-row"><div class="logo-prev" style=${`background:${c.color}`}>${c.logo ? html`<img src=${c.logo} />` : html`<b>${(c.name || 'V').slice(0, 2)}</b>`}</div><input type="file" accept="image/*" onChange=${async (e) => { const fd = new FormData(); fd.append('file', e.target.files[0]); const r = await api('/admin/logo', { body: fd }); upd('company', 'logo', r.url); toast('Logo enviado — clique em Salvar'); }} />${c.logo && html`<button class="btn ghost sm" onClick=${() => upd('company', 'logo', '')}>Remover</button>`}</div></label>
    </div><div class="actions"><button class="btn primary" onClick=${() => save('company')}>Salvar</button></div></${Card}>`}
    ${tab === 'termo' && html`<${Card} title="Textos do termo de vistoria" icon="file"><p class="muted small">Cada linha vira um item/parágrafo no laudo.</p>
      <${Inp} area rows=${3} label="Introdução" value=${t.intro} onInput=${(v) => upd('texts', 'intro', v)} />
      <${Inp} area rows=${4} label="Critérios de avaliação de pintura" value=${t.paint} onInput=${(v) => upd('texts', 'paint', v)} />
      <${Inp} area rows=${4} label="Critérios de avaliação da limpeza" value=${t.cleaning} onInput=${(v) => upd('texts', 'cleaning', v)} />
      <${Inp} area rows=${9} label="Contestação" value=${t.contest} onInput=${(v) => upd('texts', 'contest', v)} />
      <${Inp} area rows=${9} label="Observações finais" value=${t.observations} onInput=${(v) => upd('texts', 'observations', v)} />
      <div class="actions"><button class="btn primary" onClick=${() => save('texts')}>Salvar</button></div></${Card}>`}
    ${tab === 'emails' && html`<div class="var-hint"><${Icon} name="info" size=${16} /> Variáveis: <code>{{nome}}</code> <code>{{imovel}}</code> <code>{{link}}</code> <code>{{empresa}}</code> <code>{{codigo}}</code> <code>{{tipo}}</code></div>
      ${[['initial', 'E-mail de vistoria inicial (entrada)'], ['final', 'E-mail de vistoria final (saída)'], ['signed', 'E-mail do documento assinado (vai com o PDF anexo)']].map(([k, l]) => html`<${Card} title=${l} icon="mail"><${Inp} label="Assunto" value=${em[k].subject} onInput=${(v) => setD({ ...d, emails: { ...em, [k]: { ...em[k], subject: v } } })} /><${Inp} area rows=${8} label="Mensagem" value=${em[k].body} onInput=${(v) => setD({ ...d, emails: { ...em, [k]: { ...em[k], body: v } } })} /></${Card}>`)}
      <div class="actions"><button class="btn primary" onClick=${() => save('emails')}>Salvar modelos</button></div>`}
    ${tab === 'integracoes' && html`
      <${Card} title="ClickSign — assinatura eletrônica" icon="edit" right=${html`<span class=${'pill ' + (ig.clicksign.enabled ? 'green' : 'amber')}>${ig.clicksign.enabled ? 'Conectado' : 'Modo simulação'}</span>`}>
        <p class="muted small">Gere o token em ClickSign → Configurações → API (use o ambiente Sandbox para testes). Sem token, o fluxo funciona em modo simulação e você confirma as assinaturas manualmente.</p>
        <div class="grid2"><${Inp} label="Access token" value=${ig.clicksign.token} onInput=${(v) => intg('clicksign', 'token', v)} placeholder=${ig.clicksign.env_token ? 'Definido no .env' : 'Cole o token'} /><${Sel} label="Ambiente" value=${ig.clicksign.env} onChange=${(v) => intg('clicksign', 'env', v)} options=${[['sandbox', 'Sandbox (testes)'], ['production', 'Produção']]} />
        <${Inp} label="Segredo do webhook (HMAC) — opcional" value=${ig.clicksign.webhook_secret} onInput=${(v) => intg('clicksign', 'webhook_secret', v)} /><label class="af"><span>URL do webhook (cadastre na ClickSign)</span><div class="copy-row"><input readonly value=${d.webhook_url} /><button class="btn ghost sm" onClick=${() => { navigator.clipboard.writeText(d.webhook_url); toast('Copiado'); }}>Copiar</button></div></label></div>
      </${Card}>
      <${Card} title="E-mail (SMTP)" icon="mail" right=${html`<span class=${'pill ' + (ig.smtp.enabled ? 'green' : 'amber')}>${ig.smtp.enabled ? 'Configurado' : 'Não configurado'}</span>`}>
        <div class="grid2"><${Inp} label="Servidor (host)" value=${ig.smtp.host} onInput=${(v) => intg('smtp', 'host', v)} placeholder="smtp.gmail.com" /><${Inp} label="Porta" value=${ig.smtp.port} onInput=${(v) => intg('smtp', 'port', v)} placeholder="587" />
        <${Inp} label="Usuário" value=${ig.smtp.user} onInput=${(v) => intg('smtp', 'user', v)} /><${Inp} label="Senha" type="password" value=${ig.smtp.pass} onInput=${(v) => intg('smtp', 'pass', v)} />
        <${Inp} label="Remetente" value=${ig.smtp.from} onInput=${(v) => intg('smtp', 'from', v)} placeholder="Imob Easy <vistorias@imobeasy.com>" /><${Sel} label="Conexão segura (SSL, porta 465)" value=${String(ig.smtp.secure || 'false')} onChange=${(v) => intg('smtp', 'secure', v)} options=${[['false', 'Não (STARTTLS / 587)'], ['true', 'Sim (SSL / 465)']]} /></div>
        <div class="actions"><button class="btn ghost" onClick=${async () => { await save('integrations', { clicksign: ig.clicksign, smtp: ig.smtp, ai: ig.ai }); const r = await api('/admin/test-email', { body: {} }); toast(r.status === 'enviado' ? 'E-mail de teste enviado ✔' : `Falhou: ${r.error || r.status}`, r.status === 'enviado' ? 'ok' : 'err'); }}>Salvar e enviar teste</button></div>
      </${Card}>
      <${Card} title="Inteligência artificial (leitura de contrato)" icon="sparkles" right=${html`<span class=${'pill ' + (ig.ai.enabled ? 'green' : 'gray')}>${ig.ai.enabled ? 'Claude ativo' : 'Extrator local'}</span>`}>
        <p class="muted small">Sem chave, o sistema usa um extrator local que funciona bem em contratos de locação digitais. Com a chave da Anthropic (Claude), a IA lê qualquer contrato — inclusive escaneado — e gera descrições a partir das fotos.</p>
        <div class="grid2"><${Inp} label="Chave da API (Anthropic)" value=${ig.ai.key} onInput=${(v) => intg('ai', 'key', v)} placeholder=${ig.ai.env_key ? 'Definida no .env' : 'sk-ant-…'} /><${Inp} label="Modelo" value=${ig.ai.model} onInput=${(v) => intg('ai', 'model', v)} /></div>
      </${Card}>
      <div class="actions"><span class=${'pill ' + (d.chrome ? 'green' : 'red')}>${d.chrome ? 'Gerador de PDF pronto' : 'Chromium não encontrado — PDF indisponível'}</span><span class="sp"></span><button class="btn primary" onClick=${() => save('integrations', { clicksign: ig.clicksign, smtp: ig.smtp, ai: ig.ai })}>Salvar integrações</button></div>`}
    ${tab === 'app' && html`<${Card} title="App do vistoriador" icon="camera">
      <${Switch} on=${pr.app_can_add_vocab} onChange=${(v) => upd('params', 'app_can_add_vocab', v)} label="Cômodos e itens criados no app entram na lista permanente" sub="Ex.: o vistoriador cria “Varanda gourmet” e ela passa a aparecer na adição rápida." />
      <div class="grid2"><${Inp} label="Limite de fotos por cômodo" type="number" value=${pr.photos_per_room} onInput=${(v) => upd('params', 'photos_per_room', Number(v))} /><${Inp} label="Fuso horário das datas do laudo" value=${pr.timezone || 'America/Sao_Paulo'} onInput=${(v) => upd('params', 'timezone', v)} hint="Ex.: America/Manaus, America/Sao_Paulo" /></div>
      <div class="actions"><button class="btn primary" onClick=${() => save('params')}>Salvar</button></div></${Card}>`}
  </div>`;
}

function CrudTable({ title, icon, sub, endpoint, cols, fields, toRow, fromRow, empty }) {
  const [list, reload] = useLoad(() => api(endpoint));
  const [q, setQ] = useState('');
  function edit(x = {}) {
    let f = fromRow ? fromRow(x) : { ...x };
    const F = () => { const [s, set] = useState(f); f = s; return html`<div class="grid2">${fields.map(([k, l, type, opts]) => (type === 'select' ? html`<${Sel} label=${l} value=${s[k]} onChange=${(v) => set({ ...s, [k]: v })} options=${opts} />` : html`<${Inp} label=${l} type=${type || 'text'} value=${s[k]} onInput=${(v) => set({ ...s, [k]: v })} />`))}</div>`; };
    modal(html`<${Modal} title=${x.id ? 'Editar' : 'Novo cadastro'} onClose=${closeModal} footer=${html`${x.id && html`<button class="btn ghost danger-t" onClick=${async () => { if (await confirmBox({ title: 'Excluir?', danger: true, ok: 'Excluir' })) { await api(`${endpoint}/${x.id}`, { method: 'DELETE' }); reload(); } }}>Excluir</button>`}<span class="sp"></span><button class="btn ghost" onClick=${closeModal}>Cancelar</button><button class="btn primary" onClick=${async () => { try { await api(endpoint, { body: toRow ? toRow(f) : f }); closeModal(); reload(); toast('Salvo'); } catch (e) { toast(e.message, 'err'); } }}>Salvar</button>`}><${F} /></${Modal}>`);
  }
  const shown = (list || []).filter((x) => !q || JSON.stringify(x).toLowerCase().includes(q.toLowerCase()));
  return html`<div class="pg"><${PageHead} title=${title} icon=${icon} sub=${sub} right=${html`<button class="btn primary" onClick=${() => edit()}><${Icon} name="plus" size=${18} /> Novo</button>`} />
    <div class="acard filters"><div class="search-a"><${Icon} name="search" size=${18} /><input placeholder="Digite aqui para pesquisar…" value=${q} onInput=${(e) => setQ(e.target.value)} /></div></div>
    ${!list ? html`<${Loading} />` : shown.length ? html`<div class="acard"><table class="atable hover"><thead><tr>${cols.map(([, l]) => html`<th>${l}</th>`)}</tr></thead><tbody>${shown.map((x) => html`<tr onClick=${() => edit(x)}>${cols.map(([k, , fn]) => html`<td>${fn ? fn(x) : x[k] || '—'}</td>`)}</tr>`)}</tbody></table></div>` : html`<${Empty} text=${empty || 'Nenhum cadastro'} />`}</div>`;
}
export const People = () => html`<${CrudTable} title="Pessoas" icon="users" endpoint="/admin/people" cols=${[['name', 'Nome'], ['cpf', 'CPF / CNPJ'], ['email', 'E-mail'], ['phone', 'Telefone'], ['kind', 'Tipo']]}
  fields=${[['name', 'Nome'], ['cpf', 'CPF / CNPJ'], ['rg', 'RG'], ['email', 'E-mail', 'email'], ['phone', 'Telefone'], ['kind', 'Tipo', 'select', [['', '—'], ['locador', 'Locador'], ['locatario', 'Locatário'], ['fiador', 'Fiador'], ['corretor', 'Corretor'], ['outro', 'Outro']]]]} />`;
export const Properties = () => html`<${CrudTable} title="Imóveis" icon="building" endpoint="/admin/properties" cols=${[['identification', 'Identificação'], ['addr', 'Endereço', (x) => [x.data.street, x.data.number, x.data.district, x.data.city].filter(Boolean).join(', ') || '—'], ['type', 'Tipo', (x) => x.data.type || '—']]}
  fromRow=${(x) => ({ id: x.id, identification: x.identification, ...(x.data || {}) })} toRow=${(f) => { const { id, identification, ...data } = f; return { id, identification, data }; }}
  fields=${[['identification', 'Identificação'], ['type', 'Tipo', 'select', [['', '—'], 'Apartamento', 'Casa', 'Sobrado', 'Kitnet/Studio', 'Sala Comercial', 'Galpão', 'Terreno']], ['cep', 'CEP'], ['street', 'Endereço'], ['number', 'Número'], ['complement', 'Complemento'], ['district', 'Bairro'], ['city', 'Cidade'], ['state', 'UF'], ['area', 'Metragem (m²)'], ['iptu', 'Inscrição IPTU']]} />`;
export const Users = () => html`<${CrudTable} title="Usuários e vistoriadores" icon="shield" sub="Vistoriadores entram no app (/app). Administradores entram no painel." endpoint="/admin/users" cols=${[['name', 'Nome'], ['email', 'E-mail'], ['role', 'Perfil', (x) => html`<span class=${'pill ' + (x.role === 'admin' ? 'purple' : 'blue')}>${x.role === 'admin' ? 'Administrador' : 'Vistoriador'}</span>`], ['active', 'Situação', (x) => (x.active ? 'Ativo' : 'Inativo')]]}
  fromRow=${(x) => ({ ...x, password: '' })} fields=${[['name', 'Nome'], ['email', 'E-mail', 'email'], ['phone', 'Telefone'], ['role', 'Perfil', 'select', [['vistoriador', 'Vistoriador'], ['admin', 'Administrador']]], ['password', 'Senha (deixe em branco para manter)', 'password']]} />`;

export function Vocab() {
  const [list, reload] = useLoad(() => api('/vocab'));
  const [n, setN] = useState(''); const [k, setK] = useState('room');
  const col = (kind, title) => html`<${Card} title=${title} icon=${kind === 'room' ? 'door' : 'box'}><div class="vocab">${(list || []).filter((x) => x.kind === kind).map((x) => html`<span class="vchip">${x.name}<small>${x.uses}×</small><button onClick=${async () => { await api(`/vocab/${x.id}`, { method: 'DELETE' }); reload(); }}><${Icon} name="x" size=${12} /></button></span>`)}</div></${Card}>`;
  return html`<div class="pg"><${PageHead} title="Cômodos e itens personalizados" icon="list" sub="Nomes criados pelos vistoriadores no app ficam salvos aqui e aparecem na adição rápida de todos." />
    <div class="acard filters"><${Sel} value=${k} onChange=${setK} options=${[['room', 'Cômodo'], ['item', 'Item / móvel']]} /><div class="search-a"><input placeholder="Novo nome…" value=${n} onInput=${(e) => setN(e.target.value)} /></div><button class="btn primary" onClick=${async () => { if (!n.trim()) return; await api('/vocab', { body: { kind: k, name: n.trim() } }); setN(''); reload(); }}>Adicionar</button></div>
    ${!list ? html`<${Loading} />` : html`<div class="grid-dash">${col('room', 'Cômodos')}${col('item', 'Itens e móveis')}</div>`}</div>`;
}
