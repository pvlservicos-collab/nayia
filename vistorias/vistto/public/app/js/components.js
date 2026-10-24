// Componentes de interface do app do vistoriador
import { html, useState, useEffect, useRef, useCallback } from '/shared/vendor/preact-htm.js';
import { Icon } from './icons.js';
import { media, mediaUrl, uid, DEMO } from './store.js';

// ---------------- barramento de overlays / toasts ----------------
const listeners = new Set();
export const bus = { emit: (e) => listeners.forEach((l) => l(e)), on: (l) => { listeners.add(l); return () => listeners.delete(l); } };
export const toast = (text, kind = 'ok') => bus.emit({ type: 'toast', text, kind });
export const openOverlay = (node) => bus.emit({ type: 'overlay', node });
export const closeOverlay = () => bus.emit({ type: 'overlay', node: null });
export function confirmDialog({ title, text, ok = 'Confirmar', danger = false }) {
  return new Promise((resolve) => {
    const done = (v) => { closeOverlay(); resolve(v); };
    openOverlay(html`<div class="modal-bg" onClick=${(e) => e.target === e.currentTarget && done(false)}><div class="modal pop">
      <h3>${title}</h3>${text && html`<p>${text}</p>`}
      <div class="modal-actions"><button class="btn ghost" onClick=${() => done(false)}>Cancelar</button><button class=${'btn ' + (danger ? 'danger' : 'dark')} onClick=${() => done(true)}>${ok}</button></div>
    </div></div>`);
  });
}
export function promptDialog({ title, value = '', placeholder = '', ok = 'Salvar', suggestions = [] }) {
  return new Promise((resolve) => {
    let v = value;
    const done = (r) => { closeOverlay(); resolve(r); };
    openOverlay(html`<div class="modal-bg" onClick=${(e) => e.target === e.currentTarget && done(null)}><div class="modal pop">
      <h3>${title}</h3>
      <input class="input" autofocus value=${value} placeholder=${placeholder} onInput=${(e) => (v = e.target.value)} onKeyDown=${(e) => e.key === 'Enter' && done(v.trim() || null)} />
      ${suggestions.length ? html`<div class="chips sm">${suggestions.slice(0, 12).map((s) => html`<button class="chip" onClick=${() => done(s)}>${s}</button>`)}</div>` : ''}
      <div class="modal-actions"><button class="btn ghost" onClick=${() => done(null)}>Cancelar</button><button class="btn dark" onClick=${() => done(v.trim() || null)}>${ok}</button></div>
    </div></div>`);
  });
}

// ---------------- básicos ----------------
export function Toggle({ on, onChange, label, sub, danger }) {
  return html`<label class=${'toggle-row' + (on ? ' on' : '') + (danger ? ' danger' : '')}><span class="tg-txt"><b>${label}</b>${sub && html`<small>${sub}</small>`}</span>
    <button type="button" role="switch" aria-checked=${on} class=${'switch' + (on ? ' on' : '')} onClick=${() => onChange(!on)}><i></i></button></label>`;
}
export function Chips({ options, value, onChange, cls = '' }) {
  return html`<div class=${'chips ' + cls}>${options.map((o) => { const v = o.value ?? o; const l = o.label ?? o; return html`<button type="button" class=${'chip' + (value === v ? ' on' : '')} style=${o.color && value === v ? `--cc:${o.color}` : o.color ? `--cd:${o.color}` : ''} onClick=${() => onChange(value === v && o.toggle ? null : v)}>${o.icon && html`<${Icon} name=${o.icon} size=${15} />`}${o.dot && html`<i class="cdot" style=${`background:${o.color}`}></i>`}${l}</button>`; })}</div>`;
}
export function Field({ icon, label, children }) {
  return html`<label class="field">${label && html`<span class="flabel">${label}</span>`}<div class="fwrap">${icon && html`<${Icon} name=${icon} size=${18} cls="fic" />`}${children}</div></label>`;
}
export function Section({ tag, title, count, icon, right, children, cls = '' }) {
  return html`<section class=${'card ' + cls}>${tag && html`<span class="tag">${tag}</span>`}
    ${title && html`<div class="card-h">${icon && html`<${Icon} name=${icon} size=${19} />`}<b>${title}</b>${count != null && html`<span class="count">${count}</span>`}<span class="sp"></span>${right}</div>`}${children}</section>`;
}

export function Stepper({ steps, current, onGo }) {
  return html`<div class="stepper">${steps.map((s, i) => html`
    ${i > 0 && html`<span class=${'sline' + (i <= current ? ' done' : '')}></span>`}
    <button class=${'sdot' + (i < current ? ' done' : i === current ? ' cur' : '')} onClick=${() => onGo && onGo(i)}><span>${i < current ? html`<${Icon} name="check" size=${16} stroke=${3} />` : i + 1}</span><small>${s}</small></button>`)}</div>`;
}

export function Thumb({ id, onClick, onDelete, badge, cls = '' }) {
  const [u, setU] = useState('');
  const [m, setM] = useState(null);
  const [ver, setVer] = useState(0);
  useEffect(() => bus.on((e) => { if (e.type === 'media-changed' && e.id === id) setVer((v) => v + 1); }), [id]);
  useEffect(() => { let ok = true; mediaUrl(id).then((x) => ok && setU(x)); media.get(id).then((x) => ok && setM(x)); return () => (ok = false); }, [id, ver]);
  const kind = m ? m.kind : 'photo';
  const marks = (m && m.markers) || [];
  return html`<div class=${'thumb ' + cls} onClick=${onClick}>
    ${kind === 'video' ? html`<video src=${u} muted playsinline preload="metadata"></video><span class="tplay"><${Icon} name="play" size=${16} fill /></span>` : u ? html`<img src=${u} loading="lazy" />` : html`<span class="tload"></span>`}
    ${marks.map((k) => html`<span class="tmk" style=${`left:${k.x * 100}%;top:${k.y * 100}%;width:${(k.r || 0.07) * 200}%`}></span>`)}
    ${m && !m.uploaded && !DEMO && html`<span class="tsync" title="Salvo no aparelho"><${Icon} name="cloud" size=${12} /></span>`}
    ${marks.length ? html`<span class="tbadge">${marks.length}</span>` : badge}
    ${onDelete && html`<button class="tdel" onClick=${(e) => { e.stopPropagation(); onDelete(); }}><${Icon} name="x" size=${12} stroke=${3} /></button>`}
  </div>`;
}

export function PhotoGrid({ ids = [], onAdd, onOpen, onDelete, addLabel = 'Tirar foto', big = false, emptyLabel }) {
  if (!ids.length && big) return html`<button class="shoot-empty" onClick=${onAdd}><${Icon} name="cameraPlus" size=${30} /><span>${emptyLabel || 'Toque para tirar a primeira foto'}</span></button>`;
  return html`<div class="pgrid">${ids.map((id, i) => html`<${Thumb} key=${id} id=${id} onClick=${() => onOpen && onOpen(id, i)} onDelete=${onDelete && (() => onDelete(id))} />`)}
    ${onAdd && html`<button class="thumb add" onClick=${onAdd}><${Icon} name="cameraPlus" size=${24} /><span>${addLabel}</span></button>`}</div>`;
}

// ---------------- imagens ----------------
export async function compressImage(fileOrBlob, max = 1800, q = 0.84) {
  try {
    const bmp = await createImageBitmap(fileOrBlob, { imageOrientation: 'from-image' });
    const s = Math.min(1, max / Math.max(bmp.width, bmp.height));
    const c = document.createElement('canvas'); c.width = Math.round(bmp.width * s); c.height = Math.round(bmp.height * s);
    c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
    return await new Promise((r) => c.toBlob((b) => r(b || fileOrBlob), 'image/jpeg', q));
  } catch { return fileOrBlob; }
}
export async function saveMedia(inspection_id, { kind, blob, mime, taken_at, transcript, markers }) {
  const id = uid();
  await media.put({ id, inspection_id, kind, blob, mime: mime || blob.type, taken_at: taken_at || new Date().toISOString(), transcript: transcript || '', markers: markers || [], uploaded: false, created_at: new Date().toISOString() });
  return id;
}
export function pickFiles({ accept = 'image/*', multiple = true, capture = null }) {
  return new Promise((resolve) => {
    const inp = document.createElement('input');
    inp.type = 'file'; inp.accept = accept; inp.multiple = multiple; if (capture) inp.setAttribute('capture', capture);
    inp.style.display = 'none'; document.body.appendChild(inp);
    inp.onchange = () => { resolve([...inp.files]); inp.remove(); };
    inp.click();
  });
}

// ---------------- câmera em tela cheia ----------------
export function Camera({ title = 'Tire quantas fotos quiser', limit = 50, already = 0, onDone, demo = false }) {
  const vid = useRef(null);
  const [stream, setStream] = useState(null);
  const [err, setErr] = useState('');
  const [shots, setShots] = useState([]);
  const [zoom, setZoom] = useState(1);
  const [flash, setFlash] = useState(false);
  const [facing, setFacing] = useState('environment');
  useEffect(() => {
    if (demo) return;
    let s;
    (async () => {
      try {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) throw new Error('Câmera indisponível neste navegador (é necessário HTTPS).');
        s = await navigator.mediaDevices.getUserMedia({ video: { facingMode: facing, width: { ideal: 1920 }, height: { ideal: 1440 } }, audio: false });
        setStream(s); if (vid.current) { vid.current.srcObject = s; vid.current.play().catch(() => {}); }
      } catch (e) { setErr(e.name === 'NotAllowedError' ? 'Permita o acesso à câmera nas configurações do navegador.' : 'Não foi possível abrir a câmera deste navegador.'); }
    })();
    return () => s && s.getTracks().forEach((t) => t.stop());
  }, [facing]);
  useEffect(() => {
    if (!stream) return;
    const tr = stream.getVideoTracks()[0];
    try { const cap = tr.getCapabilities ? tr.getCapabilities() : {}; if (cap.zoom) tr.applyConstraints({ advanced: [{ zoom: Math.min(cap.zoom.max, Math.max(cap.zoom.min, zoom)) }] }); } catch {}
  }, [zoom, stream]);
  async function shoot() {
    const v = vid.current; if (!v || !v.videoWidth) return;
    setFlash(true); setTimeout(() => setFlash(false), 160);
    if (navigator.vibrate) navigator.vibrate(18);
    const tr = stream && stream.getVideoTracks()[0];
    const hw = tr && tr.getCapabilities && tr.getCapabilities().zoom;
    const z = hw ? 1 : zoom;
    const sw = v.videoWidth / z, sh = v.videoHeight / z;
    const c = document.createElement('canvas');
    const scale = Math.min(1, 1800 / Math.max(sw, sh));
    c.width = Math.round(sw * scale); c.height = Math.round(sh * scale);
    c.getContext('2d').drawImage(v, (v.videoWidth - sw) / 2, (v.videoHeight - sh) / 2, sw, sh, 0, 0, c.width, c.height);
    const blob = await new Promise((r) => c.toBlob(r, 'image/jpeg', 0.85));
    setShots((s) => [...s, { blob, url: URL.createObjectURL(blob), taken_at: new Date().toISOString() }]);
  }
  async function fallback() {
    const files = await pickFiles({ accept: 'image/*', capture: 'environment', multiple: true });
    const out = [];
    for (const f of files) out.push({ blob: await compressImage(f), taken_at: new Date().toISOString() });
    onDone(out);
  }
  const total = already + shots.length;
  return html`<div class="camera">
    <div class="cam-top"><button class="cam-btn" onClick=${() => onDone([])}><${Icon} name="x" size=${24} /></button><div class="cam-title"><b>${title}</b><small>Cada foto é salva na hora. Ao terminar, toque em “Usar”.</small></div><button class="cam-btn" onClick=${() => setFacing((f) => (f === 'environment' ? 'user' : 'environment'))}><${Icon} name="flip" size=${22} /></button></div>
    <div class="cam-view">
      ${demo ? html`<img class="cam-demo" src="/app/demo/p4.jpg" />` : html`<video ref=${vid} playsinline muted autoplay style=${`transform:scale(${stream && stream.getVideoTracks()[0]?.getCapabilities?.().zoom ? 1 : zoom})`}></video>`}
      ${err && html`<div class="cam-err"><${Icon} name="camera" size=${34} /><p>${err}</p><button class="btn green" onClick=${fallback}>Usar câmera do aparelho</button></div>`}
      ${flash && html`<div class="cam-flash"></div>`}
      <div class="cam-count">${total} de ${limit}</div>
    </div>
    <div class="cam-zoom">${[1, 2].map((z) => html`<button class=${zoom === z ? 'on' : ''} onClick=${() => setZoom(z)}>${z}${zoom === z ? '×' : ''}</button>`)}</div>
    <div class="cam-bottom">
      <div class="cam-last">${shots.length ? html`<img src=${shots[shots.length - 1].url} /><button class="tdel" onClick=${() => setShots((s) => s.slice(0, -1))}><${Icon} name="x" size=${11} stroke=${3} /></button>` : ''}</div>
      <button class="shutter" disabled=${total >= limit} onClick=${demo ? () => {} : shoot} aria-label="Fotografar"><i></i></button>
      <button class="cam-use" onClick=${() => onDone(shots)}><span><${Icon} name="check" size=${22} stroke=${3} /></span>${shots.length ? 'Usar' : 'Pronto'}</button>
    </div>
  </div>`;
}

// ---------------- editor de bolinhas (destaque de avarias) ----------------
export function MarkerEditor({ id, onClose }) {
  const [u, setU] = useState('');
  const [marks, setMarks] = useState([]);
  const [sel, setSel] = useState(-1);
  const box = useRef(null);
  const drag = useRef(null);
  useEffect(() => { mediaUrl(id).then(setU); media.get(id).then((m) => setMarks((m && m.markers) || [])); }, [id]);
  const pos = (e) => { const r = box.current.getBoundingClientRect(); return { x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)) }; };
  function down(e) {
    const p = pos(e);
    const r = box.current.getBoundingClientRect();
    const ar = r.height / r.width;
    const hit = marks.findIndex((k) => Math.hypot(k.x - p.x, (k.y - p.y) * ar) < (k.r || 0.07) + 0.02);
    if (hit >= 0) { setSel(hit); drag.current = { i: hit }; } else { const n = [...marks, { x: p.x, y: p.y, r: 0.08 }]; setMarks(n); setSel(n.length - 1); drag.current = { i: n.length - 1 }; if (navigator.vibrate) navigator.vibrate(10); }
    e.currentTarget.setPointerCapture && e.currentTarget.setPointerCapture(e.pointerId);
  }
  function move(e) { if (!drag.current) return; const p = pos(e); setMarks((ms) => ms.map((k, i) => (i === drag.current.i ? { ...k, x: p.x, y: p.y } : k))); }
  function up() { drag.current = null; }
  async function save() { await media.patch(id, { markers: marks, dirty: true }); bus.emit({ type: 'media-changed', id }); toast(marks.length ? `${marks.length} destaque(s) salvo(s)` : 'Destaques removidos'); onClose(true); }
  const cur = marks[sel];
  return html`<div class="marker-ed">
    <div class="me-top"><button class="cam-btn" onClick=${() => onClose(false)}><${Icon} name="x" size=${22} /></button><div><b>Destacar avaria</b><small>Toque na foto para marcar · arraste para mover</small></div><button class="me-save" onClick=${save}><${Icon} name="check" size=${18} stroke=${3} /> Salvar</button></div>
    <div class="me-stage"><div class="me-img" ref=${box} onPointerDown=${down} onPointerMove=${move} onPointerUp=${up} onPointerCancel=${up}>
      ${u && html`<img src=${u} draggable="false" />`}
      ${marks.map((k, i) => html`<span class=${'mk' + (i === sel ? ' sel' : '')} style=${`left:${k.x * 100}%;top:${k.y * 100}%;width:${(k.r || 0.07) * 200}%`}><b>${i + 1}</b></span>`)}
    </div></div>
    <div class="me-tools">
      ${cur ? html`<div class="me-size"><span>Tamanho</span><input type="range" min="0.03" max="0.25" step="0.005" value=${cur.r} onInput=${(e) => setMarks((ms) => ms.map((k, i) => (i === sel ? { ...k, r: +e.target.value } : k)))} /></div>` : html`<p class="me-hint"><${Icon} name="target" size=${18} /> Marque cada defeito com uma bolinha vermelha. Ela aparece no laudo final.</p>`}
      <div class="me-btns"><button onClick=${() => { setMarks((m) => m.slice(0, -1)); setSel(-1); }} disabled=${!marks.length}><${Icon} name="undo" size=${18} /> Desfazer</button>
      <button onClick=${() => { if (sel < 0) return; setMarks((m) => m.filter((_, i) => i !== sel)); setSel(-1); }} disabled=${sel < 0}><${Icon} name="trash" size=${18} /> Remover</button>
      <button onClick=${() => { setMarks([]); setSel(-1); }} disabled=${!marks.length}><${Icon} name="x" size=${18} /> Limpar</button></div>
    </div>
  </div>`;
}

// ---------------- visualizador de foto ----------------
export function PhotoViewer({ ids, index = 0, onClose, onDelete, onChanged }) {
  const [i, setI] = useState(index);
  const [u, setU] = useState('');
  const [m, setM] = useState(null);
  const [ver, setVer] = useState(0);
  const id = ids[i];
  useEffect(() => { mediaUrl(id).then(setU); media.get(id).then(setM); }, [id, ver]);
  const sx = useRef(null);
  if (!id) return null;
  const go = (d) => setI((x) => (x + d + ids.length) % ids.length);
  return html`<div class="viewer" onTouchStart=${(e) => (sx.current = e.touches[0].clientX)} onTouchEnd=${(e) => { const d = e.changedTouches[0].clientX - (sx.current || 0); if (Math.abs(d) > 60) go(d < 0 ? 1 : -1); }}>
    <div class="me-top"><button class="cam-btn" onClick=${onClose}><${Icon} name="x" size=${22} /></button><div><b>Foto ${i + 1} de ${ids.length}</b><small>${m ? new Date(m.taken_at).toLocaleString('pt-BR') : ''}</small></div><span></span></div>
    <div class="me-stage"><div class="me-img">${m && m.kind === 'video' ? html`<video src=${u} controls autoplay playsinline></video>` : u && html`<img src=${u} />`}
      ${(m && m.markers || []).map((k, n) => html`<span class="mk" style=${`left:${k.x * 100}%;top:${k.y * 100}%;width:${(k.r || 0.07) * 200}%`}><b>${n + 1}</b></span>`)}</div></div>
    <div class="viewer-actions">
      ${m && m.kind === 'photo' && html`<button class="va red" onClick=${() => openOverlay(html`<${MarkerEditor} id=${id} onClose=${(ch) => { closeOverlay(); if (ch) { setVer((v) => v + 1); onChanged && onChanged(); } openOverlay(html`<${PhotoViewer} ids=${ids} index=${i} onClose=${onClose} onDelete=${onDelete} onChanged=${onChanged} />`); }} />`)}><${Icon} name="target" size=${20} /> Marcar avaria</button>`}
      ${onDelete && html`<button class="va" onClick=${async () => { if (await confirmDialog({ title: 'Excluir esta mídia?', ok: 'Excluir', danger: true })) { onDelete(id); onClose(); } else openOverlay(html`<${PhotoViewer} ids=${ids} index=${i} onClose=${onClose} onDelete=${onDelete} onChanged=${onChanged} />`); }}><${Icon} name="trash" size=${20} /> Excluir</button>`}
    </div>
  </div>`;
}

// ---------------- gravação de áudio + transcrição ----------------
function speech() { return window.SpeechRecognition || window.webkitSpeechRecognition; }
export function useRecorder() {
  const [state, setState] = useState({ rec: false, secs: 0, text: '' });
  const r = useRef({});
  const start = useCallback(async () => {
    const st = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mime = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/aac'].find((m) => window.MediaRecorder && MediaRecorder.isTypeSupported && MediaRecorder.isTypeSupported(m)) || '';
    const mr = new MediaRecorder(st, mime ? { mimeType: mime } : undefined);
    const chunks = [];
    mr.ondataavailable = (e) => e.data.size && chunks.push(e.data);
    mr.start(250);
    let text = '';
    const SR = speech();
    let sr = null;
    if (SR) { try { sr = new SR(); sr.lang = 'pt-BR'; sr.continuous = true; sr.interimResults = true; sr.onresult = (e) => { let fin = '', inter = ''; for (let k = 0; k < e.results.length; k++) { const t = e.results[k][0].transcript; if (e.results[k].isFinal) fin += t + ' '; else inter += t; } text = fin; setState((s) => ({ ...s, text: (fin + inter).trim() })); }; sr.onerror = () => {}; sr.start(); } catch { sr = null; } }
    const t0 = Date.now();
    const timer = setInterval(() => setState((s) => ({ ...s, secs: Math.floor((Date.now() - t0) / 1000) })), 250);
    r.current = { st, mr, chunks, sr, timer, getText: () => text, mime: mr.mimeType || mime || 'audio/webm' };
    setState({ rec: true, secs: 0, text: '' });
  }, []);
  const stop = useCallback((keep) => new Promise((resolve) => {
    const c = r.current; if (!c.mr) return resolve(null);
    clearInterval(c.timer);
    try { c.sr && c.sr.stop(); } catch {}
    c.mr.onstop = () => { c.st.getTracks().forEach((t) => t.stop()); const blob = new Blob(c.chunks, { type: c.mime }); r.current = {}; setState({ rec: false, secs: 0, text: '' }); resolve(keep ? { blob, mime: c.mime, transcript: (c.getText() || '').trim() } : null); };
    c.mr.stop();
  }), []);
  return { ...state, start, stop };
}

export function RecordingBar({ secs, text, onCancel, onSave }) {
  const mm = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
  return html`<div class="recbar slide-up">
    <div class="rec-top"><span class="rec-dot"></span><b>Gravando…</b><span class="rec-time">${mm}</span></div>
    <div class="rec-wave">${Array.from({ length: 28 }).map((_, i) => html`<i style=${`animation-delay:${(i % 7) * 0.09}s`}></i>`)}</div>
    ${text ? html`<p class="rec-text">“${text}”</p>` : html`<p class="rec-text muted">Fale normalmente — o texto aparece aqui (quando o aparelho suporta transcrição).</p>`}
    <div class="rec-actions"><button class="btn outline-light" onClick=${onCancel}><${Icon} name="x" size=${18} /> Descartar</button><button class="btn green" onClick=${onSave}><${Icon} name="check" size=${18} stroke=${3} /> Salvar áudio</button></div>
  </div>`;
}

export function AudioChip({ id, onDelete }) {
  const [m, setM] = useState(null);
  const [u, setU] = useState('');
  const [play, setPlay] = useState(false);
  const [dur, setDur] = useState(0);
  const a = useRef(null);
  useEffect(() => { media.get(id).then(setM); mediaUrl(id).then(setU); }, [id]);
  if (!m) return null;
  const toggle = () => { const el = a.current; if (!el) return; if (el.paused) { el.play(); setPlay(true); } else { el.pause(); setPlay(false); } };
  return html`<div class="audio-chip"><audio ref=${a} src=${u} preload="metadata" onLoadedMetadata=${(e) => isFinite(e.target.duration) && setDur(e.target.duration)} onEnded=${() => setPlay(false)}></audio>
    <button class="ac-play" onClick=${toggle}><${Icon} name=${play ? 'pause' : 'play'} size=${16} fill /></button>
    <div class="ac-body"><b>Observação de voz</b><span>${m.transcript ? `“${m.transcript}”` : 'Áudio salvo'}</span></div>
    <span class="ac-dur">${dur ? `0:${String(Math.round(dur)).padStart(2, '0')}` : ''}</span>
    ${onDelete && html`<button class="ac-del" onClick=${onDelete}><${Icon} name="trash" size=${16} /></button>`}</div>`;
}

// Caixa de comentário com botão de áudio (transcreve para o texto) e, opcionalmente, vídeo
export function CommentBox({ value, onChange, placeholder = 'Anotações adicionais…', audios = [], onAudio, onDeleteAudio, onVideo, rows = 3, demoRec = false }) {
  const rec = useRecorder();
  const [busy, setBusy] = useState(false);
  async function startRec() {
    try { await rec.start(); } catch (e) { toast('Não foi possível acessar o microfone: ' + (e.message || e), 'err'); }
  }
  async function save() {
    setBusy(true);
    const r = await rec.stop(true);
    setBusy(false);
    if (!r) return;
    if (r.transcript) onChange(((value || '') + (value ? '\n' : '') + r.transcript).trim());
    onAudio && onAudio(r);
  }
  return html`<div class="cbox">
    <div class="cbox-in"><textarea rows=${rows} placeholder=${placeholder} value=${value || ''} onInput=${(e) => onChange(e.target.value)}></textarea>
      <div class="cbox-tools">
        ${onVideo && html`<button type="button" class="cb-btn" title="Gravar vídeo" onClick=${onVideo}><${Icon} name="video" size=${18} /></button>`}
        <button type="button" class=${'cb-btn mic' + (rec.rec ? ' on' : '')} title="Gravar áudio" onClick=${rec.rec ? save : startRec}><${Icon} name="mic" size=${18} /></button>
      </div></div>
    ${audios.map((id) => html`<${AudioChip} key=${id} id=${id} onDelete=${onDeleteAudio && (() => onDeleteAudio(id))} />`)}
    ${(rec.rec || demoRec) && html`<${RecordingBar} secs=${demoRec ? 3 : rec.secs} text=${demoRec ? 'Painel com a quina inferior lascada' : rec.text} onCancel=${() => rec.stop(false)} onSave=${save} />`}
    ${busy && html`<div class="mini-load">Salvando áudio…</div>`}
  </div>`;
}

export function Sheet({ title, onClose, children }) {
  return html`<div class="sheet-bg" onClick=${(e) => e.target === e.currentTarget && onClose()}><div class="sheet slide-up"><div class="sheet-grab"></div>${title && html`<div class="sheet-h"><b>${title}</b><button class="icon-btn" onClick=${onClose}><${Icon} name="x" size=${20} /></button></div>`}<div class="sheet-body">${children}</div></div></div>`;
}

export function Empty({ icon = 'clipboard', title, text, action }) {
  return html`<div class="empty fade-in"><span class="empty-ic"><${Icon} name=${icon} size=${44} stroke=${1.6} /></span><b>${title}</b>${text && html`<p>${text}</p>`}${action}</div>`;
}
