// Painel administrativo
import { html, render, useState, useEffect } from '/shared/vendor/preact-htm.js';
import { api, bus, toast, Icon } from './ui.js';
import { Logo } from '/app/js/icons.js';
import { Dashboard, Requests, Inspections, Approvals, Contestations, Templates, Screens, Emails, Settings, People, Properties, Users, Vocab } from './pages.js';
import { InspectionPage } from './inspection.js';

export const session = { user: null };
const route = () => (location.hash.replace(/^#/, '') || '/dashboard').split('?')[0].split('/').filter(Boolean);
export const nav = (p) => (location.hash = p);

const MENU = [
  ['dashboard', 'Dashboard', 'layers'],
  ['solicitacoes', 'Solicitações', 'calendar'],
  ['vistorias', 'Vistorias', 'home'],
  ['aprovacoes', 'Aprovações', 'checkCircle', 'badge'],
  ['contestacoes', 'Contestações', 'alert'],
  ['modelos', 'Modelos de vistoria', 'clipboard'],
  ['telas', 'Telas do app', 'eye', 'new'],
  ['emails', 'E-mails', 'mail'],
  ['config', 'Configurações', 'shield', null, [['config/parametros', 'Parâmetros do sistema'], ['config/pessoas', 'Pessoas'], ['config/imoveis', 'Imóveis'], ['config/usuarios', 'Usuários e vistoriadores'], ['config/vocabulario', 'Cômodos e itens']]],
];

function Login({ onDone }) {
  const [email, setEmail] = useState(''); const [pw, setPw] = useState(''); const [busy, setBusy] = useState(false);
  async function go(e) {
    e.preventDefault(); setBusy(true);
    try { const r = await api('/auth/login', { body: { email, password: pw } }); if (r.user.role !== 'admin') throw new Error('Acesso restrito ao administrador. Vistoriadores usam o app em /app'); localStorage.setItem('vt_admin', r.token); session.user = r.user; onDone(); } catch (err) { toast(err.message, 'err'); }
    setBusy(false);
  }
  return html`<div class="alogin"><div class="al-side"><div class="al-glow"></div><div class="al-brand"><${Logo} size=${54} dark /><span class="brand-sub">Vistorias</span></div><h1>Vistorias de imóveis,<br /><em>do app ao laudo assinado.</em></h1>
    <ul><li><${Icon} name="check" size=${18} /> App offline com fotos, áudio e vídeo</li><li><${Icon} name="check" size=${18} /> Avarias destacadas com bolinhas</li><li><${Icon} name="check" size=${18} /> IA que lê o contrato e completa o laudo</li><li><${Icon} name="check" size=${18} /> Assinatura ClickSign e link público</li></ul></div>
    <form class="al-form" onSubmit=${go}><h2>Entrar no painel</h2><p class="muted">Use sua conta de administrador.</p>
      <label class="af"><span>E-mail ou usuário</span><input type="text" autocapitalize="none" required value=${email} onInput=${(e) => setEmail(e.target.value)} autocomplete="username" /></label>
      <label class="af"><span>Senha</span><input type="password" required value=${pw} onInput=${(e) => setPw(e.target.value)} autocomplete="current-password" /></label>
      <button class="btn primary lg" disabled=${busy}>${busy ? html`<span class="spin sm light"></span>` : 'Entrar'}</button>
      <a class="muted small" href="/app/">Sou vistoriador → abrir o app</a></form></div>`;
}

function Shell() {
  const [r, setR] = useState(route());
  const [counts, setCounts] = useState({});
  const [openSub, setOpenSub] = useState(r[0] === 'config');
  const [mob, setMob] = useState(false);
  useEffect(() => { const on = () => { setR(route()); setMob(false); window.scrollTo(0, 0); }; window.addEventListener('hashchange', on); return () => window.removeEventListener('hashchange', on); }, []);
  useEffect(() => { api('/admin/dashboard').then((d) => setCounts({ aprovacoes: d.kpis.pending_approval, contestacoes: d.kpis.contest_open })).catch(() => {}); }, [r.join('/')]);
  const k = r[0];
  let page;
  if (k === 'vistorias' && r[1]) page = html`<${InspectionPage} id=${r[1]} tab=${r[2]} />`;
  else page = ({ dashboard: Dashboard, solicitacoes: Requests, vistorias: Inspections, aprovacoes: Approvals, contestacoes: Contestations, modelos: Templates, telas: Screens, emails: Emails }[k]) || null;
  if (k === 'config') page = ({ parametros: Settings, pessoas: People, imoveis: Properties, usuarios: Users, vocabulario: Vocab }[r[1] || 'parametros']) || Settings;
  const Page = typeof page === 'function' ? page : null;
  return html`<div class=${'shell' + (mob ? ' mob-open' : '')}>
    <aside class="side">
      <div class="side-brand"><${Logo} size=${34} dark /><span class="brand-sub">Vistorias</span></div>
      <nav>${MENU.map(([key, label, icon, extra, sub], i) => html`
        <a class=${'side-i' + (k === key ? ' on' : '')} href=${sub ? null : '#/' + key} onClick=${sub ? () => setOpenSub(!openSub) : null}><span class="si-n">${i + 1}.</span><${Icon} name=${icon} size=${18} /><span class="si-l">${label}</span>
          ${extra === 'badge' && counts.aprovacoes ? html`<em class="si-b">${counts.aprovacoes}</em>` : ''}${key === 'contestacoes' && counts.contestacoes ? html`<em class="si-b red">${counts.contestacoes}</em>` : ''}${extra === 'new' ? html`<em class="si-new">NOVO</em>` : ''}${sub ? html`<${Icon} name=${openSub ? 'up' : 'down'} size=${15} />` : ''}</a>
        ${sub && (openSub || k === 'config') && html`<div class="side-sub">${sub.map(([p, l], j) => html`<a class=${'side-s' + (r.join('/') === p || (p === 'config/parametros' && k === 'config' && !r[1]) ? ' on' : '')} href=${'#/' + p}>${i + 1}.${j + 1}. ${l}</a>`)}</div>`}`)}</nav>
      <div class="side-foot"><a href="/app/" target="_blank" class="side-app"><${Icon} name="camera" size=${16} /> Abrir app do vistoriador</a></div>
    </aside>
    <div class="main">
      <header class="topb"><button class="ib mob-only" onClick=${() => setMob(!mob)}><${Icon} name="menu" size=${22} /></button><span class="sp"></span>
        <a class="topb-l" href="#/aprovacoes"><${Icon} name="checkCircle" size=${18} /> ${counts.aprovacoes || 0} p/ aprovar</a>
        <a class="topb-l" href="#/contestacoes"><span class="bell"><${Icon} name="alert" size=${18} />${counts.contestacoes ? html`<i>${counts.contestacoes}</i>` : ''}</span></a>
        <div class="topb-u"><span class="av">${(session.user.name || 'A')[0]}</span><b>${session.user.name}</b><button class="ib" title="Sair" onClick=${() => { localStorage.removeItem('vt_admin'); fetch('/api/auth/logout', { method: 'POST' }); location.reload(); }}><${Icon} name="logout" size=${18} /></button></div></header>
      <main class="page-w" key=${r.join('/')}>${Page ? html`<${Page} sub=${r[1]} />` : page}</main>
    </div>
    <div class="mob-veil" onClick=${() => setMob(false)}></div>
  </div>`;
}

function Root() {
  const [st, setSt] = useState('loading');
  const [modalNode, setModal] = useState(null);
  const [toasts, setToasts] = useState([]);
  useEffect(() => {
    const off = bus.on((e) => {
      if (e.type === 'modal') setModal(e.node);
      if (e.type === 'toast') { const id = Math.random(); setToasts((t) => [...t, { ...e, id }]); setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 3200); }
      if (e.type === 'logout') setSt('login');
    });
    if (!localStorage.getItem('vt_admin')) setSt('login');
    else api('/auth/me').then((r) => { if (r.user.role !== 'admin') throw new Error(); session.user = r.user; setSt('ok'); }).catch(() => setSt('login'));
    return off;
  }, []);
  return html`${st === 'loading' ? html`<div class="aload full"><span class="spin"></span></div>` : st === 'login' ? html`<${Login} onDone=${() => setSt('ok')} />` : html`<${Shell} />`}
    ${modalNode}<div class="atoasts">${toasts.map((t) => html`<div key=${t.id} class=${'atoast ' + t.kind}><${Icon} name=${t.kind === 'err' ? 'alert' : 'checkCircle'} size=${18} />${t.text}</div>`)}</div>`;
}

render(html`<${Root} />`, document.getElementById('root'));
