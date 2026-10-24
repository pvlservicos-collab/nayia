// Kit de interface do painel administrativo
import { html, useState, useEffect, useRef } from '/shared/vendor/preact-htm.js';
import { Icon } from '/app/js/icons.js';
export { Icon };

// ---------- API ----------
export async function api(path, opts = {}) {
  const headers = { ...(opts.headers || {}) };
  const t = localStorage.getItem('vt_admin');
  if (t) headers.Authorization = `Bearer ${t}`;
  let body = opts.body;
  if (body && !(body instanceof FormData) && typeof body !== 'string') { headers['Content-Type'] = 'application/json'; body = JSON.stringify(body); }
  const r = await fetch(`/api${path}`, { method: opts.method || (body ? 'POST' : 'GET'), headers, body, credentials: 'same-origin' });
  const j = await r.json().catch(() => ({}));
  if (r.status === 401) { localStorage.removeItem('vt_admin'); bus.emit({ type: 'logout' }); throw new Error('Sessão expirada'); }
  if (!r.ok) throw new Error(j.error || `Erro ${r.status}`);
  return j;
}

// ---------- barramento ----------
const ls = new Set();
export const bus = { emit: (e) => ls.forEach((l) => l(e)), on: (l) => { ls.add(l); return () => ls.delete(l); } };
export const toast = (text, kind = 'ok') => bus.emit({ type: 'toast', text, kind });
export const modal = (node) => bus.emit({ type: 'modal', node });
export const closeModal = () => bus.emit({ type: 'modal', node: null });
export function confirmBox({ title, text, ok = 'Confirmar', danger }) {
  return new Promise((res) => {
    const done = (v) => { closeModal(); res(v); };
    modal(html`<${Modal} title=${title} onClose=${() => done(false)} width=${440} footer=${html`<button class="btn ghost" onClick=${() => done(false)}>Cancelar</button><button class=${'btn ' + (danger ? 'danger' : 'primary')} onClick=${() => done(true)}>${ok}</button>`}><p class="muted">${text}</p></${Modal}>`);
  });
}

// ---------- formatação ----------
export const fmtDate = (s, time = true) => { if (!s) return '—'; const d = new Date(s.includes('T') ? s : s.replace(' ', 'T') + 'Z'); return isNaN(d) ? s : d.toLocaleString('pt-BR', time ? { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' } : { day: '2-digit', month: '2-digit', year: 'numeric' }); };
export const fmtBytes = (b) => (b > 1073741824 ? `${(b / 1073741824).toFixed(2)} GB` : b > 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.round((b || 0) / 1024)} KB`);
export const STATUS = { rascunho: ['Em andamento', 'gray'], enviada: ['Recebida', 'blue'], em_revisao: ['Em revisão', 'amber'], aprovada: ['Aprovada', 'green'], em_assinatura: ['Em assinatura', 'purple'], assinada: ['Assinada', 'teal'], cancelada: ['Cancelada', 'red'] };
export const TYPES = { entrada: 'Entrada', saida: 'Saída', temporada: 'Temporada', compra_venda: 'Compra e Venda', periodica: 'Periódica', recebimento: 'Recebimento' };
export const CONDS = { novo: ['Novo', '#2563EB'], bom: ['Bom', '#16A34A'], regular: ['Regular', '#CA8A04'], mau: ['Mau', '#DC2626'] };
export const Status = ({ s }) => { const [l, c] = STATUS[s] || [s, 'gray']; return html`<span class=${'pill ' + c}>${l}</span>`; };

// ---------- componentes ----------
export function Modal({ title, children, onClose, footer, width = 640, cls = '' }) {
  useEffect(() => { const k = (e) => e.key === 'Escape' && onClose && onClose(); window.addEventListener('keydown', k); return () => window.removeEventListener('keydown', k); }, []);
  return html`<div class="m-bg" onMouseDown=${(e) => e.target === e.currentTarget && onClose && onClose()}><div class=${'m-box ' + cls} style=${`max-width:${width}px`}>
    <div class="m-h"><b>${title}</b><button class="ib" onClick=${onClose}><${Icon} name="x" size=${20} /></button></div>
    <div class="m-b">${children}</div>${footer && html`<div class="m-f">${footer}</div>`}</div></div>`;
}
export function Card({ title, icon, right, children, cls = '', pad = true }) {
  return html`<section class=${'acard ' + cls}>${title && html`<div class="acard-h">${icon && html`<span class="acard-ic"><${Icon} name=${icon} size=${18} /></span>`}<b>${title}</b><span class="sp"></span>${right}</div>`}<div class=${pad ? 'acard-b' : ''}>${children}</div></section>`;
}
export function Inp({ label, value, onInput, type = 'text', placeholder, area, rows = 3, hint, cls = '', ...rest }) {
  return html`<label class=${'af ' + cls}>${label && html`<span>${label}</span>`}${area ? html`<textarea rows=${rows} value=${value ?? ''} placeholder=${placeholder} onInput=${(e) => onInput(e.target.value)} ...${rest}></textarea>` : html`<input type=${type} value=${value ?? ''} placeholder=${placeholder} onInput=${(e) => onInput(e.target.value)} ...${rest} />`}${hint && html`<small>${hint}</small>`}</label>`;
}
export function Sel({ label, value, onChange, options, cls = '' }) {
  return html`<label class=${'af ' + cls}>${label && html`<span>${label}</span>`}<select value=${value ?? ''} onChange=${(e) => onChange(e.target.value)}>${options.map((o) => { const v = Array.isArray(o) ? o[0] : o; const l = Array.isArray(o) ? o[1] : o; return html`<option value=${v}>${l}</option>`; })}</select></label>`;
}
export function Switch({ on, onChange, label, sub }) {
  return html`<label class="aswitch"><button type="button" class=${'sw' + (on ? ' on' : '')} onClick=${() => onChange(!on)}><i></i></button><span><b>${label}</b>${sub && html`<small>${sub}</small>`}</span></label>`;
}
export function Empty({ icon = 'clipboard', text = 'Nada por aqui ainda', action }) {
  return html`<div class="aempty"><${Icon} name=${icon} size=${40} stroke=${1.5} /><p>${text}</p>${action}</div>`;
}
export function Loading() { return html`<div class="aload"><span class="spin"></span></div>`; }

// Foto com bolinhas e data
export function Photo({ m, onClick, selected, onSelect, small }) {
  return html`<figure class=${'aph' + (selected ? ' sel' : '') + (small ? ' sm' : '')} onClick=${onClick}>
    ${m.kind === 'video' ? html`<video src=${m.url + '#t=0.5'} muted preload="metadata"></video><span class="aplay"><${Icon} name="play" size=${16} fill /></span>` : m.kind === 'audio' ? html`<div class="aaudio"><${Icon} name="mic" size=${22} /><small>${m.transcript ? `“${m.transcript.slice(0, 60)}”` : 'Áudio'}</small></div>` : html`<img src=${m.url} loading="lazy" />`}
    ${(m.markers || []).map((k) => html`<span class="amk" style=${`left:${k.x * 100}%;top:${k.y * 100}%;width:${(k.r || 0.07) * 200}%`}></span>`)}
    <span class="adt">${fmtDate(m.taken_at)}</span>
    ${onSelect && html`<button class=${'achk' + (selected ? ' on' : '')} onClick=${(e) => { e.stopPropagation(); onSelect(); }}><${Icon} name="check" size=${13} stroke=${3} /></button>`}
  </figure>`;
}

// Editor de bolinhas no painel
export function MarkerModal({ m, onSaved }) {
  const [marks, setMarks] = useState(m.markers || []);
  const [sel, setSel] = useState(-1);
  const box = useRef(null); const drag = useRef(null);
  const pos = (e) => { const r = box.current.getBoundingClientRect(); return { x: Math.min(1, Math.max(0, (e.clientX - r.left) / r.width)), y: Math.min(1, Math.max(0, (e.clientY - r.top) / r.height)) }; };
  const down = (e) => { const p = pos(e); const r = box.current.getBoundingClientRect(); const ar = r.height / r.width; const hit = marks.findIndex((k) => Math.hypot(k.x - p.x, (k.y - p.y) * ar) < (k.r || 0.07) + 0.015); if (hit >= 0) { setSel(hit); drag.current = hit; } else { const n = [...marks, { x: p.x, y: p.y, r: 0.07 }]; setMarks(n); setSel(n.length - 1); drag.current = n.length - 1; } };
  const move = (e) => { if (drag.current == null) return; const p = pos(e); setMarks((ms) => ms.map((k, i) => (i === drag.current ? { ...k, ...p } : k))); };
  async function save() { await api(`/media/${m.id}`, { method: 'PATCH', body: { markers: marks } }); toast('Destaques salvos'); closeModal(); onSaved && onSaved(); }
  return html`<${Modal} title="Destacar avarias com bolinhas" width=${980} onClose=${closeModal} footer=${html`<span class="muted small">Clique para marcar · arraste para mover · selecione e ajuste o tamanho</span><span class="sp"></span>
    ${sel >= 0 && html`<input type="range" min="0.02" max="0.25" step="0.005" value=${marks[sel] && marks[sel].r} onInput=${(e) => setMarks((ms) => ms.map((k, i) => (i === sel ? { ...k, r: +e.target.value } : k)))} />`}
    <button class="btn ghost" disabled=${sel < 0} onClick=${() => { setMarks((ms) => ms.filter((_, i) => i !== sel)); setSel(-1); }}>Remover</button>
    <button class="btn ghost" onClick=${() => { setMarks([]); setSel(-1); }}>Limpar</button><button class="btn primary" onClick=${save}><${Icon} name="check" size=${16} /> Salvar</button>`}>
    <div class="mk-stage"><div class="mk-img" ref=${box} onMouseDown=${down} onMouseMove=${move} onMouseUp=${() => (drag.current = null)} onMouseLeave=${() => (drag.current = null)}>
      <img src=${m.url} draggable="false" />${marks.map((k, i) => html`<span class=${'amk big' + (i === sel ? ' sel' : '')} style=${`left:${k.x * 100}%;top:${k.y * 100}%;width:${(k.r || 0.07) * 200}%`}><b>${i + 1}</b></span>`)}
    </div></div>
  </${Modal}>`;
}

export function BarChart({ data, keys, colors, height = 220 }) {
  const max = Math.max(4, ...data.map((d) => keys.reduce((a, k) => a + (d[k] || 0), 0)));
  const w = 100 / Math.max(1, data.length);
  return html`<div class="bchart" style=${`height:${height}px`}>
    <div class="bc-grid">${[1, 0.75, 0.5, 0.25, 0].map((f) => html`<div><span>${Math.round(max * f)}</span></div>`)}</div>
    <div class="bc-bars">${data.map((d) => html`<div class="bc-col" style=${`width:${w}%`} title=${`${d.label}: ${keys.map((k) => `${k} ${d[k] || 0}`).join(' · ')}`}>
      <div class="bc-stack">${keys.map((k, i) => (d[k] ? html`<i style=${`height:${(d[k] / max) * 100}%;background:${colors[i]}`}></i>` : ''))}</div><small>${d.label}</small></div>`)}</div>
  </div>`;
}
