// App do vistoriador (PWA offline-first)
import { html, render, useState, useEffect, useRef } from '/shared/vendor/preact-htm.js';
import { DEMO, kv, inspections, seedDemo, persist } from './store.js';
import { getToken, bootstrap, startBackgroundSync, online } from './api.js';
import { bus, toast } from './components.js';
import { Onboarding, Login, Home, InspectionList, SyncCenter, Support, Profile, ServerDetail } from './screens.js';
import { Wizard, RoomScreen, SendScreen, CameraDemo } from './wizard.js';
import { demoState, DEMO_BOOT } from './demo.js';

export const app = { boot: null, user: null };

function parseHash() {
  const h = location.hash.replace(/^#/, '') || '/home';
  const [path, qs] = h.split('?');
  return { path, parts: path.split('/').filter(Boolean), q: Object.fromEntries(new URLSearchParams(qs || '')) };
}
export const go = (path, replace = false) => { if (replace) history.replaceState(null, '', '#' + path); else location.hash = path; if (replace) window.dispatchEvent(new HashChangeEvent('hashchange')); };
let navCount = 0;
window.addEventListener('hashchange', () => navCount++);
export const back = (fallback = '/home') => { if (navCount > 0) history.back(); else go(fallback, true); };

function App() {
  const [route, setRoute] = useState(parseHash());
  const [ready, setReady] = useState(false);
  const [authed, setAuthed] = useState(false);
  const [overlay, setOverlay] = useState(null);
  const [toasts, setToasts] = useState([]);
  const [net, setNet] = useState(online());
  const depth = useRef(history.length);
  const [dir, setDir] = useState('fwd');

  useEffect(() => {
    const on = () => {
      const n = history.length;
      setDir(n < depth.current ? 'back' : 'fwd'); depth.current = n;
      setRoute(parseHash()); setOverlay(null);
    };
    window.addEventListener('hashchange', on);
    window.addEventListener('popstate', () => setDir('back'));
    const u1 = () => setNet(true), u2 = () => setNet(false);
    window.addEventListener('online', u1); window.addEventListener('offline', u2);
    const off = bus.on((e) => {
      if (e.type === 'overlay') setOverlay(e.node);
      if (e.type === 'toast') { const id = Math.random(); setToasts((t) => [...t, { ...e, id }]); setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 2600); }
      if (e.type === 'logout') { setAuthed(false); go('/login', true); }
      if (e.type === 'login') { setAuthed(true); startBackgroundSync((id, err) => { if (!err) toast('Vistoria sincronizada ✔'); }); }
    });
    (async () => {
      if (DEMO) {
        seedDemo(demoState());
        app.boot = DEMO_BOOT; app.user = DEMO_BOOT.user; setAuthed(true); setReady(true); return;
      }
      persist();
      const t = await getToken();
      app.user = await kv.get('user');
      if (t) {
        try { app.boot = await bootstrap(); setAuthed(true); } catch (e) { if (e.auth) setAuthed(false); else { app.boot = await kv.get('bootstrap'); setAuthed(true); } }
        startBackgroundSync((id, err) => { if (!err) toast('Vistoria sincronizada ✔'); });
      }
      setReady(true);
    })();
    return () => { window.removeEventListener('hashchange', on); off(); };
  }, []);

  if (!ready) return html`<div class="splash"><div class="spin"></div></div>`;
  const p = route.parts;
  let screen;
  const needAuth = !authed && !['onboarding', 'login'].includes(p[0]);
  if (needAuth) {
    screen = html`<${Onboarding} />`;
  } else if (p[0] === 'onboarding') screen = html`<${Onboarding} />`;
  else if (p[0] === 'login') screen = html`<${Login} />`;
  else if (p[0] === 'vistorias') screen = html`<${InspectionList} />`;
  else if (p[0] === 'sync') screen = html`<${SyncCenter} />`;
  else if (p[0] === 'suporte') screen = html`<${Support} />`;
  else if (p[0] === 'perfil') screen = html`<${Profile} />`;
  else if (p[0] === 'camera') screen = html`<${CameraDemo} />`;
  else if (p[0] === 's' && p[1]) screen = html`<${ServerDetail} id=${p[1]} />`;
  else if (p[0] === 'v' && p[1] && p[2] === 'room') screen = html`<${RoomScreen} id=${p[1]} roomId=${p[3]} q=${route.q} />`;
  else if (p[0] === 'v' && p[1] && p[2] === 'send') screen = html`<${SendScreen} id=${p[1]} q=${route.q} />`;
  else if (p[0] === 'v' && p[1]) screen = html`<${Wizard} id=${p[1]} step=${p[2] != null ? +p[2] : null} q=${route.q} />`;
  else screen = html`<${Home} />`;

  return html`<div class="app">
    ${!net && !DEMO && html`<div class="offline-bar"><span>Sem conexão — tudo está sendo salvo no aparelho</span></div>`}
    <div key=${route.path} class=${'page ' + (dir === 'back' ? 'page-back' : 'page-fwd')}>${screen}</div>
    ${overlay && html`<div class="overlay-root">${overlay}</div>`}
    <div class="toasts">${toasts.map((t) => html`<div key=${t.id} class=${'toast ' + t.kind}>${t.text}</div>`)}</div>
  </div>`;
}

render(html`<${App} />`, document.getElementById('root'));

if ('serviceWorker' in navigator && !DEMO) navigator.serviceWorker.register('/app/sw.js', { scope: '/app/' }).catch(() => {});
