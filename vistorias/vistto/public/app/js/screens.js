// Telas principais: boas-vindas, login, início, vistorias, sincronização, suporte, perfil
import { html, useState, useEffect } from '/shared/vendor/preact-htm.js';
import { Icon, Logo } from './icons.js';
import { DEMO, kv, inspections, media, storageEstimate } from './store.js';
import { api, setSession, clearSession, bootstrap, syncInspection, online, mediaPlacement } from './api.js';
import { toast, bus, confirmDialog, Empty, Field, Section } from './components.js';
import { app, go, back } from './main.js';

export function TopBar({ title, onBack, right, sub }) {
  return html`<header class="topbar">
    ${onBack ? html`<button class="icon-btn" onClick=${onBack} aria-label="Voltar"><${Icon} name="arrowLeft" size=${22} /></button>` : html`<span class="tb-sp"></span>`}
    ${title ? html`<div class="tb-title"><b>${title}</b>${sub && html`<small>${sub}</small>`}</div>` : html`<div class="brand"><${Logo} size=${30} /><span class="brand-sub">Vistorias</span></div>`}
    ${right || html`<button class="avatar" onClick=${() => go('/perfil')}>${((app.user && app.user.name) || 'U')[0].toUpperCase()}</button>`}
  </header>`;
}

export function BottomNav({ active }) {
  const it = (k, icon, label, path) => html`<button class=${'bn' + (active === k ? ' on' : '')} onClick=${() => go(path)}><${Icon} name=${icon} size=${22} stroke=${active === k ? 2.4 : 1.9} /><span>${label}</span></button>`;
  return html`<nav class="bottomnav">${it('home', 'home', 'Início', '/home')}${it('list', 'clipboard', 'Vistorias', '/vistorias')}
    <button class="bn-fab" onClick=${newInspection} aria-label="Nova vistoria"><${Icon} name="plus" size=${28} stroke=${2.6} /></button>
    ${it('sync', 'sync', 'Sincronizar', '/sync')}${it('help', 'headset', 'Suporte', '/suporte')}</nav>`;
}

export async function newInspection() {
  const id = crypto.randomUUID ? crypto.randomUUID() : String(Date.now());
  await inspections.put({ id, type: null, created_at: new Date().toISOString(), local_status: 'draft', step: 0, rooms: [], property: {}, parties: { locatarios: [{}], locadores: [{}], fiadores: [], testemunhas: [] }, meters: {}, general_notes: '' });
  go(`/v/${id}/0`);
}

// ---------------- Boas-vindas ----------------
const SLIDES = [
  { t: 'Vistoria de Imóveis com IA', d: 'Vistoriadores, corretores, imobiliárias e engenheiros: uma ferramenta só, do início ao laudo assinado.', chips: [['shield', 'Vistoriador'], ['star', 'Corretor'], ['building', 'Imobiliária'], ['user', 'Engenheiro']] },
  { t: 'Funciona sem internet', d: 'Fotos, áudios, vídeos e dados ficam salvos no aparelho e sobem sozinhos quando você se conectar.', chips: [['cloudOff', 'Offline'], ['cloud', 'Sincroniza sozinho']] },
  { t: 'Avarias em destaque', d: 'Marque cada defeito com bolinhas vermelhas na foto. Tudo vai para o laudo, separado por cômodo.', chips: [['target', 'Bolinhas'], ['mic', 'Áudio'], ['video', 'Vídeo']] },
];
export function Onboarding() {
  const [i, setI] = useState(0);
  const s = SLIDES[i];
  return html`<div class="onb">
    <div class="onb-glow"></div>
    <div class="onb-body" key=${i}>
      <div class="onb-logo"><${Logo} size=${58} dark /><span class="brand-sub">Vistorias</span></div>
      <h1>${s.t}</h1><p>${s.d}</p>
      <div class="onb-chips">${s.chips.map(([ic, l]) => html`<span><${Icon} name=${ic} size=${14} />${l}</span>`)}</div>
    </div>
    <div class="onb-foot">
      <div class="dots">${SLIDES.map((_, k) => html`<i class=${k === i ? 'on' : ''} onClick=${() => setI(k)}></i>`)}</div>
      <button class="btn green xl" onClick=${() => (i < SLIDES.length - 1 ? setI(i + 1) : go('/login'))}>${i < SLIDES.length - 1 ? 'Próximo' : 'Começar'}</button>
      <p class="onb-link">Já tem conta? <a onClick=${() => go('/login')}>Entrar</a></p>
    </div>
  </div>`;
}

export function Login() {
  const [email, setEmail] = useState('');
  const [pw, setPw] = useState('');
  const [busy, setBusy] = useState(false);
  const [show, setShow] = useState(false);
  async function submit(e) {
    e.preventDefault();
    if (DEMO) return;
    setBusy(true);
    try {
      const r = await fetch('/api/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw }) }).then(async (x) => { const j = await x.json(); if (!x.ok) throw new Error(j.error); return j; });
      await setSession(r.token, r.user); app.user = r.user;
      app.boot = await bootstrap(true);
      await kv.set('onboarded', true);
      bus.emit({ type: 'login' });
      go('/home', true);
    } catch (err) { toast(err.message || 'Falha no login', 'err'); }
    setBusy(false);
  }
  return html`<div class="login">
    <div class="login-hero"><div class="onb-glow"></div><${Logo} size=${50} dark /><h1>Bem-vindo de volta</h1><p>Entre para continuar suas vistorias</p></div>
    <form class="login-form slide-up" onSubmit=${submit}>
      <${Field} icon="mail" label="E-mail ou usuário"><input class="input" type="text" autocapitalize="none" autocomplete="username" required value=${email} onInput=${(e) => setEmail(e.target.value)} placeholder="voce@empresa.com" /></${Field}>
      <${Field} icon="key" label="Senha"><input class="input" type=${show ? 'text' : 'password'} autocomplete="current-password" required value=${pw} onInput=${(e) => setPw(e.target.value)} placeholder="Sua senha" /><button type="button" class="eye" onClick=${() => setShow(!show)}><${Icon} name="eye" size=${18} /></button></${Field}>
      <button class="btn dark xl" disabled=${busy}>${busy ? html`<span class="spin sm"></span>` : 'Entrar'}</button>
      <p class="muted center small">Acesso fornecido pela sua imobiliária. Depois do primeiro login o app funciona offline.</p>
    </form>
  </div>`;
}

// ---------------- Início ----------------
function countMedia(ins) { const pl = mediaPlacement(ins); return pl.size; }
export function Home() {
  const [list, setList] = useState([]);
  const [server, setServer] = useState([]);
  useEffect(() => {
    inspections.all().then(setList);
    if (!DEMO && online()) api('/app/inspections').then(setServer).catch(() => {});
  }, []);
  const local = list.filter((i) => i.local_status !== 'sent');
  const queued = list.filter((i) => i.local_status === 'queued');
  const st = (s) => server.filter((x) => s.includes(x.status)).length;
  const counts = DEMO ? [2, 5, 3, local.length] : [st(['enviada', 'em_revisao']), st(['aprovada', 'em_assinatura']), st(['assinada']), local.length];
  const name = ((app.user && app.user.name) || '').split(' ')[0];
  const recent = [...local.map((i) => ({ local: true, ...i })), ...server.filter((s) => !local.some((l) => l.id === s.id)).map((s) => ({ ...s, remote: true }))].slice(0, 6);
  return html`<div class="screen with-nav">
    <${TopBar} />
    <div class="content">
      <div class="hello fade-in"><h2>Olá, ${name || 'vistoriador'}! <span class="wave">👋</span></h2><p>O que vamos fazer hoje?</p></div>
      <button class="btn dark xl newbtn pop" onClick=${newInspection}><${Icon} name="plus" size=${20} stroke=${2.6} /> NOVA VISTORIA</button>
      <div class="kpis">${[['EM REVISÃO', '#F59E0B'], ['FINALIZADAS', '#1B1B1E'], ['ASSINADAS', '#22C55E'], ['ANDAMENTO', '#A2A2AA']].map(([l, c], k) => html`<div class="kpi" style=${`--k:${c}`}><b>${counts[k]}</b><span>${l}</span></div>`)}</div>
      ${queued.length ? html`<div class="card sync-card pop" onClick=${() => go('/sync')}><span class="sc-ic"><${Icon} name="cloud" size=${22} /></span><div><b>${queued.length} vistoria(s) aguardando envio</b><small>${online() ? 'Enviando automaticamente…' : 'Serão enviadas quando houver internet'}</small></div><${Icon} name="right" size=${18} /></div>` : ''}
      <div class="card setup"><div class="ring"><b>${Math.min(100, (list.length ? 50 : 0) + (server.length ? 50 : 0))}%</b></div><div><b>Dica rápida</b><small>Toque em <b>Tirar fotos</b> (botão verde) em cada cômodo e marque as avarias com bolinhas.</small></div></div>
      <div class="sec-h"><b><${Icon} name="clipboard" size=${18} /> Últimas vistorias</b><a onClick=${() => go('/vistorias')}>Ver todas →</a></div>
      ${recent.length ? recent.map((i) => html`<${InsCard} key=${i.id} ins=${i} />`) : html`<${Empty} title="Nenhuma vistoria ainda" text="Toque em Nova Vistoria para começar." />`}
    </div>
    <${BottomNav} active="home" />
  </div>`;
}

const LSTATUS = { draft: ['Em andamento', 'gray'], queued: ['Aguardando envio', 'amber'], sent: ['Enviada', 'blue'] };
const SSTATUS = { rascunho: ['Em andamento', 'gray'], enviada: ['Recebida', 'blue'], em_revisao: ['Em revisão', 'amber'], aprovada: ['Aprovada', 'green'], em_assinatura: ['Em assinatura', 'purple'], assinada: ['Assinada', 'green'], cancelada: ['Cancelada', 'red'] };
function InsCard({ ins }) {
  const types = (app.boot && app.boot.types) || {};
  const p = ins.property || {};
  const [lab, col] = ins.remote ? SSTATUS[ins.status] || [ins.status, 'gray'] : ins.local_status === 'sent' && ins.server ? SSTATUS[ins.server.status] || LSTATUS.sent : LSTATUS[ins.local_status] || LSTATUS.draft;
  const open = () => (ins.remote ? go(`/s/${ins.id}`) : ins.local_status === 'sent' ? go(`/s/${ins.id}`) : go(`/v/${ins.id}/${ins.step || 0}`));
  const photos = ins.remote ? ins.photos : null;
  return html`<button class="ins-card fade-in" onClick=${open}>
    <span class="ic-type"><${Icon} name=${ins.type === 'saida' ? 'logout' : 'door'} size=${20} /></span>
    <div class="ic-body"><b>${p.identification || ins.address || [p.street, p.number].filter(Boolean).join(', ') || (ins.type ? (types[ins.type] || {}).label : 'Nova vistoria')}</b>
      <small>${(types[ins.type] || {}).label || 'Tipo não definido'} · ${ins.code ? `#${ins.code} · ` : ''}${new Date(ins.created_at).toLocaleDateString('pt-BR')}</small>
      <small class="muted">${ins.remote ? `${ins.rooms} cômodos · ${photos} fotos` : `${(ins.rooms || []).length} cômodos`}</small></div>
    <span class=${'pill ' + col}>${lab}</span>
  </button>`;
}

export function InspectionList() {
  const [list, setList] = useState([]);
  const [server, setServer] = useState([]);
  const [q, setQ] = useState('');
  const [tab, setTab] = useState('todas');
  useEffect(() => { inspections.all().then(setList); if (!DEMO && online()) api('/app/inspections').then(setServer).catch(() => {}); }, []);
  const local = list.filter((i) => i.local_status !== 'sent');
  const all = [...local, ...server.filter((s) => !local.some((l) => l.id === s.id)).map((s) => ({ ...s, remote: true })), ...(DEMO ? list.filter((i) => i.local_status === 'sent') : [])];
  const shown = all.filter((i) => (tab === 'aparelho' ? !i.remote && i.local_status !== 'sent' : tab === 'enviadas' ? i.remote || i.local_status === 'sent' : true))
    .filter((i) => !q || JSON.stringify([i.property, i.address, i.code, i.people]).toLowerCase().includes(q.toLowerCase()));
  return html`<div class="screen with-nav">
    <${TopBar} />
    <div class="content">
      <div class="search"><${Icon} name="search" size=${19} /><input placeholder="Buscar por endereço, código, inquilino…" value=${q} onInput=${(e) => setQ(e.target.value)} /></div>
      <div class="seg">${[['todas', 'Todas'], ['aparelho', 'No aparelho'], ['enviadas', 'Enviadas']].map(([k, l]) => html`<button class=${tab === k ? 'on' : ''} onClick=${() => setTab(k)}>${l}</button>`)}</div>
      ${shown.length ? shown.map((i) => html`<${InsCard} key=${i.id} ins=${i} />`) : html`<${Empty} title="Nenhuma vistoria encontrada" />`}
    </div>
    <button class="fab-pill pop" onClick=${newInspection}><${Icon} name="plus" size=${20} stroke=${2.6} /> Nova Vistoria</button>
    <${BottomNav} active="list" />
  </div>`;
}

// ---------------- Sincronização ----------------
export function SyncCenter() {
  const [list, setList] = useState([]);
  const [info, setInfo] = useState({});
  const [est, setEst] = useState(null);
  const [busy, setBusy] = useState(null);
  async function load() {
    const l = await inspections.all();
    const inf = {};
    for (const i of l) { const ms = await media.byInspection(i.id); inf[i.id] = { total: ms.length, pending: ms.filter((m) => !m.uploaded).length, bytes: ms.reduce((a, m) => a + ((m.blob && m.blob.size) || 0), 0) }; }
    setList(l); setInfo(inf); setEst(await storageEstimate());
  }
  useEffect(() => { load(); }, []);
  async function sync(id) {
    if (!online()) return toast('Sem internet no momento. Tentaremos automaticamente.', 'err');
    setBusy(id);
    try { await syncInspection(id, () => {}); toast('Sincronizado ✔'); } catch (e) { toast(e.message, 'err'); }
    setBusy(null); load();
  }
  async function cleanup(id) {
    if (!(await confirmDialog({ title: 'Liberar espaço?', text: 'As mídias já enviadas serão removidas deste aparelho. A vistoria continua salva no servidor.', ok: 'Liberar' }))) return;
    for (const m of await media.byInspection(id)) if (m.uploaded) await media.del(m.id);
    await inspections.del(id); load(); toast('Espaço liberado');
  }
  const mb = (b) => `${(b / 1048576).toFixed(1)} MB`;
  return html`<div class="screen with-nav">
    <${TopBar} title="Sincronização" />
    <div class="content">
      <div class=${'net-card ' + (online() ? 'on' : 'off')}><${Icon} name=${online() || DEMO ? 'cloud' : 'cloudOff'} size=${26} /><div><b>${online() || DEMO ? 'Conectado' : 'Sem conexão'}</b><small>${online() || DEMO ? 'Vistorias na fila sobem automaticamente.' : 'Continue trabalhando: tudo fica salvo no aparelho.'}</small></div></div>
      ${est && est.quota ? html`<div class="card"><div class="card-h"><${Icon} name="box" size=${18} /><b>Armazenamento do aparelho</b></div><div class="bar"><i style=${`width:${Math.max(2, (est.usage / est.quota) * 100)}%`}></i></div><small class="muted">${mb(est.usage)} usados de ${mb(est.quota)} disponíveis para o app</small></div>` : ''}
      <div class="sec-h"><b>No aparelho</b></div>
      ${list.length ? list.map((i) => { const f = info[i.id] || {}; const pend = DEMO ? (i.local_status === 'sent' ? 0 : 7) : f.pending;
        return html`<div class="card sync-row"><div class="sr-top"><b>${(i.property && (i.property.identification || [i.property.street, i.property.number].filter(Boolean).join(', '))) || 'Vistoria sem endereço'}</b><span class=${'pill ' + (pend ? 'amber' : 'green')}>${pend ? `${pend} pendente(s)` : 'Tudo enviado'}</span></div>
        <small class="muted">${(i.rooms || []).length} cômodos · ${DEMO ? 12 : f.total} mídias · ${mb(DEMO ? 18874368 : f.bytes || 0)} · ${i.local_status === 'queued' ? 'na fila de envio' : i.local_status === 'sent' ? 'enviada para aprovação' : 'rascunho'}</small>
        <div class="sr-actions"><button class="btn sm dark" disabled=${busy === i.id} onClick=${() => sync(i.id)}>${busy === i.id ? html`<span class="spin sm"></span> Enviando…` : html`<${Icon} name="sync" size=${16} /> Sincronizar agora`}</button>
        ${i.local_status === 'sent' && !pend ? html`<button class="btn sm ghost" onClick=${() => cleanup(i.id)}>Liberar espaço</button>` : html`<button class="btn sm ghost" onClick=${() => go(`/v/${i.id}/${i.step || 0}`)}>Abrir</button>`}</div></div>`; }) : html`<${Empty} icon="cloud" title="Nada pendente" text="Quando você fizer vistorias offline, elas aparecem aqui até serem enviadas." />`}
    </div>
    <${BottomNav} active="sync" />
  </div>`;
}

// ---------------- Suporte ----------------
const FAQ = [
  ['Consigo usar offline?', 'Sim. Depois do primeiro login, o app funciona sem internet. Fotos, áudios, vídeos e dados ficam salvos no aparelho e são enviados automaticamente quando a conexão voltar.'],
  ['Como faço para criar uma vistoria?', 'Toque em “Nova vistoria”, escolha a modalidade, adicione os cômodos, registre fotos e itens de cada cômodo, preencha os dados e envie para aprovação.'],
  ['Como marco uma avaria na foto?', 'Abra a foto e toque em “Marcar avaria”. Toque no ponto do defeito para colocar uma bolinha vermelha; arraste para ajustar. As bolinhas aparecem no laudo final.'],
  ['A gravação de áudio ou a foto não está funcionando', 'Verifique se o navegador tem permissão para câmera e microfone e se o endereço do sistema usa HTTPS. Sem permissão, use “Galeria” para anexar fotos.'],
  ['O sistema tem assinatura digital com validade jurídica?', 'Sim. Após a aprovação, o laudo é enviado para assinatura eletrônica pela ClickSign, com validade jurídica (MP 2.200-2/2001 e Lei 14.063/2020).'],
  ['Consigo comparar uma vistoria de entrada com a de saída?', 'Sim. O administrador gera a vistoria de saída a partir da de entrada e o laudo mostra o estado de cada item na entrada.'],
];
export function Support() {
  const [open, setOpen] = useState(-1);
  const [subject, setSubject] = useState('');
  const [msg, setMsg] = useState('');
  async function send() {
    if (!msg.trim()) return toast('Escreva sua mensagem', 'err');
    if (DEMO) return toast('Mensagem enviada ✔');
    try { await api('/support', { body: { subject, message: msg } }); toast('Mensagem enviada ✔'); setMsg(''); } catch (e) { toast(e.message, 'err'); }
  }
  return html`<div class="screen with-nav">
    <${TopBar} />
    <div class="content">
      <div class="help-hero fade-in"><span><${Icon} name="headset" size=${34} /></span><h2>Precisa de ajuda?</h2><p>Nossa equipe está pronta para te ajudar. Veja as dúvidas frequentes ou envie uma mensagem.</p></div>
      <a class="card contact" href="mailto:${(app.boot && app.boot.support_email) || 'contato@imobeasy.com'}"><span class="ct-ic dark"><${Icon} name="mail" size=${20} /></span><div><b>E-mail de suporte</b><small>${(app.boot && app.boot.support_email) || 'contato@imobeasy.com'}</small></div></a>
      <a class="card contact" href="https://wa.me/" target="_blank"><span class="ct-ic green"><${Icon} name="whatsapp" size=${20} /></span><div><b>Suporte via WhatsApp</b><small>Fale com a equipe</small></div><${Icon} name="right" size=${18} /></a>
      <div class="sec-h"><b><${Icon} name="info" size=${18} /> Perguntas frequentes</b></div>
      <div class="faq">${FAQ.map(([q, a], k) => html`<div class=${'faq-i' + (open === k ? ' on' : '')}><button onClick=${() => setOpen(open === k ? -1 : k)}><b>${q}</b><${Icon} name="down" size=${18} /></button><div class="faq-a"><p>${a}</p></div></div>`)}</div>
      <${Section} title="Envie uma mensagem"><p class="muted small">Preencha o formulário e nós cuidamos do resto.</p>
        <label class="flabel">Assunto</label><select class="input" value=${subject} onChange=${(e) => setSubject(e.target.value)}><option value="">Selecione o principal motivo</option><option>Dúvida de uso</option><option>Problema técnico</option><option>Sugestão</option><option>Financeiro</option></select>
        <label class="flabel">Como podemos ajudar?</label><textarea class="input" rows="5" value=${msg} onInput=${(e) => setMsg(e.target.value)} placeholder="Ex.: Tentei baixar as fotos do laudo #32 mas está acusando…"></textarea>
        <div class="info-box"><${Icon} name="info" size=${18} /><span>A resposta chegará no seu e-mail: <b>${app.user && app.user.email}</b></span></div>
        <button class="btn dark xl" onClick=${send}><${Icon} name="send" size=${18} /> ENVIAR MENSAGEM</button>
      </${Section}>
    </div>
    <${BottomNav} active="help" />
  </div>`;
}

export function Profile() {
  async function logout() {
    const pend = (await inspections.all()).filter((i) => i.local_status !== 'sent').length;
    if (!(await confirmDialog({ title: 'Sair da conta?', text: pend ? `Há ${pend} vistoria(s) não enviadas neste aparelho. Elas continuarão salvas aqui.` : 'Você poderá entrar novamente a qualquer momento.', ok: 'Sair', danger: true }))) return;
    await clearSession(); bus.emit({ type: 'logout' });
  }
  const u = app.user || {};
  return html`<div class="screen">
    <${TopBar} title="Meu perfil" onBack=${() => back('/home')} right=${html`<span class="tb-sp"></span>`} />
    <div class="content">
      <div class="profile pop"><span class="avatar xl">${(u.name || 'U')[0]}</span><b>${u.name}</b><small>${u.email}</small><span class="pill blue">${u.role === 'admin' ? 'Administrador' : 'Vistoriador'}</span></div>
      <div class="card list-menu">
        <button onClick=${() => go('/sync')}><${Icon} name="sync" size=${20} /> Sincronização e armazenamento <${Icon} name="right" size=${16} /></button>
        <button onClick=${() => go('/suporte')}><${Icon} name="headset" size=${20} /> Suporte <${Icon} name="right" size=${16} /></button>
        <button onClick=${() => go('/onboarding')}><${Icon} name="info" size=${20} /> Ver apresentação <${Icon} name="right" size=${16} /></button>
        <button class="danger" onClick=${logout}><${Icon} name="logout" size=${20} /> Sair</button>
      </div>
      <p class="muted center small">${(app.boot && app.boot.app_name) || 'Imob Easy Vistorias'} · ${(app.boot && app.boot.company && app.boot.company.name) || ''}</p>
    </div>
  </div>`;
}

// Vistoria já enviada (acompanhamento)
export function ServerDetail({ id }) {
  const [ins, setIns] = useState(null);
  const [remote, setRemote] = useState(null);
  useEffect(() => { inspections.get(id).then(setIns); if (!DEMO && online()) api('/app/inspections').then((l) => setRemote(l.find((x) => x.id === id))).catch(() => {}); }, [id]);
  const st = (remote && remote.status) || (ins && ins.server && ins.server.status) || 'enviada';
  const steps = [['enviada', 'Recebida pela imobiliária'], ['em_revisao', 'Em revisão'], ['aprovada', 'Aprovada · link público'], ['em_assinatura', 'Em assinatura (ClickSign)'], ['assinada', 'Assinada por todos']];
  const idx = steps.findIndex((s) => s[0] === st);
  const p = (ins && ins.property) || (remote && remote.property) || {};
  return html`<div class="screen">
    <${TopBar} title=${remote && remote.code ? `Vistoria #${remote.code}` : 'Vistoria enviada'} onBack=${() => back('/vistorias')} right=${html`<span class="tb-sp"></span>`} />
    <div class="content">
      <div class="card"><b>${p.identification || (remote && remote.address) || 'Imóvel'}</b><small class="muted">${(remote && remote.address) || [p.street, p.number, p.city].filter(Boolean).join(', ')}</small></div>
      <${Section} title="Andamento">
        <div class="timeline">${steps.map(([k, l], n) => html`<div class=${'tl' + (n <= idx ? ' done' : '') + (n === idx ? ' cur' : '')}><span>${n <= idx ? html`<${Icon} name="check" size=${14} stroke=${3} />` : n + 1}</span><b>${l}</b></div>`)}</div>
      </${Section}>
      ${remote && remote.public_token && html`<a class="btn green xl" href=${`/v/${remote.public_token}`} target="_blank"><${Icon} name="file" size=${18} /> Ver laudo público</a>`}
      ${ins && ins.local_status !== 'sent' && html`<button class="btn dark xl" onClick=${() => go(`/v/${id}/${ins.step || 0}`)}>Continuar vistoria</button>`}
    </div>
  </div>`;
}
