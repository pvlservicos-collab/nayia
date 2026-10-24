// Vistoria no painel: fluxo de aprovação em etapas
import { html, useState, useEffect, useRef } from '/shared/vendor/preact-htm.js';
import { api, toast, modal, closeModal, confirmBox, Modal, Card, Inp, Sel, Switch, Empty, Loading, Status, TYPES, CONDS, fmtDate, Photo, MarkerModal, Icon } from './ui.js';
import { nav } from './main.js';

const STAGES = [['Fotos e cômodos', 'camera'], ['Contrato (IA)', 'sparkles'], ['Dados do laudo', 'file'], ['Revisão do laudo', 'eye'], ['Aprovação', 'checkCircle'], ['Assinaturas', 'edit']];

export function InspectionPage({ id, tab }) {
  const [ins, setIns] = useState(null);
  const [v, setV] = useState(0);
  const reload = () => setV((x) => x + 1);
  useEffect(() => {
    api(`/admin/inspections/${id}`).then(async (d) => {
      if (d.status === 'enviada') { await api(`/admin/inspections/${id}`, { method: 'PATCH', body: { status: 'em_revisao' } }); d.status = 'em_revisao'; }
      setIns(d);
    }).catch((e) => toast(e.message, 'err'));
  }, [id, v]);
  if (!ins) return html`<${Loading} />`;
  const stage = tab ? Math.max(1, Math.min(6, +tab)) : Math.min(6, ins.status === 'em_assinatura' || ins.status === 'assinada' ? 6 : ins.status === 'aprovada' ? 5 : ins.review_stage || 1);
  const goStage = (n) => { nav(`/vistorias/${id}/${n}`); if (n > (ins.review_stage || 1) && !['aprovada', 'em_assinatura', 'assinada'].includes(ins.status)) api(`/admin/inspections/${id}`, { method: 'PATCH', body: { review_stage: n } }); };
  const p = ins.property || {};
  const locked = ['aprovada', 'em_assinatura', 'assinada'].includes(ins.status);
  const Body = [RoomsStage, ContractStage, DataStage, ReviewStage, ApproveStage, SignStage][stage - 1];
  return html`<div class="pg ins-pg">
    <a class="back-l" href="#/aprovacoes"><${Icon} name="arrowLeft" size=${16} /> Fluxo de aprovação</a>
    <div class="ins-head acard">
      <div class="ih-main"><div class="ih-code">#${ins.code}</div><div><h1>${p.identification || 'Imóvel sem identificação'}</h1><p>${[p.street, p.number, p.complement, p.district, p.city, p.state].filter(Boolean).join(', ') || 'Endereço não informado'}</p>
        <div class="ih-tags"><${Status} s=${ins.status} /><span class="pill gray">${ins.typeLabel}</span><span class="mini"><${Icon} name="user" size=${14} />${ins.inspector ? ins.inspector.name : '—'}</span><span class="mini"><${Icon} name="calendar" size=${14} />${fmtDate(ins.inspected_at || ins.created_at)}</span><span class="mini"><${Icon} name="camera" size=${14} />${ins.stats.photos} fotos</span><span class="mini red"><${Icon} name="alert" size=${14} />${ins.stats.ncs} avarias</span></div></div></div>
      <div class="ih-act">
        ${ins.public_url && html`<a class="btn ghost" href=${ins.public_url} target="_blank"><${Icon} name="link" size=${16} /> Link público</a>`}
        ${locked && ins.status !== 'assinada' && html`<button class="btn ghost" onClick=${async () => { if (await confirmBox({ title: 'Reabrir para edição?', text: 'O laudo volta para revisão. Se já estiver em assinatura, será necessário reenviar.', ok: 'Reabrir' })) { await api(`/admin/inspections/${id}/reopen`, { body: {} }); nav(`/vistorias/${id}/4`); reload(); } }}><${Icon} name="edit" size=${16} /> Reabrir</button>`}
        ${ins.type === 'entrada' && locked && html`<button class="btn ghost" onClick=${async () => { const r = await api(`/admin/inspections/${id}/clone-exit`, { body: {} }); toast('Vistoria de saída criada com os mesmos cômodos e itens'); nav(`/vistorias/${r.id}`); }}><${Icon} name="logout" size=${16} /> Gerar vistoria de saída</button>`}
        <button class="ib" title="Excluir vistoria" onClick=${async () => { if (await confirmBox({ title: 'Excluir esta vistoria?', text: 'Fotos, áudios e o laudo serão apagados definitivamente.', ok: 'Excluir', danger: true })) { await api(`/admin/inspections/${id}`, { method: 'DELETE' }); nav('/vistorias'); } }}><${Icon} name="trash" size=${18} /></button>
      </div>
    </div>
    <div class="stages">${STAGES.map(([l, ic], i) => { const n = i + 1; const done = n < stage || (n <= 5 && locked && n !== stage) || (n === 6 && ins.status === 'assinada'); return html`<button class=${'stg' + (n === stage ? ' cur' : '') + (done ? ' done' : '')} onClick=${() => goStage(n)}><span>${done ? html`<${Icon} name="check" size=${15} stroke=${3} />` : html`<${Icon} name=${ic} size=${15} />`}</span><div><small>Etapa ${n}</small><b>${l}</b></div></button>`; })}</div>
    <div class="ins-grid">
      <div class="ins-main" key=${stage}>${locked && stage <= 3 ? html`<div class="lock-note"><${Icon} name="shield" size=${16} /> Laudo aprovado — edições aparecem no link público imediatamente. Para reenviar à assinatura, use “Reabrir”.</div>` : ''}<${Body} ins=${ins} reload=${reload} goStage=${goStage} /></div>
      <aside class="ins-aside">
        <${Card} title="Completude do laudo" icon="checkCircle"><div class="score-a"><div class="ring-a" style=${`--p:${ins.completeness.score}`}><b>${ins.completeness.score}%</b></div><p class="muted small">Para ficar igual ao modelo de laudo, complete os itens abaixo.</p></div>
          <div class="cklist">${ins.completeness.checks.map((c) => html`<div class=${'ck-a' + (c.ok ? ' ok' : '')}><${Icon} name=${c.ok ? 'checkCircle' : 'alert'} size=${15} />${c.label}</div>`)}</div></${Card}>
        <${Card} title="Histórico" icon="sync"><div class="tl-a">${(ins.events || []).map((e) => html`<div class="tl-i"><span class=${'fd ' + e.kind}></span><div><b>${e.message}</b><small>${fmtDate(e.created_at)}${e.user_name ? ` · ${e.user_name}` : ''}</small></div></div>`)}</div></${Card}>
      </aside>
    </div>
  </div>`;
}

// ---------------- Etapa 1: fotos e cômodos ----------------
async function upload(ins, files, extra) {
  for (const f of files) {
    const fd = new FormData();
    fd.append('file', f); fd.append('inspection_id', ins.id);
    for (const [k, v] of Object.entries(extra)) if (v) fd.append(k, v);
    fd.append('taken_at', new Date(f.lastModified || Date.now()).toISOString());
    fd.append('kind', f.type.startsWith('video') ? 'video' : f.type.startsWith('audio') ? 'audio' : 'photo');
    await api('/media', { body: fd });
  }
}
function UploadBtn({ ins, extra, reload, label = 'Enviar fotos' }) {
  const ref = useRef(null); const [busy, setBusy] = useState(false);
  return html`<button class="btn ghost sm" disabled=${busy} onClick=${() => ref.current.click()}>${busy ? html`<span class="spin sm"></span>` : html`<${Icon} name="cameraPlus" size=${15} />`} ${label}<input ref=${ref} type="file" multiple accept="image/*,video/*" hidden onChange=${async (e) => { setBusy(true); try { await upload(ins, [...e.target.files], extra); toast('Arquivos enviados'); reload(); } catch (er) { toast(er.message, 'err'); } setBusy(false); }} /></button>`;
}
function openPhoto(m, reload, extraActions) {
  modal(html`<${Modal} width=${980} title=${`Mídia · ${fmtDate(m.taken_at)}`} onClose=${closeModal} footer=${html`
    ${m.kind === 'photo' && html`<button class="btn danger-soft" onClick=${() => modal(html`<${MarkerModal} m=${m} onSaved=${reload} />`)}><${Icon} name="target" size=${16} /> Destacar avarias (bolinhas)</button>`}
    ${extraActions}<span class="sp"></span>
    <a class="btn ghost" href=${m.url} target="_blank" download><${Icon} name="file" size=${16} /> Baixar</a>
    <button class="btn ghost danger-t" onClick=${async () => { if (await confirmBox({ title: 'Excluir mídia?', ok: 'Excluir', danger: true })) { await api(`/media/${m.id}`, { method: 'DELETE' }); reload(); } }}><${Icon} name="trash" size=${16} /> Excluir</button>`}>
    <div class="pv-big">${m.kind === 'video' ? html`<video src=${m.url} controls autoplay></video>` : m.kind === 'audio' ? html`<div><audio src=${m.url} controls autoplay></audio>${m.transcript && html`<p class="tr-a">“${m.transcript}”</p>`}</div>` : html`<div class="mk-img"><img src=${m.url} />${(m.markers || []).map((k, i) => html`<span class="amk big" style=${`left:${k.x * 100}%;top:${k.y * 100}%;width:${(k.r || 0.07) * 200}%`}><b>${i + 1}</b></span>`)}</div>`}</div>
  </${Modal}>`);
}
function Gallery({ list, reload, selectable, sel, setSel }) {
  const vis = list.filter((m) => m.kind !== 'audio');
  const aud = list.filter((m) => m.kind === 'audio');
  return html`${vis.length ? html`<div class="agal">${vis.map((m) => html`<${Photo} key=${m.id} m=${m} onClick=${() => openPhoto(m, reload)} selected=${sel && sel.includes(m.id)} onSelect=${selectable ? () => setSel(sel.includes(m.id) ? sel.filter((x) => x !== m.id) : [...sel, m.id]) : null} />`)}</div>` : ''}
    ${aud.map((m) => html`<div class="aud-row"><${Icon} name="mic" size=${16} /><audio src=${m.url} controls preload="none"></audio><span>${m.transcript ? `“${m.transcript}”` : ''}</span></div>`)}`;
}
function RoomsStage({ ins, reload, goStage }) {
  const [rid, setRid] = useState(ins.rooms[0] && ins.rooms[0].id);
  const room = ins.rooms.find((r) => r.id === rid) || ins.rooms[0];
  const [sel, setSel] = useState([]);
  useEffect(() => setSel([]), [rid]);
  async function addRoom() { const r = await api(`/admin/inspections/${ins.id}/rooms`, { body: { name: 'Novo cômodo' } }); setRid(r.id); reload(); }
  async function move(i, d) { const ids = ins.rooms.map((r) => r.id); const j = i + d; if (j < 0 || j >= ids.length) return; [ids[i], ids[j]] = [ids[j], ids[i]]; await api('/admin/rooms/reorder', { body: { ids } }); reload(); }
  async function ncFromSel(itemId) {
    const r = await api('/admin/ncs', { body: { room_id: room.id, item_id: itemId || null, title: 'Avaria', media_ids: sel } });
    setSel([]); toast('Avaria criada — descreva e marque as bolinhas'); reload();
  }
  if (!ins.rooms.length) return html`<${Card}><${Empty} icon="door" text="Nenhum cômodo nesta vistoria." action=${html`<button class="btn primary" onClick=${addRoom}>Adicionar cômodo</button>`} /></${Card}>`;
  return html`<div class="rooms-ed">
    <div class="re-list acard"><div class="re-h"><b>Cômodos</b><span class="count">${ins.rooms.length}</span></div>
      ${ins.rooms.map((r, i) => { const ph = r.media.length + r.items.reduce((a, it) => a + it.media.length + it.ncs.reduce((b, n) => b + n.media.length, 0), 0); const nc = r.ncs.length + r.items.reduce((a, it) => a + it.ncs.length, 0);
        return html`<button class=${'re-i' + (room && room.id === r.id ? ' on' : '')} onClick=${() => setRid(r.id)}><span class="re-n">${i + 1}</span><div><b>${r.name}</b><small>${ph} fotos · ${r.items.length} itens${nc ? html` · <em class="red">${nc} avarias</em>` : ''}</small></div>
          <span class="re-mv"><i onClick=${(e) => { e.stopPropagation(); move(i, -1); }}><${Icon} name="up" size=${14} /></i><i onClick=${(e) => { e.stopPropagation(); move(i, 1); }}><${Icon} name="down" size=${14} /></i></span></button>`; })}
      <button class="btn ghost sm full" onClick=${addRoom}><${Icon} name="plus" size=${15} /> Adicionar cômodo</button>
      <button class="btn primary sm full" onClick=${() => goStage(2)}>Próxima etapa: Contrato →</button></div>
    ${room && html`<div class="re-body" key=${room.id}>
      <${Card}><div class="room-h"><input class="title-in" value=${room.name} onChange=${async (e) => { await api(`/admin/rooms/${room.id}`, { method: 'PATCH', body: { name: e.target.value } }); reload(); }} />
        <button class="ib" title="Excluir cômodo" onClick=${async () => { if (await confirmBox({ title: `Excluir ${room.name}?`, text: 'Itens, avarias e fotos deste cômodo serão removidos.', ok: 'Excluir', danger: true })) { await api(`/admin/rooms/${room.id}`, { method: 'DELETE' }); setRid(null); reload(); } }}><${Icon} name="trash" size=${18} /></button></div>
        <${Inp} area rows=${2} label="Observações do cômodo" value=${room.notes} onInput=${() => {}} onChange=${async (e) => { await api(`/admin/rooms/${room.id}`, { method: 'PATCH', body: { notes: e.target.value } }); toast('Observação salva'); }} />
      </${Card}>
      <${Card} title=${`Fotos do cômodo (${room.media.length})`} icon="camera" right=${html`<${UploadBtn} ins=${ins} extra=${{ room_id: room.id, scope: 'room' }} reload=${reload} />`}>
        ${sel.length ? html`<div class="sel-bar"><b>${sel.length} selecionada(s)</b><button class="btn danger-soft sm" onClick=${() => ncFromSel(null)}><${Icon} name="alert" size=${15} /> Criar avaria no cômodo</button>
          <select onChange=${(e) => e.target.value && ncFromSel(e.target.value)}><option value="">Criar avaria em um item…</option>${room.items.map((it) => html`<option value=${it.id}>${it.name}</option>`)}</select>
          <select onChange=${async (e) => { if (!e.target.value) return; for (const mid of sel) await api(`/media/${mid}`, { method: 'PATCH', body: { item_id: e.target.value, scope: 'item' } }); setSel([]); reload(); toast('Fotos movidas para o item'); }}><option value="">Mover para item…</option>${room.items.map((it) => html`<option value=${it.id}>${it.name}</option>`)}</select>
          <button class="btn ghost sm" onClick=${() => setSel([])}>Limpar</button></div>` : html`<p class="muted small">Dica: selecione fotos (✓) para criar uma avaria ou movê-las para um item. Clique na foto para marcar bolinhas.</p>`}
        ${room.media.length ? html`<${Gallery} list=${room.media} reload=${reload} selectable sel=${sel} setSel=${setSel} />` : html`<${Empty} icon="camera" text="Sem fotos neste cômodo" />`}
      </${Card}>
      ${room.ncs.length ? html`<${Card} title="Avarias do cômodo" icon="alert">${room.ncs.map((n) => html`<${NcEditor} key=${n.id} n=${n} ins=${ins} room=${room} reload=${reload} />`)}</${Card}>` : ''}
      <${Card} title=${`Itens e móveis (${room.items.length})`} icon="box" right=${html`<button class="btn ghost sm" onClick=${async () => { await api(`/admin/rooms/${room.id}/items`, { body: { name: 'Novo item' } }); reload(); }}><${Icon} name="plus" size=${15} /> Item</button>`}>
        ${room.items.length ? room.items.map((it, i) => html`<${ItemEditor} key=${it.id} it=${it} idx=${i} ins=${ins} room=${room} reload=${reload} />`) : html`<${Empty} icon="box" text="Nenhum item cadastrado neste cômodo" />`}
      </${Card}>
    </div>`}
  </div>`;
}
function ItemEditor({ it, idx, ins, room, reload }) {
  const [busy, setBusy] = useState(false);
  const patch = async (b) => { await api(`/admin/items/${it.id}`, { method: 'PATCH', body: b }); reload(); };
  const isSaida = ins.type === 'saida' && it.source;
  return html`<div class=${'it-ed' + (it.ncs.length ? ' nc' : '')}>
    <div class="it-top"><span class="it-n">${ins.rooms.indexOf(room) + 1}.${idx + 1}</span><input class="it-name" value=${it.name} onChange=${(e) => patch({ name: e.target.value })} />
      <div class="cond-seg">${Object.entries(CONDS).map(([k, [l, c]]) => html`<button class=${it.condition === k ? 'on' : ''} style=${`--c:${c}`} onClick=${() => patch({ condition: it.condition === k ? null : k })}><i></i>${l}</button>`)}</div>
      <button class="ib" onClick=${async () => { if (await confirmBox({ title: `Excluir ${it.name}?`, ok: 'Excluir', danger: true })) { await api(`/admin/items/${it.id}`, { method: 'DELETE' }); reload(); } }}><${Icon} name="trash" size=${16} /></button></div>
    ${isSaida && html`<div class="was-a">Na entrada: <b>${(CONDS[it.source.condition] || ['—'])[0]}</b></div>`}
    <div class="it-row"><${Sel} label="Funcionamento" value=${it.functioning || ''} onChange=${(v) => patch({ functioning: v || null })} options=${[['', 'Não se aplica'], ['funcionando', 'Funcionando'], ['nao_funcionando', 'Não funcionando'], ['nao_testado', 'Não testado']]} /><${Inp} label="Quantidade" type="number" value=${it.quantity || ''} onInput=${() => {}} onChange=${(e) => patch({ quantity: e.target.value ? +e.target.value : null })} />
      <${Inp} cls="grow" area rows=${2} label="Descrição / observações" value=${it.notes} onInput=${() => {}} onChange=${(e) => patch({ notes: e.target.value })} /></div>
    <div class="it-media"><${Gallery} list=${it.media} reload=${reload} /><div class="it-btns"><${UploadBtn} ins=${ins} extra=${{ room_id: room.id, item_id: it.id, scope: 'item' }} reload=${reload} label="Fotos do item" />
      ${it.media.some((m) => m.kind === 'photo') && html`<button class="btn ghost sm" disabled=${busy} onClick=${async () => { setBusy(true); try { const r = await api('/ai/describe', { body: { media_ids: it.media.filter((m) => m.kind === 'photo').map((m) => m.id), context: `${it.name} (${room.name})` } }); await patch({ notes: r.text }); toast('Descrição gerada pela IA'); } catch (e) { toast(e.message, 'err'); } setBusy(false); }}>${busy ? html`<span class="spin sm"></span>` : html`<${Icon} name="sparkles" size=${15} />`} Descrever com IA</button>`}
      <button class="btn danger-soft sm" onClick=${async () => { await api('/admin/ncs', { body: { room_id: room.id, item_id: it.id, title: 'Avaria' } }); reload(); }}><${Icon} name="plus" size=${15} /> Inconformidade</button></div></div>
    ${it.ncs.map((n) => html`<${NcEditor} key=${n.id} n=${n} ins=${ins} room=${room} item=${it} reload=${reload} />`)}
  </div>`;
}
function NcEditor({ n, ins, room, item, reload }) {
  const patch = (b) => api(`/admin/ncs/${n.id}`, { method: 'PATCH', body: b }).then(() => toast('Avaria salva'));
  return html`<div class="nc-ed"><div class="nc-ed-h"><span class="dot-r"></span><input value=${n.title} onChange=${(e) => patch({ title: e.target.value }).then(reload)} placeholder="Título da avaria" /><button class="ib" onClick=${async () => { await api(`/admin/ncs/${n.id}`, { method: 'DELETE' }); reload(); }}><${Icon} name="trash" size=${15} /></button></div>
    <textarea rows="2" placeholder="Descrição da avaria" value=${n.description || ''} onChange=${(e) => patch({ description: e.target.value })}></textarea>
    <${Gallery} list=${n.media} reload=${reload} /><${UploadBtn} ins=${ins} extra=${{ room_id: room.id, item_id: item ? item.id : '', nc_id: n.id, scope: 'nc' }} reload=${reload} label="Fotos da avaria" /></div>`;
}

// ---------------- Etapa 2: contrato ----------------
const PF = [['identification', 'Identificação'], ['type', 'Tipo'], ['purpose', 'Finalidade'], ['street', 'Logradouro'], ['number', 'Número'], ['complement', 'Complemento'], ['district', 'Bairro'], ['city', 'Cidade'], ['state', 'UF'], ['cep', 'CEP'], ['iptu', 'IPTU'], ['area', 'Metragem'], ['furnished', 'Mobília']];
const CF = [['rent', 'Aluguel'], ['due_day', 'Vencimento (dia)'], ['start', 'Início'], ['end', 'Término'], ['months', 'Prazo (meses)'], ['deposit', 'Caução'], ['guarantee', 'Garantia'], ['readjust_index', 'Índice de reajuste']];
const PPL = [['locadores', 'Locador(es)'], ['locatarios', 'Locatário(s)'], ['fiadores', 'Fiador(es)']];
function ContractStage({ ins, reload, goStage }) {
  const [busy, setBusy] = useState(false);
  const [res, setRes] = useState(ins.contract && ins.contract.extracted ? { data: ins.contract.extracted, engine: ins.contract.engine } : null);
  const [pick, setPick] = useState({});
  const ref = useRef(null);
  const ppl = (arr) => (arr || []).filter((x) => x && x.name).map((x) => `${x.name}${x.cpf ? ` (${x.cpf})` : ''}${x.email ? ` · ${x.email}` : ''}`).join('\n');
  useEffect(() => {
    if (!res) return;
    const d = res.data, p = ins.property || {}, pa = ins.parties || {}, c = ins.contract || {};
    const s = {};
    PF.forEach(([k]) => { if (d.property && d.property[k] && d.property[k] !== p[k]) s['p.' + k] = !p[k]; });
    PPL.forEach(([k]) => { if (d.parties && (d.parties[k] || []).length && ppl(d.parties[k]) !== ppl(pa[k])) s['pa.' + k] = !(pa[k] || []).some((x) => x.name); });
    CF.forEach(([k]) => { if (d.contract && d.contract[k] && d.contract[k] !== c[k]) s['c.' + k] = true; });
    setPick(s);
  }, [res]);
  async function send(file) {
    setBusy(true);
    try { const fd = new FormData(); fd.append('file', file); fd.append('inspection_id', ins.id); const r = await api('/ai/contract', { body: fd }); setRes(r); reload(); toast(r.warning || `Contrato lido (${r.engine === 'claude' ? 'IA Claude' : 'extrator local'})`, r.warning ? 'err' : 'ok'); } catch (e) { toast(e.message, 'err'); }
    setBusy(false);
  }
  async function apply() {
    const d = res.data; const body = { property: {}, parties: {}, contract: {} };
    for (const [k, on] of Object.entries(pick)) { if (!on) continue; const [sec, f] = k.split('.'); if (sec === 'p') body.property[f] = d.property[f]; if (sec === 'pa') body.parties[f] = d.parties[f]; if (sec === 'c') body.contract[f] = d.contract[f]; }
    await api(`/admin/inspections/${ins.id}/apply-contract`, { body });
    toast('Dados aplicados ao laudo'); reload(); goStage(3);
  }
  const rows = [];
  if (res) {
    const d = res.data, p = ins.property || {}, pa = ins.parties || {}, c = ins.contract || {};
    PF.forEach(([k, l]) => d.property && d.property[k] && rows.push(['p.' + k, 'Imóvel', l, p[k], d.property[k]]));
    PPL.forEach(([k, l]) => d.parties && (d.parties[k] || []).length && rows.push(['pa.' + k, 'Partes', l, ppl(pa[k]), ppl(d.parties[k])]));
    CF.forEach(([k, l]) => d.contract && d.contract[k] && rows.push(['c.' + k, 'Contrato', l, c[k], d.contract[k]]));
  }
  return html`<${Card} title="Contrato e leitura por IA" icon="sparkles">
      <p class="muted">Anexe o contrato (PDF). A IA lê o documento, extrai os dados do imóvel, das partes e do contrato e você escolhe o que aplicar no laudo.</p>
      <div class=${'drop' + (busy ? ' busy' : '')} onClick=${() => !busy && ref.current.click()} onDragOver=${(e) => e.preventDefault()} onDrop=${(e) => { e.preventDefault(); const f = e.dataTransfer.files[0]; if (f) send(f); }}>
        ${busy ? html`<span class="spin"></span><b>A IA está lendo o contrato…</b>` : html`<${Icon} name="file" size=${34} stroke=${1.6} /><b>${ins.contract && ins.contract.filename ? `Contrato atual: ${ins.contract.filename}` : 'Arraste o PDF do contrato aqui'}</b><small>ou clique para selecionar · ${ins.contract && ins.contract.filename ? 'enviar outro arquivo substitui a leitura' : 'PDF até 50 MB'}</small>`}
        <input ref=${ref} type="file" accept="application/pdf" hidden onChange=${(e) => e.target.files[0] && send(e.target.files[0])} /></div>
      ${ins.contract && ins.contract.file_url && html`<a class="lnk" href=${ins.contract.file_url} target="_blank"><${Icon} name="file" size=${15} /> Abrir contrato anexado</a>`}
    </${Card}>
    ${res && html`<${Card} title="Dados extraídos" icon="list" right=${html`<span class="pill purple">${res.engine === 'claude' ? 'IA Claude' : 'Extrator local'}</span>`} pad=${false}>
      ${rows.length ? html`<table class="atable cmp"><thead><tr><th></th><th>Grupo</th><th>Campo</th><th>No laudo</th><th>Extraído do contrato</th></tr></thead><tbody>${rows.map(([k, g, l, cur, nw]) => html`<tr class=${pick[k] ? 'pk' : ''}><td><input type="checkbox" checked=${!!pick[k]} onChange=${() => setPick({ ...pick, [k]: !pick[k] })} /></td><td class="small muted">${g}</td><td><b>${l}</b></td><td class="pre muted">${cur || '—'}</td><td class="pre"><b>${nw}</b></td></tr>`)}</tbody></table>
      <div class="actions pad"><span class="muted small">${Object.values(pick).filter(Boolean).length} campo(s) selecionado(s)</span><span class="sp"></span><button class="btn ghost" onClick=${() => goStage(3)}>Pular</button><button class="btn primary" onClick=${apply}><${Icon} name="check" size=${16} /> Aplicar selecionados</button></div>` : html`<${Empty} text="Nenhum dado identificado no contrato." />`}
    </${Card}>`}
    ${!res && html`<div class="actions"><span class="sp"></span><button class="btn ghost" onClick=${() => goStage(3)}>Continuar sem contrato →</button></div>`}`;
}

// ---------------- Etapa 3: dados ----------------
function PersonList({ list, onChange, label }) {
  return html`<div class="pl"><div class="pl-h"><b>${label}</b><button class="btn ghost sm" onClick=${() => onChange([...(list || []), {}])}><${Icon} name="plus" size=${14} /> Adicionar</button></div>
    ${(list || []).map((p, i) => html`<div class="pl-r"><input placeholder="Nome" value=${p.name || ''} onInput=${(e) => { const l = [...list]; l[i] = { ...p, name: e.target.value }; onChange(l); }} /><input placeholder="CPF" value=${p.cpf || ''} onInput=${(e) => { const l = [...list]; l[i] = { ...p, cpf: e.target.value }; onChange(l); }} /><input placeholder="E-mail" value=${p.email || ''} onInput=${(e) => { const l = [...list]; l[i] = { ...p, email: e.target.value }; onChange(l); }} /><input placeholder="Telefone" value=${p.phone || ''} onInput=${(e) => { const l = [...list]; l[i] = { ...p, phone: e.target.value }; onChange(l); }} /><button class="ib" onClick=${() => onChange(list.filter((_, j) => j !== i))}><${Icon} name="x" size=${15} /></button></div>`)}
    ${!(list || []).length ? html`<small class="muted">Nenhum cadastrado</small>` : ''}</div>`;
}
function DataStage({ ins, reload, goStage }) {
  const [p, setP] = useState(ins.property || {});
  const [pa, setPa] = useState({ locadores: [], locatarios: [], fiadores: [], testemunhas: [], ...(ins.parties || {}) });
  const [mt, setMt] = useState(ins.meters || {});
  const [gn, setGn] = useState(ins.general_notes || '');
  const [dt, setDt] = useState((ins.inspected_at || '').slice(0, 16));
  const [type, setType] = useState(ins.type);
  const u = (k) => (v) => setP({ ...p, [k]: v });
  async function save(next) {
    await api(`/admin/inspections/${ins.id}`, { method: 'PATCH', body: { property: p, parties: pa, meters: mt, general_notes: gn, type, inspected_at: dt ? new Date(dt).toISOString() : ins.inspected_at } });
    toast('Dados salvos'); if (next) goStage(4); else reload();
  }
  async function cep() { const c = (p.cep || '').replace(/\D/g, ''); try { const r = await fetch(`https://viacep.com.br/ws/${c}/json/`).then((x) => x.json()); if (r.erro) throw new Error(); setP({ ...p, street: r.logradouro || p.street, district: r.bairro || p.district, city: r.localidade || p.city, state: r.uf || p.state }); } catch { toast('CEP não encontrado', 'err'); } }
  const meterPhotos = (ins.media_general || []).filter((m) => m.scope === 'meter');
  return html`<${Card} title="Imóvel" icon="building"><div class="grid3">
      <${Inp} cls="span2" label="Identificação" value=${p.identification} onInput=${u('identification')} placeholder="PARADISE LAKE AP 202 TORRE MICHIGAN" /><${Sel} label="Modalidade" value=${type} onChange=${setType} options=${Object.entries(TYPES)} />
      <label class="af"><span>CEP</span><div class="copy-row"><input value=${p.cep || ''} onInput=${(e) => u('cep')(e.target.value)} /><button class="btn ghost sm" onClick=${cep}>Buscar</button></div></label>
      <${Inp} cls="span2" label="Logradouro" value=${p.street} onInput=${u('street')} /><${Inp} label="Número" value=${p.number} onInput=${u('number')} /><${Inp} label="Complemento" value=${p.complement} onInput=${u('complement')} /><${Inp} label="Bairro" value=${p.district} onInput=${u('district')} />
      <${Inp} label="Cidade" value=${p.city} onInput=${u('city')} /><${Inp} label="UF" value=${p.state} onInput=${u('state')} /><${Sel} label="Tipo" value=${p.type || ''} onChange=${u('type')} options=${['', 'Apartamento', 'Casa', 'Sobrado', 'Kitnet/Studio', 'Sala Comercial', 'Galpão', 'Terreno', 'Rancho', 'Outro']} />
      <${Sel} label="Finalidade" value=${p.purpose || ''} onChange=${u('purpose')} options=${['', 'Residencial', 'Comercial']} /><${Inp} label="Metragem (m²)" value=${p.area} onInput=${u('area')} /><${Sel} label="Mobília" value=${p.furnished || ''} onChange=${u('furnished')} options=${['', 'Mobiliado', 'Semimobiliado', 'Não mobiliado']} />
      <${Inp} label="Inscrição IPTU" value=${p.iptu} onInput=${u('iptu')} /><${Inp} label="Data da vistoria" type="datetime-local" value=${dt} onInput=${setDt} /><${Inp} label="Executado por" value=${pa.executed_by} onInput=${(v) => setPa({ ...pa, executed_by: v })} placeholder="Próprio Corretor/Imobiliária" /></div></${Card}>
    <${Card} title="Partes envolvidas" icon="users"><p class="muted small">Os e-mails informados recebem o link do laudo e o convite de assinatura da ClickSign.</p>
      ${[['locadores', 'Locador(es)'], ['locatarios', 'Locatário(s)'], ['fiadores', 'Fiador(es)'], ['testemunhas', 'Testemunha(s)']].map(([k, l]) => html`<${PersonList} label=${l} list=${pa[k]} onChange=${(v) => setPa({ ...pa, [k]: v })} />`)}</${Card}>
    <${Card} title="Leitura dos medidores" icon="bolt"><div class="grid3">${[['energia', 'Energia elétrica'], ['agua', 'Água'], ['gas', 'Gás']].map(([k, l]) => html`<div class="meter-a"><b>${l}</b><input placeholder="Nº / matrícula" value=${(mt[k] || {}).number || ''} onInput=${(e) => setMt({ ...mt, [k]: { ...(mt[k] || {}), number: e.target.value } })} /><input placeholder="Leitura" value=${(mt[k] || {}).reading || ''} onInput=${(e) => setMt({ ...mt, [k]: { ...(mt[k] || {}), reading: e.target.value } })} /></div>`)}</div>
      ${meterPhotos.length ? html`<${Gallery} list=${meterPhotos} reload=${reload} />` : ''}</${Card}>
    <${Card} title="Observações gerais" icon="file"><${Inp} area rows=${4} value=${gn} onInput=${setGn} placeholder="Ex.: Imóvel entregue limpo, com 2 controles e 3 chaves." /></${Card}>
    <div class="actions sticky"><span class="sp"></span><button class="btn ghost" onClick=${() => save(false)}>Salvar</button><button class="btn primary" onClick=${() => save(true)}>Salvar e revisar laudo →</button></div>`;
}

// ---------------- Etapa 4: revisão ----------------
function ReviewStage({ ins, goStage }) {
  const [url, setUrl] = useState(ins.public_token ? `/v/${ins.public_token}` : null);
  const [k, setK] = useState(0); const [busy, setBusy] = useState(false);
  useEffect(() => { if (!url) api(`/admin/inspections/${ins.id}/preview`, { body: {} }).then((r) => setUrl(r.url)); }, []);
  return html`<${Card} title="Pré-visualização do laudo" icon="eye" right=${html`<button class="btn ghost sm" onClick=${() => setK(k + 1)}><${Icon} name="sync" size=${15} /> Atualizar</button>
      <button class="btn ghost sm" disabled=${busy} onClick=${async () => { setBusy(true); try { const r = await api(`/admin/inspections/${ins.id}/pdf`, { body: {} }); window.open(r.url, '_blank'); } catch (e) { toast(e.message, 'err'); } setBusy(false); }}>${busy ? html`<span class="spin sm"></span>` : html`<${Icon} name="file" size=${15} />`} PDF prévia</button>
      ${url && html`<a class="btn ghost sm" href=${url} target="_blank"><${Icon} name="link" size=${15} /> Nova aba</a>`}`} pad=${false}>
      ${url ? html`<iframe key=${k} class="laudo-frame" src=${url}></iframe>` : html`<${Loading} />`}
    </${Card}>
    <div class="actions"><button class="btn ghost" onClick=${() => goStage(1)}>← Ajustar fotos e itens</button><button class="btn ghost" onClick=${() => goStage(3)}>Ajustar dados</button><span class="sp"></span><button class="btn primary" onClick=${() => goStage(5)}>Está pronto → Aprovar</button></div>`;
}

// ---------------- Etapa 5: aprovação ----------------
function ApproveStage({ ins, reload, goStage }) {
  const [send, setSend] = useState(true); const [busy, setBusy] = useState(false);
  const approved = ['aprovada', 'em_assinatura', 'assinada'].includes(ins.status);
  const kind = ins.type === 'saida' ? 'final' : 'initial';
  if (approved) return html`<${Card} title="Laudo aprovado" icon="checkCircle" cls="ok-card">
      <p>Aprovado em <b>${fmtDate(ins.approved_at)}</b>. O link público está ativo:</p>
      <div class="copy-row big"><input readonly value=${ins.public_url} /><button class="btn primary" onClick=${() => { navigator.clipboard.writeText(ins.public_url); toast('Link copiado'); }}><${Icon} name="copy" size=${16} /> Copiar</button><a class="btn ghost" href=${ins.public_url} target="_blank">Abrir</a></div>
      <div class="actions"><button class="btn ghost" onClick=${async () => { const r = await api(`/admin/inspections/${ins.id}/resend`, { body: { kind } }); toast(`E-mail reenviado para ${r.sent} pessoa(s)`); reload(); }}><${Icon} name="mail" size=${16} /> Reenviar e-mail de vistoria ${kind === 'final' ? 'final' : 'inicial'}</button><span class="sp"></span><button class="btn primary" onClick=${() => goStage(6)}>Ir para assinaturas →</button></div>
    </${Card}>`;
  return html`<${Card} title="Aprovar e publicar" icon="checkCircle">
      <div class="appr-sum"><div><b>${ins.stats.rooms}</b><small>cômodos</small></div><div><b>${ins.stats.items}</b><small>itens</small></div><div><b>${ins.stats.photos}</b><small>fotos</small></div><div class="r"><b>${ins.stats.ncs}</b><small>avarias</small></div><div class=${ins.completeness.score < 70 ? 'a' : 'g'}><b>${ins.completeness.score}%</b><small>completo</small></div></div>
      ${ins.completeness.score < 70 && html`<div class="warn-box"><${Icon} name="alert" size=${16} /> O laudo está ${ins.completeness.score}% completo. Você pode aprovar mesmo assim, mas confira os itens pendentes ao lado.</div>`}
      <p>Ao aprovar, o sistema gera o <b>link público compartilhável</b> do laudo e, se marcado, envia o <b>e-mail de vistoria ${kind === 'final' ? 'final' : 'inicial'}</b> para:</p>
      <div class="recips">${ins.recipients.length ? ins.recipients.map((r) => html`<span class="recip"><${Icon} name="mail" size=${14} />${r.name} <small>${r.email}</small></span>`) : html`<span class="muted">Nenhuma parte com e-mail — preencha em “Dados do laudo”.</span>`}</div>
      <${Switch} on=${send} onChange=${setSend} label=${`Enviar e-mail de vistoria ${kind === 'final' ? 'final' : 'inicial'}`} sub="O modelo do e-mail pode ser editado em Configurações → E-mails." />
      <div class="actions"><button class="btn ghost" onClick=${() => goStage(4)}>← Revisar laudo</button><span class="sp"></span><button class="btn primary lg" disabled=${busy} onClick=${async () => { setBusy(true); try { const r = await api(`/admin/inspections/${ins.id}/approve`, { body: { send_email: send } }); toast(`Laudo aprovado! ${r.emails} e-mail(s) enviados`); reload(); } catch (e) { toast(e.message, 'err'); } setBusy(false); }}>${busy ? html`<span class="spin sm light"></span>` : html`<${Icon} name="checkCircle" size=${18} />`} Aprovar e gerar link público</button></div>
    </${Card}>`;
}

// ---------------- Etapa 6: assinaturas ----------------
function SignStage({ ins, reload, goStage }) {
  const approved = ['aprovada', 'em_assinatura', 'assinada'].includes(ins.status);
  const [list, setList] = useState(ins.recipients.map((r) => ({ ...r })));
  const [busy, setBusy] = useState(false);
  const cs = ins.clicksign || {};
  if (!approved) return html`<${Card}><${Empty} icon="edit" text="Aprove o laudo antes de enviar para assinatura." action=${html`<button class="btn primary" onClick=${() => goStage(5)}>Ir para aprovação</button>`} /></${Card}>`;
  const ROLES = [['locatario', 'Locatário(a)'], ['locador', 'Locador(a)'], ['fiador', 'Fiador(a)'], ['testemunha', 'Testemunha'], ['imobiliaria', 'Imobiliária']];
  if (ins.status === 'aprovada') return html`<${Card} title="Enviar para assinatura" icon="edit" right=${html`<span class=${'pill ' + (ins.clicksign_enabled ? 'green' : 'amber')}>${ins.clicksign_enabled ? 'ClickSign conectada' : 'Modo simulação'}</span>`}>
      ${!ins.clicksign_enabled && html`<div class="warn-box"><${Icon} name="info" size=${16} /> Token da ClickSign não configurado: o fluxo roda em <b>modo simulação</b> (você confirma cada assinatura aqui). Configure em Configurações → Integrações.</div>`}
      <p class="muted">O sistema gera o PDF do laudo, cria o envelope na ClickSign com os signatários abaixo e cada um recebe o convite por e-mail. Quando todos assinarem, o documento assinado é salvo e enviado por e-mail a todos.</p>
      <div class="signers-ed">${list.map((s, i) => html`<div class="pl-r"><input placeholder="Nome" value=${s.name} onInput=${(e) => { const l = [...list]; l[i] = { ...s, name: e.target.value }; setList(l); }} /><input placeholder="E-mail" value=${s.email} onInput=${(e) => { const l = [...list]; l[i] = { ...s, email: e.target.value }; setList(l); }} /><input placeholder="Telefone" value=${s.phone || ''} onInput=${(e) => { const l = [...list]; l[i] = { ...s, phone: e.target.value }; setList(l); }} />
        <select value=${s.role} onChange=${(e) => { const l = [...list]; l[i] = { ...s, role: e.target.value }; setList(l); }}>${ROLES.map(([v, t]) => html`<option value=${v}>${t}</option>`)}</select><button class="ib" onClick=${() => setList(list.filter((_, j) => j !== i))}><${Icon} name="x" size=${15} /></button></div>`)}
        <button class="btn ghost sm" onClick=${() => setList([...list, { name: '', email: '', role: 'imobiliaria' }])}><${Icon} name="plus" size=${14} /> Adicionar signatário</button></div>
      <div class="actions"><span class="sp"></span><button class="btn primary lg" disabled=${busy || !list.length} onClick=${async () => { setBusy(true); try { const r = await api(`/admin/inspections/${ins.id}/signature`, { body: { signers: list } }); toast(`Enviado para assinatura (${r.signers} signatário(s))`); reload(); } catch (e) { toast(e.message, 'err'); } setBusy(false); }}>${busy ? html`<span class="spin sm light"></span> Gerando PDF…` : html`<${Icon} name="send" size=${17} /> Gerar PDF e enviar para assinatura`}</button></div>
    </${Card}>`;
  const signed = ins.signers.filter((s) => s.status === 'assinado').length;
  return html`<${Card} title=${ins.status === 'assinada' ? 'Documento assinado por todos ✔' : 'Aguardando assinaturas'} icon=${ins.status === 'assinada' ? 'shield' : 'edit'} right=${html`<span class=${'pill ' + (cs.mode === 'clicksign' ? 'green' : 'amber')}>${cs.mode === 'clicksign' ? `ClickSign · ${cs.env}` : 'Simulação'}</span>`} cls=${ins.status === 'assinada' ? 'ok-card' : ''}>
      <div class="sign-prog"><div class="bar-a"><i style=${`width:${(signed / Math.max(1, ins.signers.length)) * 100}%`}></i></div><b>${signed} de ${ins.signers.length} assinaturas</b></div>
      <div class="signers">${ins.signers.map((s) => html`<div class=${'sg' + (s.status === 'assinado' ? ' ok' : '')}><span class="sg-ic"><${Icon} name=${s.status === 'assinado' ? 'check' : 'edit'} size=${16} /></span><div><b>${s.name}</b><small>${s.email} · ${(s.role || '').replace('locatario', 'Locatário(a)').replace('locador', 'Locador(a)')}</small></div><span class="sp"></span>
        ${s.status === 'assinado' ? html`<span class="pill green">Assinado ${fmtDate(s.signed_at)}</span>` : cs.mode !== 'clicksign' ? html`<button class="btn ghost sm" onClick=${async () => { await api(`/admin/signers/${s.id}/simulate`, { body: {} }); toast(`${s.name} assinou (simulado)`); reload(); }}>Simular assinatura</button>` : html`<span class="pill amber">Pendente</span>`}</div>`)}</div>
      <div class="actions">${ins.unsigned_pdf && html`<a class="btn ghost" href=${`/media/${ins.unsigned_pdf}`} target="_blank"><${Icon} name="file" size=${16} /> PDF enviado</a>`}
        ${ins.signed_pdf && html`<a class="btn primary" href=${`/media/${ins.signed_pdf}`} target="_blank"><${Icon} name="shield" size=${16} /> Baixar PDF assinado</a>`}
        ${ins.status === 'assinada' && html`<button class="btn ghost" onClick=${async () => { const r = await api(`/admin/inspections/${ins.id}/resend`, { body: { kind: 'signed', recipients: ins.signers } }); toast(`Documento reenviado para ${r.sent} pessoa(s)`); }}><${Icon} name="mail" size=${16} /> Reenviar documento assinado</button>`}
        <span class="sp"></span>${cs.mode === 'clicksign' && ins.status !== 'assinada' && html`<button class="btn ghost" onClick=${async () => { try { await api(`/admin/inspections/${ins.id}/sync-signature`, { body: {} }); toast('Status atualizado'); reload(); } catch (e) { toast(e.message, 'err'); } }}><${Icon} name="sync" size=${16} /> Atualizar status</button>`}</div>
    </${Card}>`;
}
