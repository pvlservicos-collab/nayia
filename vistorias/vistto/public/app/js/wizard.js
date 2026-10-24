// Fluxo da vistoria: Modalidade → Cômodos → Registro (cômodo/itens/avarias) → Dados → Revisão → Envio
import { html, useState, useEffect, useRef } from '/shared/vendor/preact-htm.js';
import { Icon, Logo } from './icons.js';
import { DEMO, kv, inspections, media, uid } from './store.js';
import { api, online, syncInspection, mediaPlacement } from './api.js';
import { toast, openOverlay, closeOverlay, confirmDialog, promptDialog, Toggle, Chips, Field, Section, Stepper, PhotoGrid, Thumb, Camera, MarkerEditor, PhotoViewer, CommentBox, useRecorder, RecordingBar, AudioChip, Sheet, Empty, saveMedia, pickFiles, compressImage } from './components.js';
import { app, go, back } from './main.js';

// rola só a janela do app (não a página que hospeda o iframe na aba "Telas")
function scrollToEl(id, smooth) { const el = document.getElementById(id); if (el) window.scrollTo({ top: el.getBoundingClientRect().top + window.scrollY - 90, behavior: smooth ? 'smooth' : 'auto' }); }
const STEPS = ['Modalidade', 'Cômodos', 'Registro', 'Dados', 'Revisão'];
const TYPE_ICONS = { entrada: 'door', saida: 'logout', temporada: 'star', compra_venda: 'house', periodica: 'calendar', recebimento: 'building' };
const COND = [{ value: 'novo', label: 'Novo', color: '#2563EB', dot: true, toggle: true }, { value: 'bom', label: 'Bom', color: '#16A34A', dot: true, toggle: true }, { value: 'regular', label: 'Regular', color: '#CA8A04', dot: true, toggle: true }, { value: 'mau', label: 'Mau', color: '#DC2626', dot: true, toggle: true }];
const FUNC = [{ value: 'funcionando', label: 'Funcionando', toggle: true, color: '#16A34A' }, { value: 'nao_funcionando', label: 'Não funciona', toggle: true, color: '#DC2626' }, { value: 'nao_testado', label: 'Não testado', toggle: true, color: '#64748B' }];

// Hook de edição com gravação automática no aparelho
function useIns(id) {
  const [ins, setIns] = useState(null);
  const [saved, setSaved] = useState(true);
  const t = useRef(null);
  useEffect(() => { inspections.get(id).then((x) => { if (!x && !DEMO) go('/home', true); setIns(x); }); }, [id]);
  const update = (fn) => setIns((cur) => {
    if (!cur) return cur;
    const n = structuredClone(cur);
    fn(n);
    if (n.local_status === 'sent') n.local_status = 'draft';
    setSaved(false); clearTimeout(t.current);
    inspections.put(n).then(() => { t.current = setTimeout(() => setSaved(true), 350); });
    return n;
  });
  return [ins, update, saved];
}
const SavedChip = ({ saved }) => html`<span class=${'saved' + (saved ? '' : ' saving')}><${Icon} name=${saved ? 'check' : 'cloud'} size=${13} stroke=${2.6} />${saved ? 'Salvo' : 'Salvando…'}</span>`;
const typeLabel = (t) => ((app.boot && app.boot.types) || {})[t] || { label: 'Nova Vistoria', short: '' };

function WizardHeader({ ins, step, saved, onGo }) {
  return html`<div class="wz-head">
    <header class="topbar"><button class="icon-btn" onClick=${() => go('/home')}><${Icon} name="arrowLeft" size=${22} /></button><div class="brand"><${Logo} size=${28} /><span><b>Vist</b><i>to</i></span></div><button class="avatar" onClick=${() => go('/perfil')}>${((app.user && app.user.name) || 'U')[0]}</button></header>
    <div class="wz-title"><b>${ins.type ? typeLabel(ins.type).label : 'Nova Vistoria'}</b><${SavedChip} saved=${saved} /></div>
    <${Stepper} steps=${STEPS} current=${step} onGo=${onGo} />
  </div>`;
}
function WizardFoot({ step, onBack, onNext, canNext = true, last }) {
  return html`<div class="wz-foot"><button class="circle light" onClick=${onBack}><${Icon} name="arrowLeft" size=${22} /></button>
    <div class="wz-foot-c"><b>${STEPS[step]}</b><small>Passo ${step + 1} de ${STEPS.length}</small></div>
    <button class=${'circle ' + (last ? 'green' : 'dark')} disabled=${!canNext} onClick=${onNext}><${Icon} name=${last ? 'check' : 'arrowRight'} size=${22} stroke=${2.6} /></button></div>`;
}

export function Wizard({ id, step: stepParam }) {
  const [ins, update, saved] = useIns(id);
  const step = stepParam != null ? stepParam : ins ? ins.step || 0 : 0;
  useEffect(() => { if (ins && ins.step !== step) update((n) => (n.step = step)); }, [step, !!ins]);
  if (!ins) return html`<div class="splash"><div class="spin"></div></div>`;
  const goStep = (s) => { if (s > 0 && !ins.type) return toast('Escolha a modalidade', 'err'); if (s > 1 && !ins.rooms.length) return toast('Adicione ao menos um cômodo', 'err'); go(`/v/${id}/${s}`, true); window.scrollTo(0, 0); };
  const next = () => (step < 4 ? goStep(step + 1) : go(`/v/${id}/send`));
  const prev = () => (step > 0 ? goStep(step - 1) : go('/home'));
  const canNext = step === 0 ? !!ins.type : step === 1 ? ins.rooms.length > 0 : true;
  const Body = [StepType, StepRooms, StepRegister, StepData, StepReview][step] || StepType;
  return html`<div class="screen wizard">
    <${WizardHeader} ins=${ins} step=${step} saved=${saved} onGo=${goStep} />
    <div class="content wz-content" key=${step}><${Body} ins=${ins} update=${update} id=${id} next=${next} /></div>
    <${WizardFoot} step=${step} onBack=${prev} onNext=${next} canNext=${canNext} last=${step === 4} />
  </div>`;
}

// ---------- Passo 1: modalidade ----------
function StepType({ ins, update, next }) {
  const types = (app.boot && app.boot.types) || {};
  const templates = (app.boot && app.boot.templates) || [];
  return html`<${Section} cls="pop">
    <div class="q-head"><span class="q-ic"><${Icon} name="checkCircle" size=${22} /></span><div><b>Qual tipo de vistoria você vai fazer?</b><small>Selecione uma opção para começar</small></div></div>
    <div class="type-grid">${Object.entries(types).map(([k, t]) => html`<button class=${'type-card' + (ins.type === k ? ' on' : '')} onClick=${() => { update((n) => (n.type = k)); setTimeout(() => go(`/v/${ins.id}/1`, true), 260); }}><span><${Icon} name=${TYPE_ICONS[k] || 'house'} size=${22} /></span><b>${t.label}</b></button>`)}</div>
  </${Section}>
  ${templates.length && !ins.rooms.length ? html`<${Section} title="Começar de um modelo" icon="layers"><small class="muted">Opcional — já adiciona cômodos e itens padrão.</small>
    <div class="tpl-list">${templates.map((t) => html`<button class="tpl" onClick=${() => { update((n) => { n.rooms = (t.rooms || []).map((r) => ({ id: uid(), name: r.name, media: [], audios: [], notes: '', items: (r.items || []).map((x) => ({ id: uid(), name: x, media: [], audios: [], ncs: [] })) })); if (!n.type) n.type = t.type || 'entrada'; }); toast('Modelo aplicado ✔'); }}><${Icon} name="layers" size=${18} /><span><b>${t.name}</b><small>${(t.rooms || []).length} cômodos</small></span><${Icon} name="plus" size=${18} /></button>`)}</div></${Section}>` : ''}`;
}

// ---------- Passo 2: cômodos ----------
function uniqueName(rooms, name) {
  const same = rooms.filter((r) => r.name === name || r.name.replace(/\s+\d+$/, '') === name).length;
  return same ? `${name} ${same + 1}` : name;
}
async function rememberVocab(kind, name) {
  const key = kind === 'room' ? 'customRooms' : 'customItems';
  const cur = (await kv.get(key, [])) || [];
  if (!cur.includes(name)) await kv.set(key, [name, ...cur].slice(0, 80));
  if (!DEMO && online()) api('/vocab', { body: { kind, name } }).catch(() => {});
}
function StepRooms({ ins, update }) {
  const [txt, setTxt] = useState('');
  const [custom, setCustom] = useState([]);
  useEffect(() => { kv.get('customRooms', []).then((c) => setCustom(c || [])); }, []);
  const base = ((app.boot && app.boot.vocab && app.boot.vocab.rooms) || []).slice(0, 14);
  const mine = [...new Set([...(custom || []), ...((app.boot && app.boot.vocab && app.boot.vocab.customRooms) || [])])].filter((x) => !base.includes(x));
  const add = (name) => update((n) => n.rooms.push({ id: uid(), name: uniqueName(n.rooms, name), media: [], audios: [], items: [], notes: '' }));
  async function addCustom() {
    const name = txt.trim(); if (!name) return;
    add(name); setTxt('');
    if (!base.includes(name)) { await rememberVocab('room', name); setCustom((c) => [name, ...c.filter((x) => x !== name)]); toast(`“${name}” salvo na sua lista`); }
  }
  const move = (i, d) => update((n) => { const j = i + d; if (j < 0 || j >= n.rooms.length) return; [n.rooms[i], n.rooms[j]] = [n.rooms[j], n.rooms[i]]; });
  return html`<${Section} cls="pop">
      <div class="h2">Cômodos do imóvel</div><small class="muted">Toque para adicionar rapidamente ou digite um nome</small>
      <div class="lbl">ADIÇÃO RÁPIDA</div>
      <div class="chips add">${base.map((r) => html`<button class="chip" onClick=${() => add(r)}><${Icon} name="plus" size=${14} />${r}</button>`)}</div>
      ${mine.length ? html`<div class="lbl">MEUS CÔMODOS <small>(salvos na sua lista)</small></div><div class="chips add">${mine.map((r) => html`<button class="chip mine" onClick=${() => add(r)}><${Icon} name="star" size=${13} />${r}</button>`)}</div>` : ''}
      <div class="add-row"><div class="fwrap"><${Icon} name="door" size=${18} cls="fic" /><input class="input" placeholder="Outro cômodo…" value=${txt} onInput=${(e) => setTxt(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && addCustom()} /></div><button class="sq dark" onClick=${addCustom}><${Icon} name="plus" size=${22} /></button></div>
    </${Section}>
    <div class="sec-h"><b>Adicionados <span class="count">${ins.rooms.length}</span></b></div>
    ${ins.rooms.length ? ins.rooms.map((r, i) => html`<div class="room-row fade-in" key=${r.id}><span class="num">${i + 1}</span><b>${r.name}</b><span class="sp"></span>
      <button class="icon-btn sm" onClick=${() => move(i, -1)} disabled=${i === 0}><${Icon} name="up" size=${16} /></button><button class="icon-btn sm" onClick=${() => move(i, 1)} disabled=${i === ins.rooms.length - 1}><${Icon} name="down" size=${16} /></button>
      <button class="icon-btn sm danger" onClick=${async () => { if (r.media.length + r.items.length === 0 || (await confirmDialog({ title: `Remover ${r.name}?`, text: 'Fotos e itens deste cômodo serão apagados.', ok: 'Remover', danger: true }))) update((n) => n.rooms.splice(i, 1)); }}><${Icon} name="trash" size=${17} /></button></div>`) : html`<${Empty} icon="door" title="Nenhum cômodo ainda" text="Use a adição rápida acima." />`}`;
}

// ---------- Passo 3: registro ----------
function countKinds(r) {
  const ph = r.media.length + r.items.reduce((a, it) => a + it.media.length + (it.ncs || []).reduce((b, n) => b + n.media.length, 0), 0);
  const au = (r.audios || []).length + r.items.reduce((a, it) => a + (it.audios || []).length, 0);
  const nc = r.items.reduce((a, it) => a + (it.has_nc ? (it.ncs || []).length : 0), 0);
  return { ph, au, nc };
}
function StepRegister({ ins, update, id }) {
  return html`<${Section} cls="pop">
    <div class="q-head"><span class="q-ic"><${Icon} name="camera" size=${22} /></span><div><b>Registre os cômodos</b><small>Toque para registrar · use as setas para reordenar · lápis para renomear</small></div></div>
    ${ins.rooms.map((r, i) => { const c = countKinds(r); return html`<div class=${'reg-row' + (r.done ? ' done' : '')} key=${r.id} onClick=${() => go(`/v/${id}/room/${r.id}`)}>
      <span class="grip"><${Icon} name="grip" size=${16} /></span>
      <div class="reg-b"><b>${r.name} ${r.done ? html`<${Icon} name="checkCircle" size=${16} cls="okc" />` : ''}</b><small>${c.ph} foto(s) · ${c.au} áudio(s) · ${r.items.length} ${r.items.length === 1 ? 'item' : 'itens'}${c.nc ? html` · <em class="red">${c.nc} avaria(s)</em>` : ''}</small></div>
      <button class="icon-btn sm boxed" onClick=${async (e) => { e.stopPropagation(); const v = await promptDialog({ title: 'Renomear cômodo', value: r.name }); if (v) update((n) => (n.rooms[i].name = v)); }}><${Icon} name="edit" size=${16} /></button>
      <button class="icon-btn sm boxed danger" onClick=${async (e) => { e.stopPropagation(); if (await confirmDialog({ title: `Remover ${r.name}?`, ok: 'Remover', danger: true })) update((n) => n.rooms.splice(i, 1)); }}><${Icon} name="trash" size=${16} /></button></div>`; })}
    <button class="add-room" onClick=${async () => { const v = await promptDialog({ title: 'Adicionar cômodo', placeholder: 'Ex.: Varanda gourmet', suggestions: (app.boot && app.boot.vocab.rooms) || [] }); if (v) { update((n) => n.rooms.push({ id: uid(), name: uniqueName(n.rooms, v), media: [], audios: [], items: [], notes: '' })); rememberVocab('room', v); } }}><span><${Icon} name="plus" size=${18} stroke=${2.6} /></span> Adicionar cômodo</button>
  </${Section}>`;
}

// ---------- Tela do cômodo ----------
export function RoomScreen({ id, roomId, q = {} }) {
  const [ins, update, saved] = useIns(id);
  const [open, setOpen] = useState(q.open || null);
  const rec = useRecorder();
  useEffect(() => { if (q.open) setTimeout(() => { scrollToEl('it-' + q.open, false); }, 350); }, []);
  useEffect(() => { if (q.marker && ins) openOverlay(html`<${MarkerEditor} id=${q.marker} onClose=${() => closeOverlay()} />`); }, [!!ins]);
  if (!ins) return html`<div class="splash"><div class="spin"></div></div>`;
  const ri = ins.rooms.findIndex((r) => r.id === roomId);
  const room = ins.rooms[ri];
  if (!room) return html`<${Empty} title="Cômodo não encontrado" action=${html`<button class="btn dark" onClick=${() => go(`/v/${id}/2`)}>Voltar</button>`} />`;
  const limit = (app.boot && app.boot.params && app.boot.params.photos_per_room) || 50;
  const upRoom = (fn) => update((n) => fn(n.rooms.find((r) => r.id === roomId)));

  function camera(target, after) {
    const already = target === 'room' ? room.media.length : 0;
    openOverlay(html`<${Camera} limit=${limit} already=${already} title=${target === 'room' ? `Fotos · ${room.name}` : 'Fotos do item'} onDone=${async (shots) => {
      closeOverlay();
      const ids = [];
      for (const s of shots) ids.push(await saveMedia(id, { kind: 'photo', blob: s.blob, mime: 'image/jpeg', taken_at: s.taken_at }));
      if (ids.length) { after(ids); toast(`${ids.length} foto(s) salva(s) no aparelho`); }
    }} />`);
  }
  async function gallery(after) {
    const files = await pickFiles({ accept: 'image/*,video/*', multiple: true });
    const ids = [];
    for (const f of files) {
      const isV = f.type.startsWith('video');
      ids.push(await saveMedia(id, { kind: isV ? 'video' : 'photo', blob: isV ? f : await compressImage(f), mime: isV ? f.type : 'image/jpeg', taken_at: new Date(f.lastModified || Date.now()).toISOString() }));
    }
    if (ids.length) { after(ids); toast(`${ids.length} arquivo(s) adicionados`); }
  }
  async function video(after) {
    const [f] = await pickFiles({ accept: 'video/*', multiple: false, capture: 'environment' });
    if (!f) return;
    after([await saveMedia(id, { kind: 'video', blob: f, mime: f.type || 'video/mp4' })]);
    toast('Vídeo salvo no aparelho');
  }
  const view = (ids, i, onDel) => openOverlay(html`<${PhotoViewer} ids=${ids} index=${i} onClose=${closeOverlay} onDelete=${onDel} onChanged=${() => upRoom(() => {})} />`);
  const delFrom = (getList) => (mid) => { upRoom((r) => { const l = getList(r); const k = l.indexOf(mid); if (k >= 0) l.splice(k, 1); }); media.del(mid); };

  async function saveVoice() {
    const r = await rec.stop(true);
    if (!r) return;
    const mid = await saveMedia(id, { kind: 'audio', blob: r.blob, mime: r.mime, transcript: r.transcript });
    upRoom((rm) => { rm.audios = [...(rm.audios || []), mid]; if (r.transcript) rm.notes = ((rm.notes || '') + (rm.notes ? '\n' : '') + r.transcript).trim(); });
    toast('Observação de voz salva');
  }
  async function addItem() {
    const custom = (await kv.get('customItems', [])) || [];
    const sug = [...new Set([...custom, ...((app.boot && app.boot.vocab && app.boot.vocab.items) || [])])];
    openOverlay(html`<${ItemPicker} suggestions=${sug} custom=${custom} onPick=${(name, isNew) => {
      closeOverlay();
      const nid = uid();
      upRoom((r) => r.items.push({ id: nid, name, condition: null, functioning: null, quantity: null, notes: '', media: [], audios: [], has_nc: false, ncs: [] }));
      setOpen(nid);
      if (isNew) { rememberVocab('item', name); toast(`“${name}” salvo na sua lista de itens`); }
      setTimeout(() => scrollToEl('it-' + nid, true), 250);
    }} onClose=${closeOverlay} />`);
  }
  const nextRoom = () => {
    upRoom((r) => (r.done = true));
    const nx = ins.rooms[ri + 1];
    toast(`${room.name} concluído ✔`);
    if (nx) go(`/v/${id}/room/${nx.id}`, true); else go(`/v/${id}/2`, true);
  };

  return html`<div class="screen room-screen">
    <header class="topbar room-top"><button class="icon-btn" onClick=${() => go(`/v/${id}/2`, true)}><${Icon} name="arrowLeft" size=${22} /></button>
      <button class="rt-name" onClick=${async () => { const v = await promptDialog({ title: 'Renomear cômodo', value: room.name }); if (v) upRoom((r) => (r.name = v)); }}><b>${room.name}</b><span class="pill blue solid">${typeLabel(ins.type).short || 'Vistoria'}</span></button>
      <span class="pill light">${ri + 1} de ${ins.rooms.length}</span></header>
    <div class="content room-content">
      <div class="tip"><${Icon} name="info" size=${18} /><span><b>Dica:</b> fotografe o cômodo, adicione cada móvel/item com seu estado e ligue <b>Inconformidade</b> para registrar avarias com bolinhas.</span><${SavedChip} saved=${saved} /></div>

      <${Section} tag="PASSO 1" title="Fotos do cômodo" icon="camera" count=${room.media.length} right=${html`<button class="link-btn" onClick=${() => gallery((ids) => upRoom((r) => r.media.push(...ids)))}><${Icon} name="image" size=${17} /> Galeria</button>`}>
        <small class="muted">${room.media.length} de ${limit} fotos</small>
        <${PhotoGrid} big ids=${room.media} onAdd=${() => camera('room', (ids) => upRoom((r) => r.media.push(...ids)))} onOpen=${(mid, i) => view(room.media, i, delFrom((r) => r.media))} onDelete=${delFrom((r) => r.media)} />
        <small class="hint"><${Icon} name="pin" size=${14} /> Fotografe paredes, piso, teto, janelas e pontos de atenção.</small>
      </${Section}>

      <${Section} tag="PASSO 2" title="Itens e móveis" icon="box" count=${room.items.length}>
        <small class="muted">Adicione cada item com nome, estado, fotos exclusivas e observações.</small>
        <div class="items">${room.items.map((it, ii) => html`<${ItemCard} key=${it.id} it=${it} idx=${ii} open=${open === it.id} onToggle=${() => setOpen(open === it.id ? null : it.id)}
          set=${(fn) => upRoom((r) => fn(r.items.find((x) => x.id === it.id)))}
          remove=${async () => { if (await confirmDialog({ title: `Remover ${it.name}?`, ok: 'Remover', danger: true })) upRoom((r) => r.items.splice(r.items.findIndex((x) => x.id === it.id), 1)); }}
          rename=${async () => { const v = await promptDialog({ title: 'Renomear item', value: it.name }); if (v) upRoom((r) => (r.items.find((x) => x.id === it.id).name = v)); }}
          camera=${camera} gallery=${gallery} video=${video} view=${view} inspId=${id} demoRec=${q.rec && q.open === it.id} />`)}</div>
        <button class="add-room" onClick=${addItem}><span><${Icon} name="plus" size=${18} stroke=${2.6} /></span> Adicionar item / móvel</button>
      </${Section}>

      <${Section} tag="PASSO 3" title="Observações do cômodo" icon="mic" count=${(room.audios || []).length}>
        <small class="muted">Descreva por texto ou voz — o áudio é transcrito automaticamente.</small>
        <${CommentBox} value=${room.notes} onChange=${(v) => upRoom((r) => (r.notes = v))} placeholder="Anotações adicionais sobre o cômodo…" audios=${room.audios || []}
          onAudio=${async (r) => { const mid = await saveMedia(id, { kind: 'audio', blob: r.blob, mime: r.mime, transcript: r.transcript }); upRoom((rm) => (rm.audios = [...(rm.audios || []), mid])); }}
          onDeleteAudio=${delFrom((r) => (r.audios = r.audios || []))} demoRec=${q.rec && !q.open} />
      </${Section}>

      <${Section} tag="OPCIONAL" title="Vídeo do cômodo" icon="video" count=${room.media.filter((m) => false).length}>
        <small class="muted">Grave um vídeo panorâmico do ambiente (fica salvo no aparelho até sincronizar).</small>
        <button class="btn outline sm" onClick=${() => video((ids) => upRoom((r) => r.media.push(...ids)))}><${Icon} name="video" size=${17} /> Gravar vídeo</button>
      </${Section}>
      <div style="height:150px"></div>
    </div>
    ${rec.rec && html`<div class="rec-float"><${RecordingBar} secs=${rec.secs} text=${rec.text} onCancel=${() => rec.stop(false)} onSave=${saveVoice} /></div>`}
    <div class="room-foot">
      <div class="rf-btns"><button class="btn green photo-cta" onClick=${() => camera('room', (ids) => upRoom((r) => r.media.push(...ids)))}><${Icon} name="camera" size=${22} /> Tirar fotos</button>
      <button class="btn dark" onClick=${async () => { try { await rec.start(); } catch (e) { toast('Microfone indisponível: ' + e.message, 'err'); } }}><${Icon} name="mic" size=${20} /> Gravar voz</button></div>
      <button class="rf-done" onClick=${nextRoom}><${Icon} name="checkCircle" size=${18} /> Concluir cômodo</button>
    </div>
  </div>`;
}

function ItemPicker({ suggestions, custom, onPick, onClose }) {
  const [q, setQ] = useState('');
  const list = suggestions.filter((s) => s.toLowerCase().includes(q.toLowerCase())).slice(0, 40);
  const exact = suggestions.some((s) => s.toLowerCase() === q.trim().toLowerCase());
  return html`<${Sheet} title="Adicionar item ou móvel" onClose=${onClose}>
    <div class="search"><${Icon} name="search" size=${18} /><input autofocus placeholder="Ex.: Rack, Painel de TV, Lustre…" value=${q} onInput=${(e) => setQ(e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && q.trim() && onPick(q.trim(), !exact)} /></div>
    ${q.trim() && !exact && html`<button class="pick-new" onClick=${() => onPick(q.trim(), true)}><${Icon} name="plusCircle" size=${20} /> Criar “<b>${q.trim()}</b>” e salvar na lista</button>`}
    <div class="chips pick">${list.map((s) => html`<button class=${'chip' + (custom.includes(s) ? ' mine' : '')} onClick=${() => onPick(s, false)}>${custom.includes(s) && html`<${Icon} name="star" size=${12} />`}${s}</button>`)}</div>
  </${Sheet}>`;
}

function ItemCard({ it, idx, open, onToggle, set, remove, rename, camera, gallery, video, view, inspId, demoRec }) {
  const cond = COND.find((c) => c.value === it.condition);
  const delMedia = (list) => (mid) => { set((x) => { const l = list(x); l.splice(l.indexOf(mid), 1); }); media.del(mid); };
  const addNc = () => set((x) => { x.ncs = x.ncs || []; x.ncs.push({ id: uid(), title: '', description: '', media: [], audios: [] }); x.has_nc = true; });
  const ncPhotos = (nid) => camera('item', async (ids) => {
    set((x) => x.ncs.find((n) => n.id === nid).media.push(...ids));
    openOverlay(html`<${MarkerEditor} id=${ids[0]} onClose=${() => { closeOverlay(); set(() => {}); }} />`);
  });
  const nPh = it.media.length + (it.ncs || []).reduce((a, n) => a + n.media.length, 0);
  return html`<div class=${'item-card' + (open ? ' open' : '') + (it.has_nc ? ' has-nc' : '')} id=${'it-' + it.id}>
    <div class="ic-head" onClick=${onToggle}>
      <span class="ic-num">${idx + 1}</span>
      <div class="ic-t"><b>${it.name}</b><small>${cond ? html`<i class="cdot" style=${`background:${cond.color}`}></i>${cond.label}` : html`<em>Defina o estado</em>`}${it.functioning ? ` · ${{ funcionando: 'Funcionando', nao_funcionando: 'Não funciona', nao_testado: 'Não testado' }[it.functioning]}` : ''}${it.quantity ? ` · Qtd ${it.quantity}` : ''} · ${nPh} foto(s)</small></div>
      ${it.has_nc && (it.ncs || []).length ? html`<span class="nc-badge">${it.ncs.length}</span>` : ''}
      <${Icon} name="down" size=${18} cls="chev" />
    </div>
    <div class="itc-body"><div class="ic-inner">
      <div class="lbl">ESTADO</div>
      <${Chips} options=${COND} value=${it.condition} onChange=${(v) => set((x) => (x.condition = v))} cls="cond" />
      <div class="ic-row">
        <div class="ic-col"><div class="lbl">FUNCIONAMENTO <small>(se aplicável)</small></div><${Chips} options=${FUNC} value=${it.functioning} onChange=${(v) => set((x) => (x.functioning = v))} cls="sm" /></div>
      </div>
      <div class="ic-row qty"><div class="lbl">QUANTIDADE</div><div class="stepper-n"><button onClick=${() => set((x) => (x.quantity = Math.max(0, (x.quantity || 1) - 1) || null))}>−</button><b>${it.quantity || '—'}</b><button onClick=${() => set((x) => (x.quantity = (x.quantity || 0) + 1))}>+</button></div></div>
      <div class="lbl">FOTOS EXCLUSIVAS DO ITEM <span class="sp"></span><button class="link-btn" onClick=${() => gallery((ids) => set((x) => x.media.push(...ids)))}><${Icon} name="image" size=${15} /> Galeria</button></div>
      <${PhotoGrid} ids=${it.media} addLabel="Foto do item" onAdd=${() => camera('item', (ids) => set((x) => x.media.push(...ids)))} onOpen=${(mid, i) => view(it.media, i, delMedia((x) => x.media))} onDelete=${delMedia((x) => x.media)} />
      <div class="lbl">OBSERVAÇÕES</div>
      <${CommentBox} value=${it.notes} onChange=${(v) => set((x) => (x.notes = v))} placeholder="Ex.: Rack em MDF carvalho, 2 portas, puxadores em alumínio…" audios=${it.audios || []}
        onAudio=${async (r) => { const mid = await saveMedia(inspId, { kind: 'audio', blob: r.blob, mime: r.mime, transcript: r.transcript }); set((x) => (x.audios = [...(x.audios || []), mid])); }}
        onDeleteAudio=${delMedia((x) => (x.audios = x.audios || []))} onVideo=${() => video((ids) => set((x) => x.media.push(...ids)))} demoRec=${demoRec} />

      <${Toggle} danger on=${!!it.has_nc} label="Inconformidade" sub="Registrar avaria / defeito neste item" onChange=${(v) => set((x) => { x.has_nc = v; x.ncs = x.ncs || []; if (v && !x.ncs.length) x.ncs.push({ id: uid(), title: '', description: '', media: [], audios: [] }); })} />
      ${it.has_nc && html`<div class="ncs slide-down">${(it.ncs || []).map((n, ni) => html`<div class="nc-card" key=${n.id}>
        <div class="nc-h"><span class="dot red"></span><b>Inconformidade ${ni + 1}</b><span class="sp"></span><button class="icon-btn sm danger" onClick=${() => set((x) => { x.ncs.splice(ni, 1); if (!x.ncs.length) x.has_nc = false; })}><${Icon} name="trash" size=${16} /></button></div>
        <input class="input" placeholder="Título · ex.: Rack esfarelado na base" value=${n.title} onInput=${(e) => set((x) => (x.ncs[ni].title = e.target.value))} />
        <${CommentBox} rows=${2} value=${n.description} onChange=${(v) => set((x) => (x.ncs[ni].description = v))} placeholder="Descreva a avaria (ou grave um áudio)…" audios=${n.audios || []}
          onAudio=${async (r) => { const mid = await saveMedia(inspId, { kind: 'audio', blob: r.blob, mime: r.mime, transcript: r.transcript }); set((x) => (x.ncs[ni].audios = [...(x.ncs[ni].audios || []), mid])); }} />
        <${PhotoGrid} ids=${n.media} addLabel="Foto da avaria" onAdd=${() => ncPhotos(n.id)} onOpen=${(mid, i) => view(n.media, i, delMedia((x) => x.ncs[ni].media))} onDelete=${delMedia((x) => x.ncs[ni].media)} />
        ${n.media.length ? html`<small class="hint red"><${Icon} name="target" size=${14} /> Toque na foto → “Marcar avaria” para colocar as bolinhas vermelhas.</small>` : ''}
      </div>`)}
      <button class="btn outline-red sm" onClick=${addNc}><${Icon} name="plus" size=${16} /> Adicionar outra inconformidade</button></div>`}
      <div class="ic-actions"><button class="link-btn" onClick=${rename}><${Icon} name="edit" size=${15} /> Renomear</button><button class="link-btn danger" onClick=${remove}><${Icon} name="trash" size=${15} /> Remover item</button></div>
    </div></div>
  </div>`;
}

// ---------- Passo 4: dados ----------
const PTYPES = [['Apartamento', 'building'], ['Casa', 'house'], ['Sobrado', 'layers'], ['Kitnet/Studio', 'door'], ['Sala Comercial', 'box'], ['Galpão', 'box'], ['Terreno', 'pin'], ['Rancho', 'house'], ['Outro', 'plus']];
function PersonForm({ p, onChange, onRemove, title }) {
  const f = (k, v) => onChange({ ...p, [k]: v });
  return html`<div class="person"><div class="person-h"><small>${title}</small>${onRemove && html`<button class="icon-btn sm danger" onClick=${onRemove}><${Icon} name="trash" size=${15} /></button>`}</div>
    <${Field} icon="user"><input class="input" placeholder="Nome" value=${p.name || ''} onInput=${(e) => f('name', e.target.value)} /></${Field}>
    <${Field} icon="file"><input class="input" placeholder="CPF" inputmode="numeric" value=${p.cpf || ''} onInput=${(e) => f('cpf', e.target.value)} /></${Field}>
    <${Field} icon="whatsapp"><input class="input" placeholder="Telefone" inputmode="tel" value=${p.phone || ''} onInput=${(e) => f('phone', e.target.value)} /></${Field}>
    <${Field} icon="mail"><input class="input" placeholder="E-mail (recebe o laudo e a assinatura)" type="email" value=${p.email || ''} onInput=${(e) => f('email', e.target.value)} /></${Field}></div>`;
}
function People({ ins, update, k, title, icon, addLabel, optional }) {
  const list = (ins.parties && ins.parties[k]) || [];
  return html`<${Section} title=${title} icon=${icon}>
    ${optional && html`<small class="muted">${optional}</small>`}
    ${list.map((p, i) => html`<${PersonForm} key=${i} p=${p} title=${`${i + 1}º ${title.toLowerCase().replace(/s$/, '').replace(/(e)s$/, '$1')}`} onChange=${(v) => update((n) => (n.parties[k][i] = v))} onRemove=${list.length > 1 || optional ? () => update((n) => n.parties[k].splice(i, 1)) : null} />`)}
    <button class="link-btn add" onClick=${() => update((n) => { n.parties = n.parties || {}; n.parties[k] = [...(n.parties[k] || []), {}]; })}><${Icon} name="plusCircle" size=${18} /> ${addLabel}</button>
  </${Section}>`;
}
function StepData({ ins, update, id }) {
  const p = ins.property || {};
  const setP = (k, v) => update((n) => { n.property = n.property || {}; n.property[k] = v; });
  const [busy, setBusy] = useState('');
  async function cep() {
    const c = (p.cep || '').replace(/\D/g, '');
    if (c.length !== 8) return toast('Digite um CEP com 8 dígitos', 'err');
    setBusy('cep');
    try { const r = await fetch(`https://viacep.com.br/ws/${c}/json/`).then((x) => x.json()); if (r.erro) throw new Error('CEP não encontrado');
      update((n) => Object.assign(n.property, { street: r.logradouro || n.property.street, district: r.bairro || n.property.district, city: r.localidade || n.property.city, state: r.uf || n.property.state })); toast('Endereço preenchido ✔'); } catch (e) { toast(e.message || 'Falha ao buscar CEP', 'err'); }
    setBusy('');
  }
  function locate() {
    if (!navigator.geolocation) return toast('Localização indisponível', 'err');
    setBusy('geo');
    navigator.geolocation.getCurrentPosition(async (pos) => {
      try { const { latitude: la, longitude: lo } = pos.coords; const r = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${la}&lon=${lo}&accept-language=pt-BR`).then((x) => x.json()); const a = r.address || {};
        update((n) => Object.assign(n.property, { street: a.road || n.property.street, number: a.house_number || n.property.number, district: a.suburb || a.neighbourhood || n.property.district, city: a.city || a.town || n.property.city, state: (a['ISO3166-2-lvl4'] || '').split('-')[1] || n.property.state, cep: a.postcode || n.property.cep, lat: la, lng: lo })); toast('Localização aplicada ✔'); } catch { toast('Sem internet para buscar o endereço — coordenadas salvas', 'err'); update((n) => Object.assign(n.property, { lat: pos.coords.latitude, lng: pos.coords.longitude })); }
      setBusy('');
    }, () => { setBusy(''); toast('Permissão de localização negada', 'err'); }, { enableHighAccuracy: true, timeout: 12000 });
  }
  async function contract() {
    const [f] = await pickFiles({ accept: 'application/pdf', multiple: false });
    if (!f) return;
    const mid = await saveMedia(id, { kind: 'pdf', blob: f, mime: 'application/pdf' });
    update((n) => (n.contract = { media_id: mid, filename: f.name, uploaded: false }));
    if (DEMO) return toast('Contrato lido ✔');
    if (!online()) return toast('Contrato salvo. A IA lê o contrato assim que houver internet.');
    setBusy('ai');
    try {
      const fd = new FormData(); fd.append('file', f, f.name);
      const r = await api('/ai/contract', { body: fd });
      const d = r.data || {};
      const nz = (o) => Object.fromEntries(Object.entries(o || {}).filter(([, v]) => v !== '' && v != null));
      update((n) => {
        n.property = { ...(n.property || {}), ...nz(d.property) };
        n.parties = n.parties || {};
        for (const k of ['locadores', 'locatarios', 'fiadores']) if (d.parties && d.parties[k] && d.parties[k].length) n.parties[k] = d.parties[k].map((x) => ({ name: x.name, cpf: x.cpf, email: x.email, phone: x.phone, rg: x.rg }));
        n.contract = { ...n.contract, extracted: true, engine: r.engine };
      });
      toast('IA preencheu os dados do contrato ✔');
    } catch (e) { toast('IA indisponível: ' + e.message + '. O contrato será enviado na sincronização.', 'err'); }
    setBusy('');
  }
  const meter = (k, label, icon, cls) => {
    const m = (ins.meters && ins.meters[k]) || {};
    const setM = (fn) => update((n) => { n.meters = n.meters || {}; n.meters[k] = n.meters[k] || { media: [] }; n.meters[k].media = n.meters[k].media || []; fn(n.meters[k]); });
    return html`<div class=${'meter ' + cls}><div class="mt-h"><${Icon} name=${icon} size=${18} /><b>${label}</b></div>
      <div class="mt-f"><input class="input" placeholder="Nº medidor / matrícula" value=${m.number || ''} onInput=${(e) => setM((x) => (x.number = e.target.value))} /><input class="input" placeholder="Leitura" inputmode="decimal" value=${m.reading || ''} onInput=${(e) => setM((x) => (x.reading = e.target.value))} /></div>
      <${PhotoGrid} ids=${m.media || []} addLabel="Foto" onAdd=${() => openOverlay(html`<${Camera} limit=${4} title=${`Medidor · ${label}`} onDone=${async (shots) => { closeOverlay(); const ids = []; for (const s of shots) ids.push(await saveMedia(id, { kind: 'photo', blob: s.blob, mime: 'image/jpeg', taken_at: s.taken_at })); setM((x) => x.media.push(...ids)); }} />`)} onDelete=${(mid) => { setM((x) => x.media.splice(x.media.indexOf(mid), 1)); media.del(mid); }} />
    </div>`;
  };
  return html`
    <div class="ai-card pop" onClick=${busy ? null : contract}>
      <span class="ai-ic">${busy === 'ai' ? html`<span class="spin sm light"></span>` : html`<${Icon} name="sparkles" size=${24} />`}</span>
      <div><b>${busy === 'ai' ? 'A IA está lendo o contrato…' : ins.contract && ins.contract.filename ? 'Contrato anexado ✔' : 'Preencher endereço e dados com IA'}</b><small>${ins.contract && ins.contract.filename ? ins.contract.filename : 'Anexe o contrato de locação (PDF) e a IA preenche imóvel, locador e locatários.'}</small></div>
      <${Icon} name="right" size=${20} />
    </div>
    <p class="muted small center">Opcional — você ou a imobiliária podem completar depois pelo painel.</p>
    <${Section} title="Endereço do imóvel" icon="pin">
      <div class="lbl">TIPO DE IMÓVEL</div>
      <${Chips} options=${PTYPES.map(([l, ic]) => ({ value: l, label: l, icon: ic }))} value=${p.type} onChange=${(v) => setP('type', v)} cls="boxy" />
      <button class="btn outline xl" onClick=${locate} disabled=${busy === 'geo'}>${busy === 'geo' ? html`<span class="spin sm"></span>` : html`<${Icon} name="target" size=${18} />`} Usar minha localização</button>
      <div class="add-row"><div class="fwrap"><${Icon} name="mail" size=${18} cls="fic" /><input class="input" placeholder="CEP" inputmode="numeric" value=${p.cep || ''} onInput=${(e) => setP('cep', e.target.value)} /></div><button class="btn ghost" onClick=${cep}>${busy === 'cep' ? html`<span class="spin sm"></span>` : html`<${Icon} name="search" size=${17} />`} Buscar</button></div>
      <${Field} icon="home"><input class="input" placeholder="Endereço (rua/avenida)" value=${p.street || ''} onInput=${(e) => setP('street', e.target.value)} /></${Field}>
      <div class="two"><input class="input" placeholder="Número" value=${p.number || ''} onInput=${(e) => setP('number', e.target.value)} /><input class="input" placeholder="Complemento (apto, bloco…)" value=${p.complement || ''} onInput=${(e) => setP('complement', e.target.value)} /></div>
      <${Field} icon="layers"><input class="input" placeholder="Bairro" value=${p.district || ''} onInput=${(e) => setP('district', e.target.value)} /></${Field}>
      <div class="two r"><input class="input" placeholder="Cidade" value=${p.city || ''} onInput=${(e) => setP('city', e.target.value)} /><input class="input" placeholder="UF" maxlength="2" value=${p.state || ''} onInput=${(e) => setP('state', e.target.value.toUpperCase())} /></div>
      <${Field} icon="building"><input class="input" placeholder="Identificação (ex.: Edifício X - Apto 202)" value=${p.identification || ''} onInput=${(e) => setP('identification', e.target.value)} /></${Field}>
      <div class="lbl">FINALIDADE</div><${Chips} options=${['Residencial', 'Comercial']} value=${p.purpose} onChange=${(v) => setP('purpose', v)} />
      <div class="lbl">MOBÍLIA</div><${Chips} options=${['Mobiliado', 'Semimobiliado', 'Não mobiliado']} value=${p.furnished} onChange=${(v) => setP('furnished', v)} />
      <${Field} icon="box"><input class="input" placeholder="Metragem (m²)" inputmode="decimal" value=${p.area || ''} onInput=${(e) => setP('area', e.target.value)} /></${Field}>
    </${Section}>
    <${People} ins=${ins} update=${update} k="locatarios" title="Locatários" icon="users" addLabel="Adicionar locatário" />
    <${People} ins=${ins} update=${update} k="locadores" title="Locadores" icon="user" addLabel="Adicionar locador" />
    <${People} ins=${ins} update=${update} k="fiadores" title="Fiadores" icon="shield" addLabel="Adicionar fiador" optional="Opcional. Se preenchido, o fiador aparece como parte envolvida e ganha um bloco de assinatura no laudo." />
    <${Section} title="Leitura dos medidores" icon="bolt">
      ${meter('energia', 'Energia elétrica', 'bolt', 'orange')}${meter('agua', 'Água', 'drop', 'blue')}${meter('gas', 'Gás', 'flame', 'red')}
    </${Section}>
    <${People} ins=${ins} update=${update} k="testemunhas" title="Testemunhas" icon="users" addLabel="Adicionar testemunha" optional="Opcional." />
    <${Section} title="Observações gerais" icon="file">
      <${CommentBox} value=${ins.general_notes} onChange=${(v) => update((n) => (n.general_notes = v))} placeholder="Chaves entregues, controles, observações finais…" />
    </${Section}>`;
}

// ---------- Passo 5: revisão ----------
function review(ins) {
  const p = ins.property || {}, pa = ins.parties || {};
  let ph = 0, au = 0, nc = 0, items = 0, noState = 0;
  for (const r of ins.rooms) { const c = countKinds(r); ph += c.ph; au += c.au; nc += c.nc; items += r.items.length; noState += r.items.filter((i) => !i.condition).length; }
  const checks = [
    ['Modalidade definida', !!ins.type], ['Cômodos registrados', ins.rooms.length > 0], ['Fotos em todos os cômodos', ins.rooms.every((r) => countKinds(r).ph > 0)],
    ['Estado de todos os itens', noState === 0], ['Endereço do imóvel', !!(p.street && p.city)], ['Tipo do imóvel', !!p.type],
    ['Locatário com e-mail', (pa.locatarios || []).some((x) => x.name && x.email)], ['Locador', (pa.locadores || []).some((x) => x.name)],
    ['Leitura de medidor', Object.values(ins.meters || {}).some((m) => m.reading)],
  ];
  return { ph, au, nc, items, checks, score: Math.round((checks.filter((c) => c[1]).length / checks.length) * 100) };
}
function StepReview({ ins, id }) {
  const r = review(ins);
  const [show, setShow] = useState(false);
  return html`
    <div class="ready pop"><span><${Icon} name="checkCircle" size=${26} /></span><div><b>Tudo pronto!</b><small>Revise e envie a vistoria para aprovação</small></div></div>
    <div class="stat-grid">${[['door', ins.rooms.length, 'Cômodos', ''], ['camera', r.ph, 'Fotos', 'amber'], ['mic', r.au, 'Áudios', 'green'], ['alert', r.nc, 'Avarias', 'red']].map(([ic, n, l, c]) => html`<div class=${'stat ' + c}><${Icon} name=${ic} size=${22} /><b>${n}</b><small>${l}</small></div>`)}</div>
    <div class="card score" onClick=${() => setShow(!show)}><div class="ring sm" style=${`--p:${r.score}`}><b>${r.score}</b></div><div><b>Score de preenchimento: ${r.score}%</b><small>${show ? 'Toque para ocultar' : 'Ver o que falta'} ›</small></div></div>
    ${show && html`<div class="card checklist slide-down">${r.checks.map(([l, ok]) => html`<div class=${'ck' + (ok ? ' ok' : '')}><${Icon} name=${ok ? 'checkCircle' : 'alert'} size=${17} />${l}</div>`)}</div>`}
    <div class="card"><div class="kv-row"><span>Modalidade</span><b>${typeLabel(ins.type).label}</b></div><div class="kv-row"><span>Imóvel</span><b>${(ins.property && (ins.property.identification || ins.property.street)) || '—'}</b></div><div class="kv-row"><span>Locatário</span><b>${((ins.parties && ins.parties.locatarios) || []).map((x) => x.name).filter(Boolean).join(', ') || '—'}</b></div></div>
    <div class="safe"><${Icon} name="shield" size=${22} /><div><b>Seus dados estão seguros</b><small>Todas as mídias capturadas estão salvas no aparelho. Se a internet cair, o envio continua depois automaticamente.</small></div></div>
    <button class="btn green xl send-cta" onClick=${() => go(`/v/${id}/send`)}><${Icon} name="send" size=${20} /> Enviar para aprovação</button>
    <p class="muted small center">Após o envio, a imobiliária revisa as fotos, anexa o contrato, aprova e o laudo segue para assinatura.</p>`;
}

// ---------- Envio ----------
export function SendScreen({ id, q = {} }) {
  const [st, setSt] = useState(DEMO ? { step: 'midias', done: 7, total: 12 } : { step: 'dados', done: 0, total: 0 });
  const [err, setErr] = useState('');
  const [off, setOff] = useState(false);
  const t0 = useRef(Date.now());
  const [secs, setSecs] = useState(0);
  useEffect(() => { const t = setInterval(() => setSecs(Math.floor((Date.now() - t0.current) / 1000)), 1000); return () => clearInterval(t); }, []);
  useEffect(() => {
    if (DEMO) return;
    (async () => {
      const ins = await inspections.get(id);
      if (!ins) return go('/home', true);
      ins.local_status = 'queued'; await inspections.put(ins);
      const run = async () => { setOff(false); setErr(''); try { await syncInspection(id, setSt); } catch (e) { setErr(e.message); } };
      if (!online()) { setOff(true); window.addEventListener('online', run, { once: true }); return; }
      run();
    })();
  }, [id]);
  const steps = [['dados', 'Envio dos dados da vistoria'], ['midias', 'Envio das fotos, áudios e vídeos'], ['envio', 'Enviada para aprovação']];
  const order = ['dados', 'midias', 'envio', 'ok'];
  const cur = order.indexOf(st.step);
  return html`<div class="send-screen">
    <div class="onb-glow"></div>
    <div class="ss-head"><span class="ai-ic"><${Icon} name=${off ? 'cloudOff' : 'cloud'} size=${24} /></span><div><b>${off ? 'Sem conexão no momento' : st.step === 'ok' ? 'Vistoria enviada!' : 'Enviando sua vistoria'}</b><small>Tempo: ${secs}s</small></div><span class=${'net ' + (off ? 'off' : '')}>${off ? 'Offline' : 'Online'}</span></div>
    ${off ? html`<div class="ss-off pop"><${Icon} name="shield" size=${40} /><p>Sua vistoria está <b>salva no aparelho</b> e entrou na fila. Ela será enviada automaticamente assim que você se conectar à internet.</p></div>` : html`
    <div class="ss-steps">${steps.map(([k, l], i) => { const done = cur > i || st.step === 'ok'; const now = cur === i && st.step !== 'ok'; return html`<div class=${'ss-step' + (done ? ' done' : '') + (now ? ' now' : '')}>
      <span class="ss-dot">${done ? html`<${Icon} name="check" size=${15} stroke=${3} />` : now ? html`<span class="spin sm light"></span>` : i + 1}</span>
      <div><b>${l}</b>${k === 'midias' && (now || done) ? html`<small>${st.done} de ${st.total} mídia(s)</small><div class="ss-bar"><i style=${`width:${st.total ? (st.done / st.total) * 100 : 100}%`}></i></div>` : done ? html`<small>Concluído.</small>` : ''}</div></div>`; })}</div>`}
    ${err && html`<div class="ss-err">${err}<br /><small>Fique tranquilo: nada se perde. Tentaremos novamente automaticamente.</small></div>`}
    <div class="ss-foot"><p>${st.step === 'ok' ? 'A imobiliária foi avisada e vai revisar seu laudo.' : 'Mantenha o app aberto até terminar. Se precisar sair, nada se perde: o envio continua depois.'}</p>
      <button class="btn green xl" onClick=${() => go('/home', true)}>${st.step === 'ok' ? 'Voltar ao início' : 'Continuar depois'}</button></div>
  </div>`;
}

export function CameraDemo() {
  return html`<${Camera} demo limit=${10} already=${0} onDone=${() => go('/home')} />`;
}
