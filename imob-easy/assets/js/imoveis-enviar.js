/* ==========================================================================
   Imob Easy — a tela /imoveis: o corretor acha os imóveis e se envia pelo WhatsApp

   O desenho é o do arquivo Telaenviarmovel.html (Pedro, 02/10/2026): "vai ser um
   link /imoveis que vou mandar para os corretores acharem os imóveis e se
   enviarem pelo whatsapp... substitua as funções lá pelas nossas mantendo o
   visual". A página (imob-easy/imoveis.html) é GERADA do desenho por
   scripts/montar_pagina_de_enviar.py: a marcação e o CSS são os dele; este
   arquivo entra no lugar do script de exemplo.

   O que mudou do exemplo para o de verdade:
     - os imóveis vêm de GET /api/imoveis-para-enviar: só o que a Nay oferece
       (nosso, Disponível, no site, sem bloqueio). Sem rua, número ou andar;
     - o mapa ilustrativo virou o MESMO mapa do nosso painel (Leaflet + OpenStreetMap com
       fundo escuro, divisas e nomes dos bairros), um pino por ponto com o preço pequeno
       dentro. O ponto é a REGIÃO do imóvel (arredondado), não a porta;
     - "Ver" abre a página do imóvel (/imovel/<código>);
     - "Me envia" chama POST /api/me-envia: a Nay manda o card e as fotos, com os
       tetos e as paredes de sempre. A lista de selecionados e o número ficam no
       navegador, nas mesmas chaves da página do imóvel (uma lista só).
   ========================================================================== */
(function () {
"use strict";

const API = window.API_BASE || "https://api.imobeasy.online";
const MAX_POR_ENVIO = 10;                       // o mesmo teto de site_me_envia
const MANAUS = [-3.08, -60.02];
let IMOVEIS = [], carregou = false, falhou = false;

/* ===== utilidades ===== */
const $ = s => document.querySelector(s);
const esc = s => String(s == null ? "" : s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const i = n => `<i data-lucide="${n}"></i>`;
// só os <i> que ainda não viraram ícone: redesenhar todos os da página a cada clique era o que travava (05/10)
const drawIcons = raiz => {
  try {
    if (!window.lucide || !(raiz || document).querySelector("i[data-lucide]")) return;
    lucide.createIcons(raiz ? { root: raiz } : undefined);      // com `raiz`, só os ícones daquele pedaço
  } catch (e) { /* ícones são enfeite */ }
};
const norm = s => String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const brl = n => "R$ " + Number(n).toLocaleString("pt-BR");
const short = n => n >= 1e6 ? `R$ ${(n / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 2 })} mi`
  : n >= 1e4 ? `R$ ${Math.round(n / 1e3).toLocaleString("pt-BR")} mil`
  : `R$ ${(n / 1e3).toLocaleString("pt-BR", { maximumFractionDigits: 1 })} mil`;
/* as fotos moram no site antigo, que serve cada uma em vários tamanhos */
const foto = (m, tam) => m.foto ? m.foto.replace("/huge/", "/" + tam + "/") : SEM_FOTO;
const SEM_FOTO = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(
  '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300"><rect width="400" height="300" fill="#EDE6F7"/>' +
  '<g fill="none" stroke="#B9A5DC" stroke-width="10" stroke-linecap="round" stroke-linejoin="round">' +
  '<path d="M130 170 L200 105 L270 170"/><path d="M150 160 V215 H250 V160"/></g></svg>');
function toast(t) { const el = $("#toast"); el.textContent = t; el.classList.add("show"); clearTimeout(toast.t); toast.t = setTimeout(() => el.classList.remove("show"), 4200); }

/* ===== estado ===== */
const G = { neg: "venda", q: "" };
const preco = m => G.neg === "aluguel" ? m.aluguel : m.venda;
const priceTxt = m => G.neg === "aluguel" ? `${brl(m.aluguel)}<span>/mês</span>` : brl(m.venda);
const local = m => [m.condominio, m.bairro].filter(Boolean).join(" · ");
const newF = () => ({ loc: "", tipo: "", quartos: new Set(), vagas: new Set(), mob: new Set(), min: "", max: "" });
const FM = newF(), FS = FM;      // 06/10: um filtro só -- o de cima vale para o mapa e para a lista
let focusCode = null, popCode = null;
const SKEY = "imobeasy_lista_envio", PKEY = "imobeasy_whatsapp";
let sel = []; try { sel = JSON.parse(localStorage.getItem(SKEY) || "[]"); if (!Array.isArray(sel)) sel = []; } catch (e) { sel = []; }
const saveSel = () => { try { localStorage.setItem(SKEY, JSON.stringify(sel)); } catch (e) { /* navegador sem armazenamento */ } };
const isSel = c => sel.some(x => String(x.codigo) === String(c));
const achar = c => IMOVEIS.find(x => String(x.codigo) === String(c));

/* ===== filtros de mapa e lista ===== */
function matchQ(m) { if (!G.q) return true; const q = norm(G.q); return [m.codigo, m.condominio, m.bairro, m.titulo, m.tipo].some(v => norm(v).includes(q)); }
const numSel = (set, v) => !set.size || [...set].some(n => n === 4 ? v >= 4 : v === n);
const parseV = s => Number(String(s).replace(/\D/g, "")) || 0;
function matchF(m, F) {
  if (F.loc) { const [k, v] = F.loc.split("|"); if (k === "b" && m.bairro !== v) return false; if (k === "c" && m.condominio !== v) return false; }
  if (F.tipo && m.tipo !== F.tipo) return false;
  if (!numSel(F.quartos, m.quartos || 0) || !numSel(F.vagas, m.vagas || 0)) return false;
  if (F.mob.size && !F.mob.has(m.mobilia)) return false;      // 297: 'mobiliado' | 'semi'
  if (F.min && preco(m) < parseV(F.min)) return false;
  if (F.max && preco(m) > parseV(F.max)) return false;
  return true;
}
const base = () => IMOVEIS.filter(m => preco(m) > 0 && matchQ(m));
const fCount = F => (F.loc ? 1 : 0) + (F.tipo ? 1 : 0) + (F.quartos.size ? 1 : 0) + (F.vagas.size ? 1 : 0) + (F.mob.size ? 1 : 0) + (F.min || F.max ? 1 : 0);
function fbarHTML(id) {
  const bairros = [...new Set(IMOVEIS.map(m => m.bairro).filter(Boolean))].sort((a, b) => a.localeCompare(b, "pt-BR"));
  const condos = [...new Set(IMOVEIS.map(m => m.condominio).filter(Boolean))].sort((a, b) => a.localeCompare(b, "pt-BR"));
  const tipos = [...new Set(IMOVEIS.map(m => m.tipo).filter(Boolean))].sort((a, b) => a.localeCompare(b, "pt-BR"));
  const ch = k => [1, 2, 3, 4].map(n => `<button type="button" class="mchip" data-f="${id}" data-k="${k}" data-n="${n}" aria-pressed="false">${n === 4 ? "4+" : n}</button>`).join("");
  return `<div class="fbar" role="group" aria-label="Filtros ${id === "m" ? "do mapa" : "da lista"}">
    <label class="fs grow"><small>Bairro/Condomínio</small><select data-f="${id}" data-k="loc"><option value="">Todos</option><optgroup label="Bairros">${bairros.map(b => `<option value="b|${esc(b)}">${esc(b)}</option>`).join("")}</optgroup><optgroup label="Condomínios">${condos.map(c => `<option value="c|${esc(c)}">${esc(c)}</option>`).join("")}</optgroup></select></label>
    <label class="fs"><small>Tipo de imóvel</small><select data-f="${id}" data-k="tipo"><option value="">Todos</option>${tipos.map(t => `<option>${esc(t)}</option>`).join("")}</select></label>
    <div class="fs"><small>Quartos</small><div class="mchips">${ch("quartos")}</div></div>
    <div class="fs"><small>Garagem</small><div class="mchips">${ch("vagas")}</div></div>
    <div class="fs"><small>Valor</small><div class="val"><input data-f="${id}" data-k="min" inputmode="numeric" placeholder="De" aria-label="Valor mínimo">–<input data-f="${id}" data-k="max" inputmode="numeric" placeholder="Até" aria-label="Valor máximo"></div></div>
    <button type="button" class="fclr" data-clear="${id}" aria-label="Limpar filtros">${i("rotate-ccw")}</button>
  </div>`;
}
function syncF(id, F) {
  syncH();
  ["#mapF", "#sheetF", "#listF"].forEach(s => {
    const root = $(s); if (!root || !root.firstElementChild) return;
    root.querySelector('[data-k="loc"]').value = F.loc; root.querySelector('[data-k="tipo"]').value = F.tipo;
    root.querySelector('[data-k="min"]').value = F.min; root.querySelector('[data-k="max"]').value = F.max;
    root.querySelectorAll(".mchip").forEach(c => c.setAttribute("aria-pressed", F[c.dataset.k].has(+c.dataset.n)));
    root.querySelector(".fclr").classList.toggle("on", fCount(F) > 0);
  });
}
const resetF = F => { F.loc = ""; F.tipo = ""; F.quartos.clear(); F.vagas.clear(); F.mob.clear(); F.min = ""; F.max = ""; };

/* ===== O FILTRO ÚNICO, FIXO EMBAIXO DO MENU (Pedro, 06/10) =====
   "quero esse filtro que tem na home ... põe o venda e locação clicável em cima da barra de pesquisa, e troca o
   garagem por Mobiliado ou semimobiliado"; "deixa só um filtro"; "põe fixo embaixo do menu". É o desenho da
   busca da home: Bairro/Condomínio (a lista desce e filtra pelas iniciais; número acha pelo código), tipo em
   botões (os principais e o resto no "+"), quartos, mobília e valor. Vale para o mapa E para a lista. */
const TIPOS_PRINCIPAIS = ["Apartamento", "Casa", "Casa de condomínio"];
let hMais = false;
const ptBR = (a, b) => a.localeCompare(b, "pt-BR");
function painelHTML() {
  const ch = [1, 2, 3, 4].map(n => `<button type="button" class="mchip hchip" data-f="m" data-k="quartos" data-n="${n}" aria-pressed="false">${n === 4 ? "4+" : n}</button>`).join("");
  const e = x => `<span class="emo" aria-hidden="true">${x}</span>`;
  /* CELULAR, ESTILO APLICATIVO (Pedro, 06/10: "quero que fique o menor possível lá em cima ... quando clica ali
     abre os filtros todos listados bonitinho até com emoji"): em cima só a pílula com o resumo (.hmini); tocar
     abre a tela de filtros (.hfull). No computador a pílula não existe e o painel fica sempre aberto. */
  return `<div class="hmini"><button type="button" class="hpill" data-habrir aria-label="Abrir os filtros">${i("search")}<span><b id="hpT"></b><small id="hpS"></small></span></button><button type="button" class="hpfil" data-habrir aria-label="Filtros">${i("sliders-horizontal")}<span class="bd" id="hfilBd"></span></button></div>
  <div class="hfull" id="hfull">
    <div class="hfull-h"><b>Filtros</b><button type="button" data-hfechar aria-label="Fechar os filtros">${i("x")}</button></div>
    <div class="hfull-b">
      <div class="hneg"><div class="seg" role="group" aria-label="Venda ou locação"><button type="button" data-neg="venda" aria-pressed="${G.neg === "venda"}">Venda</button><button type="button" data-neg="aluguel" aria-pressed="${G.neg === "aluguel"}">Locação</button></div><button type="button" class="hclr" data-clear="m" hidden>Limpar filtros</button></div>
      <div class="hp" id="hp">
        <div class="hp-r hp-r1">
          <div class="hp-c"><small>${e("📍")}Bairro/Condomínio</small><div class="hloc"><input class="hp-in" id="hloc" type="text" autocomplete="off" placeholder="Selecione o Bairro/Condomínio" aria-label="Bairro, condomínio ou código"><div class="hlist" id="hlist" role="listbox"></div></div></div>
          <div class="hp-c"><small>${e("🏠")}Tipo de Imóvel</small><div class="hchips" id="htipos"></div></div>
        </div>
        <div class="hp-r hp-r2">
          <div class="hp-c"><small>${e("🛏️")}Quartos</small><div class="hchips">${ch}</div></div>
          <div class="hp-c"><small>${e("🛋️")}Mobília</small><div class="hchips"><button type="button" class="hchip" data-mob="mobiliado" aria-pressed="false">Mobiliado</button><button type="button" class="hchip" data-mob="semi" aria-pressed="false">Semimobiliado</button></div></div>
          <div class="hp-c"><small>${e("💰")}Valor</small><div class="hval"><input class="hp-in" data-f="m" data-k="min" inputmode="numeric" placeholder="De" aria-label="Valor mínimo"><input class="hp-in" data-f="m" data-k="max" inputmode="numeric" placeholder="Até" aria-label="Valor máximo"></div></div>
        </div>
      </div>
    </div>
    <div class="hfull-f"><button type="button" class="hlimpa" data-clear="m">Limpar</button><button type="button" class="hver" data-hfechar id="hver">Ver imóveis</button></div>
  </div>`;
}
/* o resumo da pílula: "Apartamento à venda em Ponta Negra" / "2 e 3 quartos · Mobiliado · até R$ 500.000 · 12 imóveis" */
function resumoH() {
  const T = $("#hpT"); if (!T) return;
  const n = carregou ? listItems().length : null;
  const onde = FM.loc ? FM.loc.split("|")[1] : "Manaus";
  T.textContent = `${FM.tipo || "Imóveis"} ${G.neg === "aluguel" ? "para alugar" : "à venda"} em ${onde}`;
  const partes = [];
  if (FM.tipo) partes.push(FM.tipo);
  if (FM.loc) partes.push(onde);
  if (FM.quartos.size) { const q = [...FM.quartos].sort().map(x => x === 4 ? "4+" : x); partes.push(q.join(", ") + (q.length === 1 && q[0] === 1 ? " quarto" : " quartos")); }
  if (FM.mob.size) partes.push([...FM.mob].map(x => x === "semi" ? "Semimobiliado" : "Mobiliado").join(" ou "));
  if (FM.min || FM.max) partes.push(FM.min && FM.max ? `R$ ${FM.min} a ${FM.max}` : FM.min ? `a partir de R$ ${FM.min}` : `até R$ ${FM.max}`);
  const quantos = n == null ? "" : `${n} ${n === 1 ? "imóvel" : "imóveis"}`;
  $("#hpS").textContent = (partes.length ? partes : ["Toque para filtrar"]).concat(quantos ? [quantos] : []).join(" · ");
  const bd = $("#hfilBd"); if (bd) { bd.textContent = fCount(FM); bd.classList.toggle("on", fCount(FM) > 0); }
  const ver = $("#hver"); if (ver) ver.textContent = n == null ? "Ver imóveis" : n ? `Ver ${quantos}` : "Nenhum imóvel com esses filtros";
  const limpa = document.querySelector(".hlimpa"); if (limpa) limpa.disabled = !fCount(FM);
}
function abrirFiltros(on) {
  const hbar = $("#hbar"); if (!hbar) return;
  hbar.classList.toggle("aberto", on);
  document.documentElement.classList.toggle("hmodal", on);
  if (!on) { fecharLocais(); measure(); }
}
function pintarTiposH() {
  const el = $("#htipos"); if (!el) return;
  const nomes = [...new Set(IMOVEIS.filter(m => preco(m) > 0).map(m => m.tipo).filter(Boolean))];
  if (FM.tipo && !nomes.includes(FM.tipo)) nomes.push(FM.tipo);
  const frente = TIPOS_PRINCIPAIS.filter(x => nomes.includes(x)), resto = nomes.filter(x => !frente.includes(x)).sort(ptBR);
  if (FM.tipo && resto.includes(FM.tipo)) hMais = true;      // o escolhido está no resto: já vem aberto
  const b = x => `<button type="button" class="hchip" data-htipo="${esc(x)}" aria-pressed="${FM.tipo === x}">${esc(x)}</button>`;
  el.innerHTML = frente.map(b).join("") + (resto.length ? `<button type="button" class="hchip" data-hmais aria-expanded="${hMais}" title="Mais tipos">${hMais ? "−" : "+"}</button>` : "") + (hMais ? resto.map(b).join("") : "");
}
function syncH() {
  const hp = $("#hp"); if (!hp) return;
  pintarTiposH();
  hp.querySelectorAll(".mchip").forEach(c => c.setAttribute("aria-pressed", FM.quartos.has(+c.dataset.n)));
  hp.querySelectorAll("[data-mob]").forEach(c => c.setAttribute("aria-pressed", FM.mob.has(c.dataset.mob)));
  hp.querySelectorAll("input[data-k]").forEach(c => { if (c !== document.activeElement) c.value = FM[c.dataset.k]; });
  const loc = $("#hloc"); if (loc !== document.activeElement) loc.value = FM.loc ? FM.loc.split("|")[1] : "";
  const limpar = document.querySelector(".hclr"); if (limpar) limpar.hidden = !fCount(FM);
  resumoH();
}
function pintarLocais() {
  const box = $("#hlist"), q = norm($("#hloc").value.trim());
  const doNeg = IMOVEIS.filter(m => preco(m) > 0);
  const conta = campo => { const c = new Map(); doNeg.forEach(m => { if (m[campo]) c.set(m[campo], (c.get(m[campo]) || 0) + 1); }); return c; };
  // primeiro quem COMEÇA com o que foi digitado, depois quem tem uma palavra começando assim
  const acha = c => { const todos = [...c.keys()].sort(ptBR); return todos.filter(n => !q || norm(n).startsWith(q)).concat(todos.filter(n => q && !norm(n).startsWith(q) && (" " + norm(n)).includes(" " + q))); };
  const bs = conta("bairro"), cs = conta("condominio");
  const item = (k, n, c) => `<button type="button" data-hloc="${k}|${esc(n)}" role="option"><span>${esc(n)}</span><small>${c} ${c === 1 ? "imóvel" : "imóveis"}</small></button>`;
  let html = "";
  if (/^\d+$/.test(q)) html += IMOVEIS.filter(m => String(m.codigo).startsWith(q)).slice(0, 6).map(m => `<button type="button" data-go="${m.codigo}" role="option"><span>Cód. ${m.codigo} · ${esc(m.titulo)}</span></button>`).join("");
  const lb = acha(bs), lc = acha(cs);
  if (lb.length) html += `<div class="g">Bairros</div>` + lb.map(n => item("b", n, bs.get(n))).join("");
  if (lc.length) html += `<div class="g">Condomínios</div>` + lc.map(n => item("c", n, cs.get(n))).join("");
  box.innerHTML = html || `<div class="g">Nada com esse nome em ${G.neg === "venda" ? "Venda" : "Locação"}</div>`;
  box.classList.add("open");
}
const fecharLocais = () => { const b = $("#hlist"); if (b) b.classList.remove("open"); };
document.addEventListener("focusin", e => { if (e.target.id === "hloc") pintarLocais(); });
document.addEventListener("input", e => {
  if (e.target.id !== "hloc") return;
  if (!e.target.value.trim() && FM.loc) { FM.loc = ""; renderAll(); fit(); }
  pintarLocais();
});
document.addEventListener("keydown", e => {
  if (e.target.id !== "hloc") return;
  if (e.key === "Escape") fecharLocais();
  if (e.key === "Enter") { e.preventDefault(); const primeiro = document.querySelector("#hlist.open button"); if (primeiro) primeiro.click(); }
});
document.addEventListener("click", e => {
  if (!e.target.closest(".hloc")) fecharLocais();
  if (e.target.id === "hbar") { abrirFiltros(false); return; }      // tocou no escuro, fora do popup
  const t = e.target.closest("button"); if (!t) return;
  if (t.dataset.hloc) { FM.loc = t.dataset.hloc; fecharLocais(); $("#hloc").blur(); renderAll(); fit(); }
  if (t.dataset.go && t.closest("#hlist")) { fecharLocais(); $("#hloc").blur(); }
  if (t.dataset.htipo) { FM.tipo = FM.tipo === t.dataset.htipo ? "" : t.dataset.htipo; renderAll(); fit(); }
  if (t.hasAttribute("data-hmais")) { hMais = !hMais; syncH(); measure(); }
  if (t.hasAttribute("data-habrir")) abrirFiltros(true);
  if (t.hasAttribute("data-hfechar")) abrirFiltros(false);
  if (t.dataset.go && t.closest("#hlist")) abrirFiltros(false);      // foi direto a um imóvel pelo código
  if (t.dataset.mob) { FM.mob.has(t.dataset.mob) ? FM.mob.delete(t.dataset.mob) : FM.mob.add(t.dataset.mob); renderAll(); fit(); }
});

/* ===== o mapa: o MESMO do nosso painel =====
   Pedro, 02/10/2026: "esse mapa tá estranho, não é o mesmo mapa nosso, que deve ser aberto como tema escuro
   de início; pode ter o preço, mas pequeno". É o mapa da aba Mapa do admin (imoveis-ux.js): OpenStreetMap com
   o filtro escuro, as divisas e os nomes dos bairros, e UM pino por ponto. O preço vai dentro do pino, pequeno
   e de tamanho fixo (não cresce com a tela nem com o zoom); vários imóveis no mesmo ponto mostram o menor
   preço e "+N", e o balão lista todos. A rodinha rola a PÁGINA (a lista fica embaixo do mapa); Ctrl + rodinha,
   os botões ou dois dedos aproximam o mapa. */
const mapEl = $("#map"), world = $("#world");
const toque = matchMedia("(pointer:coarse)").matches;
const TKEY = "imobeasy_mapa_tema";
let mapa = null, camada = null, camadaBairros = null, camadaRotulos = null;
let tema = "escuro"; try { tema = localStorage.getItem(TKEY) === "cinza" ? "cinza" : "escuro"; } catch (e) { /* sem armazenamento */ }
const corDoTema = () => tema === "escuro" ? "#c4b5fd" : "#6d28d9";
function aplicarTema() {
  world.classList.toggle("mapa--escuro", tema === "escuro");
  world.classList.toggle("mapa--cinza", tema !== "escuro");
  if (camadaBairros) camadaBairros.eachLayer(l => { if (l.setStyle) l.setStyle({ color: corDoTema(), fillColor: corDoTema() }); });
  const b = $("#ztema");
  if (b) { b.innerHTML = i(tema === "escuro" ? "sun" : "moon"); b.setAttribute("aria-label", tema === "escuro" ? "Mapa claro" : "Mapa escuro"); drawIcons(); }
}
function mostrarRotulos() {
  if (!mapa) return;
  if (mapa.getZoom() >= 13) camadaRotulos.addTo(mapa); else mapa.removeLayer(camadaRotulos);
}
function carregarBairros() {
  fetch(API + "/api/mapa/bairros")
    .then(r => r.ok ? r.json() : [])
    .then(bs => {
      bs.forEach(b => {
        if (b.poligono) {
          L.geoJSON(b.poligono, { interactive: false, style: { color: corDoTema(), weight: 1.2, opacity: .6, fillColor: corDoTema(), fillOpacity: .04 } }).addTo(camadaBairros);
        }
        L.tooltip({ permanent: true, direction: "center", className: "ux-rotulo-bairro", interactive: false, pane: "rotulosBairro" })
          .setLatLng([b.lat, b.lon]).setContent(esc(b.bairro)).addTo(camadaRotulos);
      });
      mostrarRotulos();
    })
    .catch(() => { /* sem as divisas o mapa continua servindo */ });
}
function criarMapa() {
  if (mapa || !window.L) return;
  /* 06/10 (Pedro): "quando eu clique dentro do mapa e arraste, ele mexa o mapa e não a tela" -- no celular
     um dedo dentro do mapa arrasta o MAPA (dois dão zoom); a página rola por fora dele.
     No computador a rodinha dá zoom (Pedro, 06/10: sem a barra, o PC tinha ficado sem zoom nenhum). */
  mapa = L.map(world, { zoomControl: false, dragging: true, tap: false, scrollWheelZoom: !toque, minZoom: 10 }).setView(MANAUS, 12);
  L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", { maxZoom: 19, subdomains: "abc", attribution: "&copy; OpenStreetMap" }).addTo(mapa);
  mapa.attributionControl.setPrefix(false).setPosition("bottomleft");
  camadaBairros = L.layerGroup().addTo(mapa);
  mapa.createPane("rotulosBairro");                      // os nomes dos bairros ficam ABAIXO dos pinos
  mapa.getPane("rotulosBairro").style.zIndex = 450;
  mapa.getPane("rotulosBairro").style.pointerEvents = "none";
  camadaRotulos = L.layerGroup();
  camada = L.layerGroup().addTo(mapa);
  mapa.on("click", () => { closePopup(); ativarMapa(true); });
  mapa.on("zoomend", mostrarRotulos);
  /* o pino do preço segue o zoom: 40% com a cidade inteira na tela (os nomes dos bairros aparecem), normal de perto */
  const escalaDosPinos = () => {
    const z = mapa.getZoom();
    const f = z >= 16 ? 1.3 : z >= 15 ? 1.04 : z >= 14 ? 0.85 : z >= 13 ? 0.65 : 0.52;      // +30% sobre o de antes (05/10)
    mapa.getContainer().style.setProperty("--pin-escala", f);
  };
  mapa.on("zoomend", escalaDosPinos);
  escalaDosPinos();
  /* A RODINHA É SEMPRE DA PÁGINA (Pedro, 05/10: "ainda está dando zoom pelo scroll, sendo que pedi para trocar
     isso pela barra que aumenta ou diminui o zoom lateralmente"). Nenhum zoom pela rodinha, nem com Ctrl, nem
     depois de clicar no mapa. No computador o zoom é a barra deitada; no celular, a pinça de dois dedos. */
  const barra = document.querySelector("#zbar");
  if (barra) {
    barra.min = 10; barra.max = 19; barra.step = 1; barra.value = mapa.getZoom();
    barra.addEventListener("input", () => mapa.setZoom(Number(barra.value)));
    mapa.on("zoomend", () => { barra.value = mapa.getZoom(); });
    const caixa = barra.closest(".zbar");
    if (caixa) { L.DomEvent.disableClickPropagation(caixa); L.DomEvent.disableScrollPropagation(caixa); }
  }
  const z = document.querySelector(".zoom");
  if (z && !$("#ztema")) z.insertAdjacentHTML("beforeend", '<button id="ztema" type="button"></button>');
  aplicarTema();
  carregarBairros();
}

/* um pino por PONTO: imóveis do mesmo condomínio caem no mesmo lugar */
function lugares(list) {
  const por = new Map();
  list.forEach(m => {
    if (m.lat == null || m.lon == null) return;
    const k = m.lat + "|" + m.lon;
    if (!por.has(k)) por.set(k, { lat: m.lat, lon: m.lon, ims: [] });
    por.get(k).ims.push(m);
  });
  const saida = [...por.values()];
  saida.forEach(g => g.ims.sort((a, b) => preco(a) - preco(b)));
  return saida;
}
let pontos = [];
const lugarDe = c => pontos.find(g => g.ims.some(m => String(m.codigo) === String(c)));
/* o preço dentro do pino: curto ("480 mil", "1,2 mi", "2,7 mil") */
const curto = n => n >= 1e6 ? (n / 1e6).toLocaleString("pt-BR", { maximumFractionDigits: 2 }) + " mi"
  : n >= 1e4 ? Math.round(n / 1e3).toLocaleString("pt-BR") + " mil"
  : (n / 1e3).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " mil";

function viewArea() { return { top: ($("#mtop") ? $("#mtop").offsetHeight : 0) + 26, lado: 46 }; }
function fit() {
  if (!mapa) return;
  mapa.invalidateSize();
  const pts = lugares(base().filter(m => matchF(m, FM)));
  if (!pts.length) { mapa.setView(MANAUS, 12); return; }
  const v = viewArea();
  mapa.fitBounds(L.latLngBounds(pts.map(p => [p.lat, p.lon])), { paddingTopLeft: [v.lado, v.top + 30], paddingBottomRight: [v.lado, 30], maxZoom: 15, animate: false });
  if (mapa.getZoom() < 12) mapa.setZoom(12, { animate: false });      // nunca mais longe que a cidade
}
function centerOn(m) {
  if (!mapa || m.lat == null) return;
  mapa.setView([m.lat, m.lon], Math.max(mapa.getZoom(), 15), { animate: false });
  // o balão abre para cima do pino: o pino desce para o balão caber abaixo dos filtros
  mapa.panBy([0, -Math.round(mapEl.clientHeight * 0.3)], { animate: false });
}

/* NO COMPUTADOR, CLICAR NUM IMÓVEL CENTRALIZA NO CARD DELE (Pedro, 06/10). O card abre para cima do pino: o
   pino vai para o meio na horizontal e um pouco abaixo do meio na vertical, e o card fica inteiro à vista. */
function centralizarNoCard(code) {
  const g = mapa && !toque && lugarDe(code); if (!g) return;
  const ponto = mapa.latLngToContainerPoint([g.lat, g.lon]);
  const alto = mapEl.clientHeight, card = g.ims.length > 1 ? 330 : 250;
  const alvoY = Math.min(alto - 30, Math.max(alto / 2 + card / 2, card + 50));
  mapa.panBy([Math.round(ponto.x - mapEl.clientWidth / 2), Math.round(ponto.y - alvoY)], { animate: true, duration: .35 });
}

/* ===== pinos e balão ===== */
const pickBtn = (m, full) => `<button class="pick" data-pick="${m.codigo}" aria-pressed="${isSel(m.codigo)}"${full ? ' style="width:100%"' : ""}>${isSel(m.codigo) ? i("circle-check") + "Selecionado" : i("circle-plus") + "Selecionar"}</button>`;
function pinHTML(g) {
  const sel = g.ims.some(m => isSel(m.codigo)), foco = g.ims.some(m => String(m.codigo) === String(focusCode));
  const menor = g.ims[0], n = g.ims.length;
  return `<button class="ux-preco-pin${sel ? " sel" : ""}${foco ? " focus" : ""}" data-pin="${menor.codigo}" aria-label="${esc(n === 1 ? menor.titulo : n + " imóveis neste ponto")}, a partir de ${esc(short(preco(menor)))}">${curto(preco(menor))}${n > 1 ? `<i>+${n - 1}</i>` : ""}</button>`;
}
function balaoHTML(g) {
  const fechar = `<button class="x" data-closepop aria-label="Fechar">${i("x")}</button>`;
  if (g.ims.length === 1) {
    const pm = g.ims[0];
    return `<div class="popup">${fechar}<img src="${esc(foto(pm, "large"))}" alt=""><div class="pb"><b>${esc(pm.titulo)}</b><small>${esc(local(pm))} · Cód. ${pm.codigo}</small><div class="pp">${priceTxt(pm)}</div><div style="display:flex;gap:6px"><button class="vbtn" data-ver="${pm.codigo}">${i("eye")}Ver</button>${pickBtn(pm, true)}</div></div></div>`;
  }
  const nomes = [...new Set(g.ims.map(m => m.condominio || ""))];
  const titulo = nomes.length === 1 && nomes[0] ? nomes[0] : "Vários imóveis neste ponto";
  return `<div class="popup popup--lugar">${fechar}<div class="pb"><b>${esc(titulo)}</b><small>${g.ims.length} imóveis · ${esc(g.ims[0].bairro || "Manaus")}</small><div class="pl-lista">${g.ims.map(m =>
    `<div class="pl${String(m.codigo) === String(focusCode) ? " focus" : ""}"><img src="${esc(foto(m, "small"))}" alt=""><span><b>${priceTxt(m)}</b><small>${esc([m.tipo, m.quartos ? m.quartos + (m.quartos === 1 ? " quarto" : " quartos") : "", "Cód. " + m.codigo].filter(Boolean).join(" · "))}</small></span><button class="vbtn" data-ver="${m.codigo}" aria-label="Ver o imóvel ${m.codigo}">${i("eye")}</button><button class="pick" data-pick="${m.codigo}" aria-pressed="${isSel(m.codigo)}" aria-label="${isSel(m.codigo) ? "Tirar" : "Selecionar"} o imóvel ${m.codigo}">${i(isSel(m.codigo) ? "circle-check" : "circle-plus")}</button></div>`).join("")}</div></div></div>`;
}
function renderMap() {
  const list = base().filter(m => matchF(m, FM));
  pontos = lugares(list);
  const noMapa = pontos.reduce((s, g) => s + g.ims.length, 0), sem = list.length - noMapa;
  $("#mapCount").textContent = !carregou ? "" : `${noMapa} ${noMapa === 1 ? "imóvel" : "imóveis"} no mapa` + (sem ? ` · ${sem} sem ponto no mapa (estão na lista)` : "");
  if (!mapa) return;
  camada.clearLayers();
  pontos.forEach(g => {
    const foco = g.ims.some(m => String(m.codigo) === String(focusCode)), sel = g.ims.some(m => isSel(m.codigo));
    L.marker([g.lat, g.lon], { zIndexOffset: foco ? 900 : sel ? 500 : 0, keyboard: false,
      icon: L.divIcon({ className: "pinw", iconSize: null, html: pinHTML(g) }) }).addTo(camada);
  });
  const aberto = popCode && lugarDe(popCode);
  if (aberto) {
    L.marker([aberto.lat, aberto.lon], { zIndexOffset: 5000, keyboard: false,
      icon: L.divIcon({ className: "pinw", iconSize: null, html: balaoHTML(aberto) }) }).addTo(camada);
  }
}
function closePopup() { if (popCode) { popCode = null; renderMap(); drawIcons(); } }

/* ===== lista embaixo do mapa ===== */
const listItems = () => base().filter(m => matchF(m, FS));
function renderList() {
  const list = listItems();
  const botaoDaLista = $("#listbtnTxt");      // o botão "Ver lista" saiu do painel fixo em 05/10
  if (botaoDaLista) botaoDaLista.textContent = carregou ? `Ver lista: ${list.length} ${list.length === 1 ? "imóvel" : "imóveis"}` : "Ver lista de imóveis";
  $("#resCount").textContent = carregou ? `${list.length} ${list.length === 1 ? "encontrado" : "encontrados"} · toque no imóvel para selecionar` : "";
  if (!carregou) {
    $("#list").innerHTML = `<div class="empty">${falhou ? 'Não consegui carregar os imóveis agora. <button class="vbtn" data-de-novo>Tentar de novo</button>' : "Carregando os imóveis…"}</div>`;
    return;
  }
  $("#list").innerHTML = list.length ? list.map(m => `<article class="row${isSel(m.codigo) ? " sel" : ""}${String(m.codigo) === String(focusCode) ? " focus" : ""}" id="row-${m.codigo}" data-row="${m.codigo}" role="button" tabindex="0" aria-pressed="${isSel(m.codigo)}">
    <div class="ph"><img src="${esc(foto(m, "medium"))}" alt="" loading="lazy"><span class="ck">${i("check")}</span></div>
    <div class="ri"><div class="tg">${esc(m.tipo)} · ${G.neg === "aluguel" ? "Aluguel" : "Venda"}</div><div class="t">${esc(m.titulo)}</div><div class="lc">${esc(local(m))} · Cód. ${m.codigo}</div>
      <div class="sp">${m.quartos ? `<span>${i("bed-double")}<b>${m.quartos}</b> ${m.quartos === 1 ? "quarto" : "quartos"}</span>` : ""}${m.vagas ? `<span>${i("car")}<b>${m.vagas}</b> ${m.vagas === 1 ? "vaga" : "vagas"}</span>` : ""}${m.area ? `<span>${i("ruler")}<b>${m.area}</b> m²</span>` : ""}</div></div>
    <div class="rr"><div class="pr">${priceTxt(m)}</div><div class="btns"><button class="vbtn" data-ver="${m.codigo}">${i("eye")}Ver</button>${pickBtn(m)}</div></div>
  </article>`).join("") : `<div class="empty">Nenhum imóvel com esses filtros em ${G.neg === "venda" ? "Comprar" : "Alugar"}.</div>`;
}

/* ===== menu fixo: só os selecionados ===== */
let enviando = false;
function renderSel() {
  const n = sel.length;
  $("#nSel").textContent = n; $("#nSel").classList.toggle("z", !n);
  $("#clearAll").hidden = !n;
  // só aparece quando ele seleciona o primeiro (Pedro, 02/10: "não precisa mostrar de início")
  document.querySelector(".sel-h").hidden = !n; $("#selList").hidden = !n;
  $("#selList").innerHTML = n ? sel.slice().reverse().map(x => `<div class="it"><img src="${esc(x.foto || SEM_FOTO)}" alt=""><b>${esc(x.titulo)}</b><small>${esc(x.sub)}</small><small>Cód. ${esc(x.codigo)}</small><button class="rm" data-rm="${esc(x.codigo)}" aria-label="Tirar da lista">${i("trash-2")}</button></div>`).join("")
    : `<p class="sel-empty">Nenhum ainda. Toque num imóvel do mapa ou da lista para selecionar.</p>`;
  $("#ftogBd").textContent = fCount(FS); $("#ftogBd").classList.toggle("on", fCount(FS) > 0);
  $("#sendTxt").innerHTML = enviando ? "Enviando…" : n ? `Me envia <span class="lbl-long">${n === 1 ? "o imóvel" : `os ${n}`}</span>` : "Me envia";
  // 06/10 (Pedro): o Enviar fica ao lado do WhatsApp, apagado, e libera quando o número está preenchido
  $("#send").hidden = false;
  $("#send").disabled = enviando || digits(phone).length < 10;
}

/* ===== busca (sincronizada) ===== */
let hl = -1, sugOpen = false;
function renderSugs() {
  const box = $("#sugs");
  if (!G.q || !sugOpen) { box.classList.remove("open"); return; }
  const res = base();
  box.innerHTML = `<div class="sug-seg"><small>${res.length} ${res.length === 1 ? "resultado" : "resultados"}</small><div class="seg" role="group" aria-label="Comprar ou alugar"><button data-neg="venda" aria-pressed="true">Comprar</button><button data-neg="aluguel" aria-pressed="false">Alugar</button></div></div>` + (res.length ? res.slice(0, 5).map((m, k) => `<button class="sug${k === hl ? " hl" : ""}" data-go="${m.codigo}" role="option"><img src="${esc(foto(m, "small"))}" alt=""><span><b>${esc(m.titulo)}</b><small>${esc(local(m))} · Cód. ${m.codigo}</small></span><span class="pr">${short(preco(m))}</span></button>`).join("")
    : `<div class="none">Nada encontrado para “${esc(G.q)}” em ${G.neg === "venda" ? "Comprar" : "Alugar"}.</div>`);
  box.querySelectorAll("[data-neg]").forEach(b => b.setAttribute("aria-pressed", b.dataset.neg === G.neg));
  box.classList.add("open");
}
function setQ(v, src) {
  G.q = v.trim(); hl = -1; focusCode = null; popCode = null;
  document.querySelectorAll("[data-q]").forEach(el => { if (el !== src) el.value = v; });
  document.querySelectorAll("[data-sbox]").forEach(b => b.classList.toggle("has", !!v));
  renderAll(); renderSugs(); fit();
}
function goTo(code) {
  const m = achar(code); if (!m) return;
  if (!(preco(m) > 0)) {      // o imóvel é do outro negócio (pedido por link): troca Comprar/Alugar
    G.neg = m.aluguel > 0 ? "aluguel" : "venda";
    document.querySelectorAll("[data-neg]").forEach(b => b.setAttribute("aria-pressed", b.dataset.neg === G.neg));
  }
  sugOpen = false; $("#sugs").classList.remove("open"); $("#q").blur();
  focusCode = m.codigo; popCode = m.lat != null ? m.codigo : null;
  if (!matchF(m, FM)) resetF(FM);
  renderAll();
  if (m.lat != null) centerOn(m);
  else { const linha = document.getElementById("row-" + m.codigo); if (linha) linha.scrollIntoView({ behavior: "smooth", block: "center" }); }
}

/* ===== seleção, um por um ===== */
const digits = s => String(s || "").replace(/\D/g, "").slice(0, 11);
function fmt(s) { const d = digits(s); if (!d) return ""; if (d.length <= 2) return `(${d}`; if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`; if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`; return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`; }
let phone = ""; try { phone = localStorage.getItem(PKEY) || ""; } catch (e) { /* idem */ }
function togglePick(code) {
  const m = achar(code); if (!m) return;
  const was = isSel(code);
  if (!was && sel.length >= MAX_POR_ENVIO) { toast(`Dá para se enviar até ${MAX_POR_ENVIO} imóveis de cada vez. Envie esses e escolha os próximos.`); return; }
  if (was) sel = sel.filter(x => String(x.codigo) !== String(code));
  else sel.push({ codigo: m.codigo, titulo: m.titulo, sub: `${m.bairro || "Manaus"} · ${brl(preco(m))}${G.neg === "aluguel" ? "/mês" : ""}`, foto: m.foto ? foto(m, "medium") : "" });
  saveSel(); pintarEscolha(code);
  if (!was) { try { $("#nSel").animate([{ transform: "scale(1)" }, { transform: "scale(1.4)" }, { transform: "scale(1)" }], { duration: 380 }); } catch (e) { /* enfeite */ } $("#selList").scrollTop = 0; }
  toast(was ? "Tirado dos selecionados" : "Adicionado aos selecionados");
}

/* ===== o envio de verdade: a Nay manda o card e as fotos para o número digitado ===== */
function meEnvia() {
  if (enviando) return;
  if (!sel.length) { toast("Selecione um imóvel no mapa ou na lista para enviar."); return; }
  if (digits(phone).length < 10) { $("#sheet").classList.remove("min"); $("#phone").classList.add("bad"); $("#err").textContent = "Digite seu WhatsApp com DDD para receber"; $("#phone").focus(); return; }
  enviando = true; renderSel();
  const n = sel.length;
  toast(`Enviando ${n} ${n === 1 ? "imóvel" : "imóveis"} com fotos para ${fmt(phone)}…`);
  fetch(API + "/api/me-envia", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ telefone: phone, codigos: sel.map(x => Number(x.codigo)).filter(Boolean) }) })
    .then(r => r.json().catch(() => ({})))
    .then(r => {
      toast(r.mensagem || (r.ok ? "Pronto! Em instantes chega no seu WhatsApp." : "Não foi possível enviar agora."));
      if (r.ok) { sel = []; saveSel(); }
    })
    .catch(() => toast("Sem conexão. Tente de novo em instantes."))
    .then(() => { enviando = false; renderAll(); });
}

/* SELECIONAR SEM REDESENHAR A TELA (Pedro, 05/10: "está meio lagado, otimize"). Cada clique refazia o mapa
   inteiro, a lista inteira (com as fotos) e todos os ícones da página. Agora muda só o que mudou: a linha do
   imóvel, os botões dele, o pino dele no mapa e o painel dos selecionados. */
function pintarEscolha(code) {
  const on = isSel(code), m = achar(code);
  const row = document.getElementById("row-" + code);
  if (row) { row.classList.toggle("sel", on); row.setAttribute("aria-pressed", on); }
  document.querySelectorAll(`[data-pick="${code}"]`).forEach(b => {
    b.setAttribute("aria-pressed", on);
    b.innerHTML = on ? i("circle-check") + "Selecionado" : i("circle-plus") + "Selecionar";
    drawIcons(b);
  });
  const g = m && lugarDe(code);
  if (g) {
    const pino = document.querySelector(`.ux-preco-pin[data-pin="${g.ims[0].codigo}"]`);
    if (pino) pino.classList.toggle("sel", g.ims.some(x => isSel(x.codigo)));
  }
  renderSel(); drawIcons($("#selList"));
}

/* ===== render geral ===== */
function renderAll() { renderMap(); renderList(); renderSel(); syncF("m", FM); syncF("s", FS); drawIcons(); }
const side = () => matchMedia("(min-width:1024px)").matches;
function measure() {
  document.documentElement.style.setProperty("--head-h", $("#site").offsetHeight + "px");
  const hbar = $("#hbar"); if (hbar) document.documentElement.style.setProperty("--hbar-h", hbar.offsetHeight + "px");
  document.documentElement.style.setProperty("--sheet-h", side() ? "0px" : $("#sheet").offsetHeight + "px");
  if (mapa) mapa.invalidateSize();
}
function montarFiltros() {
  const hpanel = $("#hpanel"); if (hpanel) hpanel.innerHTML = painelHTML();
  $("#mapF").innerHTML = fbarHTML("m");
  $("#sheetF").innerHTML = fbarHTML("s");
  $("#listF").innerHTML = fbarHTML("s");
}

/* O link pode abrir já num imóvel, numa busca ou em Alugar:
   /imoveis?codigo=9005   /imoveis?q=Ponta Negra   /imoveis?alugar */
function doEndereco() {
  const p = new URLSearchParams(location.search);
  if (p.has("alugar") && IMOVEIS.some(m => m.aluguel > 0)) {
    G.neg = "aluguel"; document.querySelectorAll("[data-neg]").forEach(b => b.setAttribute("aria-pressed", b.dataset.neg === G.neg));
    renderAll(); fit();
  }
  const q = (p.get("q") || "").trim();
  if (q) { document.querySelectorAll("[data-q]").forEach(el => { el.value = q; }); setQ(q, null); }
  if (p.get("codigo")) goTo(p.get("codigo"));
}

function carregar() {
  falhou = false; renderList();
  fetch(API + "/api/imoveis-para-enviar")
    .then(r => { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .then(d => {
      IMOVEIS = (d.imoveis || []).map(m => Object.assign({ venda: 0, aluguel: 0 }, m));
      carregou = true;
      /* o que estava selecionado e saiu do ar (alugou, vendeu) sai da lista sozinho */
      const antes = sel.length; sel = sel.filter(x => achar(x.codigo)); if (sel.length !== antes) saveSel();
      /* abre no negócio que tem imóvel (se só houver aluguel, por exemplo) */
      if (!IMOVEIS.some(m => m.venda > 0) && IMOVEIS.some(m => m.aluguel > 0)) G.neg = "aluguel";
      document.querySelectorAll("[data-neg]").forEach(b => b.setAttribute("aria-pressed", b.dataset.neg === G.neg));
      montarFiltros(); renderAll(); measure(); fit();
      doEndereco();
    })
    .catch(() => { falhou = true; renderList(); drawIcons(); });
}

$("#phone").value = fmt(phone);
/* No mapa, só a busca e, no canto direito dela, Aluguel | Vendas (Pedro, 03/10: "troca apt e casa por Aluguel \
   Vendas"). É o mesmo Comprar/Alugar da lista e das sugestões (`data-neg`): clicar em um muda os três. Os filtros
   de bairro, condomínio e tipo ficam no painel e em cima da lista. */
document.querySelector("#mtop .sbox").insertAdjacentHTML("beforeend",
  '<div class="tgrp" role="group" aria-label="Aluguel ou venda">' +
  `<button type="button" data-neg="aluguel" aria-pressed="${G.neg === "aluguel"}">Aluguel</button>` +
  `<button type="button" data-neg="venda" aria-pressed="${G.neg === "venda"}">Vendas</button></div>`);
criarMapa(); montarFiltros(); renderAll(); measure();
let rafM = 0, rafF = 0;
try {
  new ResizeObserver(() => { cancelAnimationFrame(rafM); rafM = requestAnimationFrame(measure); }).observe($("#sheet"));
  new ResizeObserver(() => { cancelAnimationFrame(rafF); rafF = requestAnimationFrame(() => { if (mapa) mapa.invalidateSize(); }); }).observe($("#map"));
} catch (e) { addEventListener("resize", () => { measure(); }); }
carregar();

/* ===== eventos ===== */
const FF = id => id === "m" ? FM : FS;
document.addEventListener("click", e => {
  if (!e.target.closest(".mtop .search")) { sugOpen = false; $("#sugs").classList.remove("open"); }
  const t = e.target.closest("button");
  const row = e.target.closest("[data-row]");
  if (t && t.dataset.ver) { const m = achar(t.dataset.ver); if (m) location.href = "/imovel/" + m.codigo + (m.slug ? "-" + m.slug : ""); return; }
  if (row && (!t || t.dataset.pick)) { togglePick(row.dataset.row); return; }
  if (!t) return;
  if (t.hasAttribute("data-de-novo")) { carregar(); return; }
  if (t.dataset.neg) { G.neg = t.dataset.neg; document.querySelectorAll("[data-neg]").forEach(b => b.setAttribute("aria-pressed", b.dataset.neg === G.neg)); focusCode = null; popCode = null; renderAll(); renderSugs(); fit(); }
  if (t.dataset.pin) { popCode = t.dataset.pin; focusCode = t.dataset.pin; renderAll(); centralizarNoCard(t.dataset.pin); }
  if (t.hasAttribute("data-closepop")) closePopup();
  if (t.dataset.pick) togglePick(t.dataset.pick);
  if (t.dataset.go) goTo(t.dataset.go);
  if (t.matches(".mchip") && t.dataset.f) { const F = FF(t.dataset.f), s = F[t.dataset.k], n = +t.dataset.n; s.has(n) ? s.delete(n) : s.add(n); renderAll(); if (t.dataset.f === "m") fit(); }
  if (t.dataset.clear) { resetF(FF(t.dataset.clear)); renderAll(); if (t.dataset.clear === "m") fit(); }
  if (t.hasAttribute("data-qclr")) setQ("", null);
  if (t.dataset.rm) { const fora = t.dataset.rm; sel = sel.filter(x => String(x.codigo) !== fora); saveSel(); pintarEscolha(fora); }
  if (t.id === "clearAll") { sel = []; saveSel(); renderAll(); }
  if (t.id === "listbtn") $("#results").scrollIntoView({ behavior: "smooth", block: "start" });
  if (t.id === "ftog") {
    if (!side()) {
      // celular: o filtro NÃO cresce dentro do painel de baixo (tapava os resultados, Pedro 03/10); a página vai
      // até a lista e o filtro dela fica preso no topo da tela enquanto ele rola os resultados
      $("#sheet").classList.remove("fopen");
      const f = $("#listF"); f.scrollIntoView({ behavior: "smooth", block: "start" });
      f.classList.remove("piscando"); void f.offsetWidth; f.classList.add("piscando");
    } else { const o = !$("#sheet").classList.contains("fopen"); $("#sheet").classList.toggle("fopen", o); t.setAttribute("aria-expanded", o); }
  }
  if (t.id === "zin" && mapa) mapa.zoomIn();
  if (t.id === "zout" && mapa) mapa.zoomOut();
  if (t.id === "zfit") { closePopup(); fit(); }
  if (t.id === "ztema") { tema = tema === "escuro" ? "cinza" : "escuro"; try { localStorage.setItem(TKEY, tema); } catch (err) { /* idem */ } aplicarTema(); }
  if (t.id === "send") meEnvia();
});
document.addEventListener("keydown", e => {
  const row = e.target.closest && e.target.closest("[data-row]");
  if (row && e.target === row && (e.key === "Enter" || e.key === " ")) { e.preventDefault(); togglePick(row.dataset.row); }
  if (e.key === "Escape") { closePopup(); abrirFiltros(false); }
});
document.addEventListener("change", e => {
  const t = e.target;
  if (t.dataset.f && (t.dataset.k === "loc" || t.dataset.k === "tipo")) { FF(t.dataset.f)[t.dataset.k] = t.value; renderAll(); if (t.dataset.f === "m") fit(); }
});
document.addEventListener("input", e => {
  const t = e.target;
  if (t.dataset.f && (t.dataset.k === "min" || t.dataset.k === "max")) { const d = t.value.replace(/\D/g, ""); t.value = d ? Number(d).toLocaleString("pt-BR") : ""; FF(t.dataset.f)[t.dataset.k] = t.value; renderMap(); renderList(); renderSel(); syncF(t.dataset.f, FF(t.dataset.f)); drawIcons(); }
  if (t.hasAttribute("data-q")) setQ(t.value, t);
  if (t.id === "phone") { phone = digits(t.value); t.value = fmt(phone); t.classList.remove("bad"); $("#err").textContent = ""; try { localStorage.setItem(PKEY, phone); } catch (err) { /* idem */ } $("#send").disabled = enviando || digits(phone).length < 10; }
});
$("#q").addEventListener("keydown", e => {
  const items = [...document.querySelectorAll(".sug")];
  if (e.key === "ArrowDown" && items.length) { e.preventDefault(); hl = Math.min(items.length - 1, hl + 1); renderSugs(); }
  if (e.key === "ArrowUp" && items.length) { e.preventDefault(); hl = Math.max(0, hl - 1); renderSugs(); }
  if (e.key === "Enter") { e.preventDefault(); if (hl >= 0 && items[hl]) goTo(items[hl].dataset.go); else { sugOpen = false; $("#sugs").classList.remove("open"); $("#q").blur(); } }
  if (e.key === "Escape") { sugOpen = false; $("#sugs").classList.remove("open"); }
});
$("#q").addEventListener("focus", () => { sugOpen = true; renderSugs(); });
$("#q").addEventListener("input", () => { sugOpen = true; });
$("#grab").addEventListener("click", () => $("#sheet").classList.toggle("min"));
/* "Minimizar" (05/10): recolhe a lista dos selecionados; o mesmo botão a traz de volta */
$("#minbtn").addEventListener("click", () => {
  const recolhido = $("#sheet").classList.toggle("min");
  $("#minbtn").textContent = recolhido ? "Mostrar" : "Minimizar";
  $("#minbtn").setAttribute("aria-expanded", !recolhido);
  measure();
});

/* O MAPA ACORDA COM UM CLIQUE (Pedro, 03/10: "quando a pessoa clicar dentro do mapa e rolar para baixo, ele
   role o mapa"). Antes do clique, a rodinha e o dedo rolam a PÁGINA (a lista fica embaixo). Depois do clique
   dentro do mapa, a rodinha aproxima/afasta e o dedo arrasta o mapa; sair dele (mouse fora, ou tocar fora no
   celular) devolve a rolagem à página. A etiqueta de baixo do mapa diz em qual dos dois está. */
let mapaAtivo = false, hintT = null;
function hideHint() { const h = $("#mhint"); if (h) h.classList.remove("on"); }
function ativarMapa(on) {
  if (!mapa || on === mapaAtivo) return;
  mapaAtivo = on;
  // a rodinha não entra aqui: clicar no mapa só solta o arrasto com um dedo no celular
  mapEl.classList.toggle("map--ativo", on);
  const tag = document.querySelector(".maptag");
  if (tag) tag.textContent = toque
    ? "Arraste para mover · dois dedos dão zoom"
    : "Arraste para mover · zoom nos botões + e −";
}
mapEl.addEventListener("mouseleave", () => ativarMapa(false));
document.addEventListener("pointerdown", e => { if (!mapEl.contains(e.target)) ativarMapa(false); }, true);
ativarMapa(true); ativarMapa(false);          // escreve a etiqueta do jeito de agora
})();
